---@class dsh.Config
---@field dsh_cmd string|nil          dsh 可执行文件；nil 表示自动探测
---@field profile string              dsh profile（默认 headless）
---@field launcher_args string[]      额外的启动器参数（--patch 等）
---@field cwd string                  "root" | "buffer" | "cwd" | 绝对路径
---@field timeout_ms number|nil       任务超时（毫秒）
---@field include_file_content boolean 小文件是否内联进提示词
---@field max_inline_file_chars number 内联文件的最大字符数
---@field close_key string            关闭结果浮窗的按键
---@field prompts table               提示词模板
---@field keymaps table               按键映射（nil/false/"" 表示禁用）
---@field window table                浮窗配置
---@field tui table                   dsh-tianshu-tui 终端集成配置

local M = {}

M.defaults = {
  dsh_cmd = nil,
  profile = "headless",
  launcher_args = {},
  cwd = "root",
  timeout_ms = nil,
  include_file_content = true,
  max_inline_file_chars = 20000,
  close_key = "q",
  prompts = {
    file = "请查看文件 `%s` 并给出你的分析与改进建议。",
    file_with_content = "以下是文件 `%s` 的完整内容：\n\n```\n%s\n```\n\n请查看该文件并给出你的分析与改进建议。",
    selection = "以下是 `%s` 中的一段代码：\n\n```\n%s\n```\n\n请查看这段代码并给出你的分析与建议。",
  },
  keymaps = {
    ask = "<leader>da",
    ask_file = "<leader>df",
    ask_visual = "<leader>ds",
    tui = "<leader>tt",
    tui_file = "<leader>tf",
    tui_visual = "<leader>ts",
  },
  tui = {
    profile = "tui",                             -- dsh profile（tianshu TUI 装在 tui profile 里）
    launcher_args = {},                          -- 额外启动器参数，例如 { "--patch", "/path/x.yml" }
    cwd = "root",                                -- 运行目录："root" | "buffer" | "cwd" | 绝对路径
    layout = "split",                            -- 默认布局："float" | "split" | "vsplit" | "tab"
    close_key = "q",                             -- 终端 normal 模式下关闭/收起窗口的按键
    file_mode = "mention",                       -- 添加文件方式："mention"(引用) | "content"(粘贴全文)
    skip_update = false,                         -- true = 启动时跳过 npm 版本检查（设 DSH_TUI_SKIP_UPDATE=1）
    plugin_name = "@huiliyi37/dsh-tianshu-tui",  -- 安装命令使用的包名
    float = {
      relative = "editor",
      width = 0.94,      -- 小数按编辑器尺寸换算；也支持整数（字符列）
      height = 0.9,
      row = 0.03,        -- (1 - height) / 2 附近
      col = 0.03,        -- (1 - width) / 2 附近
      anchor = "NW",
      border = "rounded",
      title = " dsh-tianshu-tui ",
      title_pos = "center",
      style = "minimal",
      focusable = true,
    },
    split = { position = "below", size = 0.4 },  -- position: "below" | "above"
    vsplit = { position = "right", size = 0.5 }, -- position: "right" | "left"
  },
  window = {
    relative = "editor",
    width = 0.72,
    height = 0.5,
    row = 0.25, -- (1 - height) / 2，配合 anchor="NW" 实现居中
    col = 0.14, -- (1 - width) / 2
    anchor = "NW",
    border = "rounded",
    title = " dsh ",
    title_pos = "center",
    style = "minimal",
    focusable = true,
  },
}

M._options = nil

local function deep_merge(defaults, user)
  return vim.tbl_deep_extend("force", vim.deepcopy(defaults), user or {})
end

--- 合并并保存配置，返回合并结果（幂等）。
function M.setup(opts)
  M._options = deep_merge(M.defaults, opts)
  return M._options
end

--- 返回当前配置；未调用 setup 时自动使用默认值。
function M.get()
  if M._options == nil then
    M._options = deep_merge(M.defaults, nil)
  end
  return M._options
end

return M
