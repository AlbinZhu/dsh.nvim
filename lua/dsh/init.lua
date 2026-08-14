--- dsh.nvim — 在 Neovim 中调用 `dsh --profile headless` 完成一次性任务。
---@brief [[
--- 用法：
---   :Dsh  <问题>            直接提问（无参数时弹出输入框）
---   :DshFile                让 dsh 审查当前文件
---   :'<,'>DshSelection      让 dsh 处理选中的文本
---   :DshCancel              取消正在运行的任务
---@brief ]]

local M = {}

local registered_keymaps = {}

local function config()
  return require("dsh.config").get()
end

--- 清除上一次注册的按键映射。
local function clear_keymaps()
  for _, km in ipairs(registered_keymaps) do
    pcall(vim.keymap.del, km[1], km[2])
  end
  registered_keymaps = {}
end

--- 按配置注册按键映射（值设为 nil/false/"" 可禁用）。
local function apply_keymaps(cfg)
  clear_keymaps()
  local km = cfg.keymaps or {}
  local defs = {
    { "n", km.ask, function() M.ask() end, "dsh: ask" },
    { "n", km.ask_file, function() M.ask_file() end, "dsh: ask about current file" },
    { "x", km.ask_visual, function() M.ask_visual() end, "dsh: ask about selection" },
    { "n", km.tui, function() M.toggle_tui() end, "dsh: toggle tianshu TUI" },
    { "n", km.tui_file, function() M.tui_add_file() end, "dsh: add file to tianshu TUI" },
    { "x", km.tui_visual, function() M.tui_add_selection() end, "dsh: add selection to tianshu TUI" },
  }
  for _, d in ipairs(defs) do
    local lhs = d[2]
    if type(lhs) == "string" and lhs ~= "" then
      vim.keymap.set(d[1], lhs, d[3], { desc = d[4], silent = true })
      table.insert(registered_keymaps, { d[1], lhs })
    end
  end
end

--- 配置并初始化插件（幂等，可重复调用）。
---@param opts table 覆盖默认配置，见 README.md
function M.setup(opts)
  local cfg = require("dsh.config").setup(opts)
  apply_keymaps(cfg)
  return cfg
end

--- 运行一个任务（核心入口）。
---@param task string 发送给 dsh 的任务文本
function M.run(task)
  local cfg = config()
  if type(task) ~= "string" or task == "" then
    vim.notify("dsh: 任务文本为空", vim.log.levels.WARN)
    return nil
  end

  local ui = require("dsh.ui")
  local runner = require("dsh.runner")

  ui.open(cfg)

  runner.run(cfg, task, {
    on_exit = function(code, signal, stdout, stderr)
      if code == 0 then
        ui.set_result(stdout ~= "" and stdout or "(no output)")
      else
        ui.set_error(code, signal, stderr)
      end
    end,
    on_error = function(msg)
      ui.set_error(nil, nil, nil, msg)
    end,
  })
  return true
end

--- 提问；无参数时弹出输入框。
function M.ask(prompt)
  prompt = prompt or ""
  if prompt ~= "" then
    M.run(prompt)
    return
  end
  vim.ui.input({ prompt = "dsh> " }, function(input)
    if input and input ~= "" then
      M.run(input)
    end
  end)
end

--- 让 dsh 审查当前文件。
function M.ask_file()
  local cfg = config()
  local ctx = require("dsh.context")
  local path = ctx.current_file()
  if not path then
    vim.notify("dsh: 当前缓冲区没有关联文件", vim.log.levels.WARN)
    return
  end

  local task
  if cfg.include_file_content then
    local content = ctx.file_content(path)
    if content and content:find("\0", 1, true) == nil and #content <= cfg.max_inline_file_chars then
      task = string.format(cfg.prompts.file_with_content, path, content)
    else
      task = string.format(cfg.prompts.file, path)
    end
  else
    task = string.format(cfg.prompts.file, path)
  end
  M.run(task)
end

--- 让 dsh 处理当前视觉选择。
function M.ask_visual()
  local cfg = config()
  local ctx = require("dsh.context")
  local sel = ctx.visual_selection()
  if not sel or sel == "" then
    vim.notify("dsh: 没有可用的视觉选择（请先进入 visual 模式选中文本）", vim.log.levels.WARN)
    return
  end
  local path = ctx.current_file() or "current buffer"
  M.run(string.format(cfg.prompts.selection, path, sel))
end

--- 取消正在运行的任务。
function M.cancel()
  local cancelled = require("dsh.runner").cancel()
  require("dsh.ui").close()
  return cancelled
end

--- dsh-tianshu-tui 终端集成模块（详见 require("dsh.tui")）。
M.tui = require("dsh.tui")

--- 打开（或聚焦）TUI。opts 可为 { layout = "float|split|vsplit|tab", text = "..." }。
function M.open_tui(opts)
  return M.tui.open(opts)
end

--- 收起/关闭 TUI 窗口。
function M.close_tui()
  return M.tui.close()
end

--- toggle TUI。
function M.toggle_tui(opts)
  return M.tui.toggle(opts)
end

--- 安装 tianshu TUI 插件到 tui profile。
function M.tui_install()
  return M.tui.install()
end

--- 向 TUI 添加一个文件（默认 @mention 引用，见 tui.file_mode）。
function M.tui_add_file(path)
  return M.tui.add_file(path)
end

--- 把当前视觉选择粘贴进 TUI 输入行。
function M.tui_add_selection()
  return M.tui.add_selection()
end

--- 把文本安全粘贴进 TUI 输入行（bracketed paste）。
function M.tui_paste(text)
  return M.tui.paste(text)
end

return M
