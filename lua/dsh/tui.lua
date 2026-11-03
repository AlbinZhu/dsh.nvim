--- dsh-TUI 集成：在 Neovim 内置终端里运行 `dsh --profile dsh-tui`。
---
--- 与 headless 一次性任务不同，dsh-TUI 是一个全屏交互式终端应用
--- （ANSI 转义、bracketed paste、鼠标等），因此把它跑进 `:terminal` 缓冲区，
--- 支持 float / split / vsplit / tab 四种布局，并可反复 toggle（收起/恢复）。
---
--- 使用前需要先把 TUI 插件装进 dsh-tui profile（见 README / `:DshTuiInstall`）。

local M = {}

--- 当前主 TUI 的终端状态（buf / win / chan）。
local state = { buf = nil, win = nil, chan = nil, layout = nil }

--- 连按两次 Ctrl+C 退出的时间窗口（毫秒）：窗口内的第二次按下才会退出。
local DOUBLE_CTRL_C_MS = 1000

local function config()
  return require("dsh.config").get()
end

local function shellquote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

--- 聚焦 TUI 窗口后进入终端模式，让按键直接输入给 TUI（tui.auto_insert = false 时停在 normal 模式）。
local function enter_insert()
  if (config().tui or {}).auto_insert ~= false then
    vim.cmd("startinsert")
  end
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
---@param app_args string[]|nil 传给 TUI 应用本身的参数（例如 { "--resume" }），排在启动器参数之后
local function build_cmd(cfg, app_args)
  local cmd = require("dsh.runner").resolve_dsh_cmd(cfg)
  if not cmd then
    return nil, "找不到 dsh 可执行文件，请在 require('dsh').setup({ dsh_cmd = '/path/to/dsh' }) 中指定。"
  end

  local t = cfg.tui or {}
  local profile = t.profile or "dsh-tui"
  local extra = t.launcher_args or {}
  app_args = app_args or {}

  -- dsh_cmd 含空格说明是 shell 前缀（例如 "npx -y @deepseek-ai/dsh"），
  -- 走 shell 字符串；否则用 List 直接 exec，避免 shell 转义问题。
  if cmd:find("%s") then
    local parts = { cmd, "--profile", shellquote(profile) }
    for _, a in ipairs(extra) do
      table.insert(parts, shellquote(a))
    end
    for _, a in ipairs(app_args) do
      table.insert(parts, shellquote(a))
    end
    return table.concat(parts, " "), nil
  end

  local argv = { cmd, "--profile", profile }
  vim.list_extend(argv, extra)
  vim.list_extend(argv, app_args)
  return argv, nil
end

--- 运行目录；TUI 继承这个 cwd 来定位项目。
local function resolve_cwd(cfg)
  local t = cfg.tui or {}
  return require("dsh.context").resolve_cwd(t.cwd or cfg.cwd or "root")
end

--- termopen 选项（cwd）。
local function term_opts(cfg, extra)
  return vim.tbl_extend("force", {
    cwd = resolve_cwd(cfg),
  }, extra or {})
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

--- 给终端缓冲区挂上收起按键：只在 terminal-normal 模式（先按 <C-\><C-n>）下生效。
--- 不能绑在 terminal-job 模式（"t"）：那里所有按键都要原样交给 TUI，
--- 绑上 q / <Esc> 会让 TUI 里打不出 q，也用不了 Esc（取消、关闭对话框、双击 Esc 回退等）。
local function attach_close_keymap(buf, t)
  local close_key = t.close_key or "q"
  vim.keymap.set("n", close_key, function()
    M.close()
  end, { buffer = buf, desc = "dsh-tui: close/hide", nowait = true })
end

--- 给 TUI 终端缓冲区挂上“连按两次 Ctrl+C 退出”（terminal 模式，即直接输入给 TUI 时）。
--- 第一次按下照常转发给 TUI（保留它自己的 Ctrl+C 行为，例如中断生成）；
--- DOUBLE_CTRL_C_MS 内的第二次按下则调用 M.exit() 退出。
--- 上次按下的时间只存在于本函数的闭包里，所以每个新会话都从零开始计。
local function attach_exit_keymap(buf, chan)
  local last_press = nil
  vim.keymap.set("t", "<C-c>", function()
    local now = (vim.uv or vim.loop).now()
    if last_press and now - last_press <= DOUBLE_CTRL_C_MS then
      M.exit()
      return
    end
    last_press = now
    pcall(vim.api.nvim_chan_send, chan, "\3")
  end, { buffer = buf, desc = "dsh-tui: 连按两次 Ctrl+C 退出" })
end

--- 关闭窗口并删除终端缓冲区（进程已结束或即将结束时调用）。
local function teardown(buf, win)
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
end

--- 在指定布局里启动一个命令终端。返回 { buf, win, chan }。
---@param cmd string|string[] 命令（shell 字符串或 List）
---@param opts table { layout?, title?, filetype?, on_exit?, existing_buf? }
local function launch(cmd, opts)
  local cfg = config()
  opts = opts or {}
  local t = cfg.tui or {}

  local layout = opts.layout or t.layout or "vsplit"
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
---@param opts? table { layout?, text?, args? } layout 覆盖默认布局；text 会在启动后输入到输入行；
---  args 是传给 TUI 应用本身的参数（如 { "--resume" }），只在新启动进程时生效
function M.open(opts)
  local cfg = config()
  opts = opts or {}
  local t = cfg.tui or {}

  -- 已有一个可见且活着的 TUI：直接聚焦。
  if state.win and vim.api.nvim_win_is_valid(state.win) and state.chan then
    vim.api.nvim_set_current_win(state.win)
    enter_insert()
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

  local layout = opts.layout or t.layout or "vsplit"

  -- 进程还在跑、只是窗口被收起：在同一终端缓冲区上重建窗口，避免重复启动。
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) and state.chan then
    local buf, win = open_window(cfg, layout, t.float.title, state.buf)
    vim.api.nvim_set_current_buf(buf)
    attach_close_keymap(buf, t)
    state.buf, state.win, state.layout = buf, win, layout
    enter_insert()
    if opts.text and opts.text ~= "" then
      M.send(opts.text)
    end
    return state
  end

  -- opts.args（例如 { "--resume" }）只在这里、即新启动进程时才会用到。
  local cmd, err = build_cmd(cfg, opts.args)
  if not cmd then
    vim.notify("dsh-tui: " .. err, vim.log.levels.ERROR)
    return nil
  end

  local result = launch(cmd, {
    layout = layout,
    title = t.float.title,
    on_exit = function(job, code, _event)
      vim.schedule(function()
        -- 会话已被 M.exit() 结束、或已被新会话替换：不动当前状态，也不报“异常退出”。
        if state.chan ~= job then
          return
        end
        state.chan = nil
        if code == 0 then
          -- 正常退出（例如 TUI 自己连按两次 Ctrl+C）：面板跟着关闭，不留下空的终端窗口。
          local buf, win = state.buf, state.win
          state.buf, state.win, state.layout = nil, nil, nil
          teardown(buf, win)
          return
        end
        -- 异常退出：保留窗口，让用户看到 TUI 打印的错误信息；下次 open 时再清理。
        vim.notify(
          string.format("dsh-tui 已退出（exit code %s）。若提示 profile/插件缺失，请先运行 :DshTuiInstall。", tostring(code)),
          vim.log.levels.ERROR
        )
      end)
    end,
  })

  state.buf, state.win, state.chan, state.layout = result.buf, result.win, result.chan, result.layout
  attach_exit_keymap(result.buf, result.chan)
  enter_insert()

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

--- 退出 TUI：结束 dsh-tui 进程，关闭窗口并删除终端缓冲区。
--- 与 close（收起、进程继续运行）不同；下次 open 会重新启动进程。
function M.exit()
  local buf, win, chan = state.buf, state.win, state.chan
  -- 先清空状态：之后到达的 on_exit 会识别出这是已结束的会话，不会误伤新会话。
  state.buf, state.win, state.chan, state.layout = nil, nil, nil, nil
  if chan then
    pcall(vim.fn.jobstop, chan)
  end
  teardown(buf, win)
end

--- toggle：开着就收起，收起/关闭了就恢复或重开。
function M.toggle(opts)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.close()
  else
    M.open(opts)
  end
end

--- 智能聚焦（对应 claudecode.nvim 的 :ClaudeCodeFocus）：
--- 窗口可见且光标已在其中 → 收起；窗口可见但光标在别处 → 聚焦；
--- 已被收起或还没启动 → 打开并聚焦。
function M.focus(opts)
  if M.is_open() then
    if vim.api.nvim_get_current_win() == state.win then
      M.close()
    else
      vim.api.nvim_set_current_win(state.win)
      enter_insert()
    end
    return state
  end
  return M.open(opts)
end

--- 恢复会话（对应 claudecode.nvim 的 :ClaudeCode --resume）：以 `--resume [id]` 启动 TUI。
--- 不带 id 即恢复上一次会话（在 dsh-tui 里与 -c / --continue 等价）。
--- 启动参数只对新启动的进程生效：TUI 已在运行时只打开/聚焦它，并提示改用 TUI 里的 /resume。
---@param session_id string|nil 会话 id；nil 或 "" 表示上一次会话
function M.resume(session_id)
  if state.chan then
    M.open()
    vim.notify(
      "dsh-tui: TUI 已在运行，--resume 只对新启动的进程生效；请在 TUI 里输入 /resume 选择会话。",
      vim.log.levels.WARN
    )
    return state
  end
  local args = { "--resume" }
  if session_id and session_id ~= "" then
    args[#args + 1] = session_id
  end
  return M.open({ args = args })
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

-- bracketed paste 起止标记（DEC 2004）。dsh-TUI 会把它当作整段粘贴，
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

--- 规整行区间：1-based、闭区间、start <= end；没有起始行时返回 nil。
local function normalize_range(start_line, end_line)
  if not start_line then
    return nil
  end
  local first = math.max(1, math.floor(start_line))
  local last = math.max(1, math.floor(end_line or first))
  if last < first then
    first, last = last, first
  end
  return first, last
end

--- 把文件引用为 @mention（提交时 TUI 会把它展开为附件）。
--- 路径统一用引号形 `@"..."` 包裹（含空格也安全）；可选的行区间以 `#L12-14`
--- （单行 `#L12`）接在引号后面，与 dsh-TUI 的 mention 语法一致。
local function mention_of(path, start_line, end_line)
  local mention = '@"' .. tostring(path):gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
  local first, last = normalize_range(start_line, end_line)
  if first then
    mention = mention .. (last > first and string.format("#L%d-%d", first, last) or string.format("#L%d", first))
  end
  return mention .. " "
end

--- 向 TUI 添加一个文件。
--- 默认以 @mention 引用；file_mode == "content" 时粘贴完整内容。
---@param path string|nil 文件路径；nil = 当前缓冲区关联文件
---@param start_line integer|nil 起始行（1-based）；与 end_line 一起只引用/粘贴这一段
---@param end_line integer|nil 结束行（含）；省略时只取 start_line 这一行
function M.add_file(path, start_line, end_line)
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
    local first, last = normalize_range(start_line, end_line)
    if first then
      local lines = vim.split(content, "\n", { plain = true })
      if lines[#lines] == "" then
        table.remove(lines) -- 文件以换行结尾时 split 会多出一个空元素，它不是一行
      end
      content = table.concat(vim.list_slice(lines, first, math.min(last, #lines)), "\n")
    end
    -- 同步读取后再打开 TUI，避免 defer 期间缓冲区变化。
    when_ready(function()
      M.paste(content)
    end)
    return true
  end

  local mention = mention_of(p, start_line, end_line)
  when_ready(function()
    M.paste(mention)
  end)
  return true
end

--- 把多个文件/目录一次性引用为 @mention（文件树多选、已标记的文件等）。
--- 始终用 @mention 形式，不受 file_mode 影响：整个目录的内容不适合直接粘贴。
---@param paths string[]
function M.add_files(paths)
  if type(paths) ~= "table" or #paths == 0 then
    return nil
  end
  local parts = {}
  for _, p in ipairs(paths) do
    parts[#parts + 1] = mention_of(p)
  end
  local text = table.concat(parts)
  when_ready(function()
    M.paste(text)
  end)
  return true
end

--- 把文件树里光标下（或 visual 选中、已标记）的文件/目录添加到 TUI 输入行。
---@param range integer[]|nil { first, last }：visual 选中的行；nil 表示只取光标所在项
function M.add_tree(range)
  local files, err = require("dsh.tree").selected_files(range)
  if not files then
    vim.notify("dsh-tui: " .. err, vim.log.levels.WARN)
    return nil
  end
  return M.add_files(files)
end

--- 把当前视觉选择添加到 TUI 输入行（bracketed paste，不自动回车）。
--- 在文件树里选中的是文件名行而不是代码，所以改为添加选中的文件（同 add_tree）。
--- tui.selection_mode = "mention" 时不粘贴代码，而是引用 @文件#L起-止。
function M.add_selection()
  local ctx = require("dsh.context")

  if require("dsh.tree").is_explorer() then
    local first, last = ctx.visual_range()
    return M.add_tree(first and { first, last } or nil)
  end

  -- 同步抓取选择，避免 defer 到 TUI 启动完成后选区已失效。
  local sel = ctx.visual_selection()
  if not sel or sel == "" then
    vim.notify("dsh-tui: 没有可用的视觉选择（请先 visual 选中文本）。", vim.log.levels.WARN)
    return nil
  end

  if (config().tui or {}).selection_mode == "mention" then
    local path = ctx.current_file()
    local first, last = ctx.visual_range()
    -- 没有关联文件的缓冲区（未命名）无法引用，退回粘贴代码。
    if path and first then
      local mention = mention_of(path, first, last)
      when_ready(function()
        M.paste(mention)
      end)
      return true
    end
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
  local profile = t.profile or "dsh-tui"
  local plugin = t.plugin_name or "@deepseek-harness-tui/dsh-tui"

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
