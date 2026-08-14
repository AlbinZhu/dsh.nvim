--- dsh-tianshu-tui 集成：在 Neovim 内置终端里运行 `dsh --profile tui`。
---
--- 与 headless 一次性任务不同，tianshu TUI 是一个全屏交互式终端应用
--- （ANSI 转义、bracketed paste、鼠标等），因此把它跑进 `:terminal` 缓冲区，
--- 支持 float / split / vsplit / tab 四种布局，并可反复 toggle（收起/恢复）。
---
--- 使用前需要先把 TUI 插件装进 tui profile（见 README / `:DshTuiInstall`）。

local M = {}

--- 当前主 TUI 的终端状态（buf / win / chan）。
local state = { buf = nil, win = nil, chan = nil, layout = nil }

local function config()
  return require("dsh.config").get()
end

local function shellquote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

--- 把 0 < v < 1 的小数按总量换算成整数；其它值原样返回。
local function resolve_dim(value, total)
  if type(value) == "number" and value > 0 and value < 1 then
    return math.max(1, math.floor(value * total))
  end
  return value
end

--- 拼装启动命令。返回 List（可直接 exec）或 shell 字符串；失败返回 nil, err。
---@param cfg table 合并后的配置
local function build_cmd(cfg)
  local cmd = require("dsh.runner").resolve_dsh_cmd(cfg)
  if not cmd then
    return nil, "找不到 dsh 可执行文件，请在 require('dsh').setup({ dsh_cmd = '/path/to/dsh' }) 中指定。"
  end

  local t = cfg.tui or {}
  local profile = t.profile or "tui"
  local extra = t.launcher_args or {}

  -- dsh_cmd 含空格说明是 shell 前缀（例如 "npx -y @deepseek-ai/dsh"），
  -- 走 shell 字符串；否则用 List 直接 exec，避免 shell 转义问题。
  if cmd:find("%s") then
    local parts = { cmd, "--profile", shellquote(profile) }
    for _, a in ipairs(extra) do
      table.insert(parts, shellquote(a))
    end
    return table.concat(parts, " "), nil
  end

  local argv = { cmd, "--profile", profile }
  vim.list_extend(argv, extra)
  return argv, nil
end

--- 运行目录；TUI 继承这个 cwd 来定位项目。
local function resolve_cwd(cfg)
  local t = cfg.tui or {}
  return require("dsh.context").resolve_cwd(t.cwd or cfg.cwd or "root")
end

--- termopen 选项（cwd + 可选环境变量）。
local function term_opts(cfg, extra)
  local opts = vim.tbl_extend("force", {
    cwd = resolve_cwd(cfg),
  }, extra or {})

  if cfg.tui and cfg.tui.skip_update then
    opts.env = vim.tbl_extend("force", opts.env or {}, { DSH_TUI_SKIP_UPDATE = "1" })
  end
  return opts
end

--- 复用已有缓冲区，否则新建 scratch 缓冲区。
local function ensure_buf(buf)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end
  local b = vim.api.nvim_create_buf(false, true)
  vim.bo[b].bufhidden = "hide"
  return b
end

--- float 布局：在（新或复用的）缓冲区上开浮动窗口。
local function open_float(cfg, title, buf)
  local f = cfg.tui.float
  local uis = vim.api.nvim_list_uis()
  local total_w = (uis[1] and uis[1].width) or 80
  local total_h = (uis[1] and uis[1].height) or 24

  local win_config = vim.tbl_deep_extend("force", vim.deepcopy(f), {
    width = resolve_dim(f.width, total_w),
    height = resolve_dim(f.height, total_h),
    row = resolve_dim(f.row, total_h),
    col = resolve_dim(f.col, total_w),
    title = title or f.title,
  })

  local win = vim.api.nvim_open_win(buf, true, win_config)
  return buf, win
end

--- split / vsplit 布局：开分屏并把缓冲区放进去。
local function open_split(cfg, vertical, buf)
  local s = vertical and cfg.tui.vsplit or cfg.tui.split
  local pos = s.position

  if vertical then
    if pos == "left" then
      vim.cmd("leftabove vsplit")
    else
      vim.cmd("vsplit")
    end
  else
    if pos == "above" then
      vim.cmd("leftabove split")
    else
      vim.cmd("split")
    end
  end

  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)

  -- 尺寸：小数按当前窗口换算，整数原样使用。
  local size = s.size
  if type(size) == "number" and size > 0 and size < 1 then
    if vertical then
      size = math.max(1, math.floor(size * vim.api.nvim_win_get_width(win)))
    else
      size = math.max(1, math.floor(size * vim.api.nvim_win_get_height(win)))
    end
  end
  if type(size) == "number" and size > 0 then
    if vertical then
      vim.api.nvim_win_set_width(win, size)
    else
      vim.api.nvim_win_set_height(win, size)
    end
  end

  return buf, win
end

--- tab 布局：新标签页放缓冲区。
local function open_tab(buf)
  vim.cmd("tabnew")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  return buf, win
end

--- 按布局新建/复用窗口，返回 buf, win。
local function open_window(cfg, layout, title, existing_buf)
  local buf = ensure_buf(existing_buf)
  if layout == "split" then
    return open_split(cfg, false, buf)
  elseif layout == "vsplit" then
    return open_split(cfg, true, buf)
  elseif layout == "tab" then
    return open_tab(buf)
  end
  return open_float(cfg, title, buf)
end

--- 给终端缓冲区挂上关闭按键（terminal-normal 模式）。
local function attach_close_keymap(buf, t)
  local close_key = t.close_key or "q"
  local close = function()
    M.close()
  end
  vim.keymap.set("t", close_key, close, { buffer = buf, desc = "dsh-tui: close/hide", nowait = true })
  vim.keymap.set("t", "<Esc>", close, { buffer = buf, desc = "dsh-tui: close/hide" })
end

--- 在指定布局里启动一个命令终端。返回 { buf, win, chan }。
---@param cmd string|string[] 命令（shell 字符串或 List）
---@param opts table { layout?, title?, filetype?, on_exit?, existing_buf? }
local function launch(cmd, opts)
  local cfg = config()
  opts = opts or {}
  local t = cfg.tui or {}

  local layout = opts.layout or t.layout or "float"
  local buf, win = open_window(cfg, layout, opts.title, opts.existing_buf)

  vim.api.nvim_set_current_buf(buf)

  -- 只在全新缓冲区上设置 filetype 与启动进程；
  -- 复用既有终端缓冲区时它已经是一个活的 terminal。
  if not opts.existing_buf then
    vim.bo[buf].filetype = opts.filetype or "dsh-tui"
    local top = term_opts(cfg, { on_exit = opts.on_exit })
    local chan = vim.fn.termopen(cmd, top)
    attach_close_keymap(buf, t)
    return { buf = buf, win = win, chan = chan, layout = layout }
  end

  attach_close_keymap(buf, t)
  return { buf = buf, win = win, chan = state.chan, layout = layout }
end

--- 打开（或聚焦）dsh TUI。
---@param opts table { layout?, text? } 可选；text 会在启动后尝试输入
function M.open(opts)
  local cfg = config()
  opts = opts or {}
  local t = cfg.tui or {}

  -- 已有一个可见且活着的 TUI：直接聚焦。
  if state.win and vim.api.nvim_win_is_valid(state.win) and state.chan then
    vim.api.nvim_set_current_win(state.win)
    if opts.text and opts.text ~= "" then
      M.send(opts.text)
    end
    return state
  end

  -- 清理上一次已退出的死缓冲区（pty 已关闭，无法复用）。
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) and not state.chan then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
    state.buf = nil
    state.win = nil
  end

  local layout = opts.layout or t.layout or "float"

  -- 进程还在跑、只是窗口被收起：在同一终端缓冲区上重建窗口，避免重复启动。
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) and state.chan then
    local buf, win = open_window(cfg, layout, t.float.title, state.buf)
    vim.api.nvim_set_current_buf(buf)
    attach_close_keymap(buf, t)
    state.buf, state.win, state.layout = buf, win, layout
    if opts.text and opts.text ~= "" then
      M.send(opts.text)
    end
    return state
  end

  local cmd, err = build_cmd(cfg)
  if not cmd then
    vim.notify("dsh-tui: " .. err, vim.log.levels.ERROR)
    return nil
  end

  local result = launch(cmd, {
    layout = layout,
    title = t.float.title,
    on_exit = function(_job, code, _event)
      vim.schedule(function()
        state.chan = nil
        if code ~= 0 then
          vim.notify(
            string.format("dsh-tui 已退出（exit code %s）。若提示 profile/插件缺失，请先运行 :DshTuiInstall。", tostring(code)),
            vim.log.levels.ERROR
          )
        end
      end)
    end,
  })

  state.buf, state.win, state.chan, state.layout = result.buf, result.win, result.chan, result.layout

  -- 打开后把 text 输入到 TUI 的输入行（稍等其启动完成）。
  if opts.text and opts.text ~= "" then
    vim.defer_fn(function()
      if state.chan then
        M.send(opts.text)
      end
    end, 400)
  end

  return state
end

--- 收起/关闭当前 TUI 窗口（进程继续在后台运行，可再次 toggle 恢复）。
function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
end

--- toggle：开着就收起，收起/关闭了就恢复或重开。
function M.toggle(opts)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.close()
  else
    M.open(opts)
  end
end

--- 向运行中的 TUI 发送文本（输入到输入行，不自动回车）。
--- 注意：直接按字节发送，适合简短纯文本；多行/含转义的代码请用 paste()。
function M.send(text)
  if not state.chan then
    return false
  end
  vim.api.nvim_chan_send(state.chan, text)
  return true
end

-- bracketed paste 起止标记（DEC 2004）。tianshu TUI 会把它当作整段粘贴，
-- 多行代码/含转义字符的文本都能安全地进输入行，不会逐行提交或被终端转义吃掉。
local PASTE_START = "\27[200~"
local PASTE_END = "\27[201~"

--- 把文本以 bracketed paste 安全粘贴进输入行（不自动回车）。
function M.paste(text)
  if not state.chan then
    return false
  end
  vim.api.nvim_chan_send(state.chan, PASTE_START .. text .. PASTE_END)
  return true
end

--- 确保 TUI 已打开且可见后执行 fn。
--- 已可见就立即；进程在后台跑但窗口收起就先恢复窗口再发；
--- 尚未启动则打开并等启动完成再发。
local function when_ready(fn, opts)
  if state.chan and state.win and vim.api.nvim_win_is_valid(state.win) then
    fn()
    return
  end
  local was_running = state.chan ~= nil
  M.open(opts)
  if was_running then
    fn()
  else
    vim.defer_fn(function()
      if state.chan then
        fn()
      end
    end, 500)
  end
end

--- 把文件引用为 @mention（提交时 TUI 会展开为内容摘要）。
--- 路径含空格/引号时用引号形 `@"..."` 包裹。
local function mention_of(path)
  return '@"' .. tostring(path):gsub("\\", "\\\\"):gsub('"', '\\"') .. '" '
end

--- 向 TUI 添加一个文件。
--- 默认以 @mention 引用；file_mode == "content" 时粘贴完整内容。
---@param path string|nil 文件路径；nil = 当前缓冲区关联文件
function M.add_file(path)
  local cfg = config()
  local t = cfg.tui or {}

  local p = path
  if not p or p == "" then
    p = require("dsh.context").current_file()
  end
  if not p then
    vim.notify("dsh-tui: 当前缓冲区没有关联文件。", vim.log.levels.WARN)
    return nil
  end

  if t.file_mode == "content" then
    local content = require("dsh.context").file_content(p)
    if not content then
      vim.notify("dsh-tui: 无法读取文件 " .. p, vim.log.levels.ERROR)
      return nil
    end
    -- 同步读取后再打开 TUI，避免 defer 期间缓冲区变化。
    when_ready(function()
      M.paste(content)
    end)
    return true
  end

  local mention = mention_of(p)
  when_ready(function()
    M.paste(mention)
  end)
  return true
end

--- 把当前视觉选择粘贴进 TUI 输入行（bracketed paste）。
function M.add_selection()
  -- 同步抓取选择，避免 defer 到 TUI 启动完成后选区已失效。
  local sel = require("dsh.context").visual_selection()
  if not sel or sel == "" then
    vim.notify("dsh-tui: 没有可用的视觉选择（请先 visual 选中文本）。", vim.log.levels.WARN)
    return nil
  end
  when_ready(function()
    M.paste(sel)
  end)
  return true
end

--- 是否有一个可见的 TUI 窗口。
function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

--- 安装 TUI 插件：`dsh plugin --profile tui add <plugin_name>`。
--- 在 split 终端里运行，方便查看 pnpm/npm 输出与交互。
function M.install()
  local cfg = config()
  local cmd = require("dsh.runner").resolve_dsh_cmd(cfg)
  if not cmd then
    vim.notify("dsh-tui: 找不到 dsh 可执行文件，无法安装插件。", vim.log.levels.ERROR)
    return nil
  end

  local t = cfg.tui or {}
  local profile = t.profile or "tui"
  local plugin = t.plugin_name or "@huiliyi37/dsh-tianshu-tui"

  local argv
  if cmd:find("%s") then
    argv = string.format("%s plugin --profile %s add %s", cmd, shellquote(profile), shellquote(plugin))
  else
    argv = { cmd, "plugin", "--profile", profile, "add", plugin }
  end

  local result = launch(argv, { layout = "split", filetype = "dsh-tui-install" })
  vim.notify(
    string.format("正在安装 %s 到 profile `%s`（在下方终端查看进度）…", plugin, profile),
    vim.log.levels.INFO
  )
  return result
end

--- 暴露内部状态（供诊断）。
function M.state()
  return state
end

return M
