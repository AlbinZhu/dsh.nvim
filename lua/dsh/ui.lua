--- 结果浮窗：运行中显示 spinner，结束后展示最终回复或错误。

local M = {}

local state = { win = nil, buf = nil, timer = nil, started = nil }

local function make_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"
  return buf
end

local function close()
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
end

local function tick()
  if not state.started then
    return
  end
  local elapsed = math.floor((vim.uv.hrtime() - state.started) / 1e9)
  local dots = string.rep(".", (elapsed % 3) + 1)
  local line = string.format("⏳ dsh 正在工作%s  (%ds)", dots, elapsed)
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.bo[state.buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.buf, 0, 1, false, { line })
    vim.bo[state.buf].modifiable = false
  end
end

--- 把 0 < v < 1 的小数按编辑器尺寸换算成整数；其它值原样返回。
local function resolve_dim(value, total)
  if type(value) == "number" and value > 0 and value < 1 then
    return math.max(1, math.floor(value * total))
  end
  return value
end

--- 打开结果浮窗（已打开则复用）。
function M.open(config)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    return state
  end

  local uis = vim.api.nvim_list_uis()
  local total_w = (uis[1] and uis[1].width) or 80
  local total_h = (uis[1] and uis[1].height) or 24

  local win_config = vim.tbl_deep_extend("force", vim.deepcopy(config.window), {
    width = resolve_dim(config.window.width, total_w),
    height = resolve_dim(config.window.height, total_h),
    row = resolve_dim(config.window.row, total_h),
    col = resolve_dim(config.window.col, total_w),
  })

  local buf = make_buffer()
  local win = vim.api.nvim_open_win(buf, true, win_config)
  state.win, state.buf = win, buf
  state.started = vim.uv.hrtime()

  vim.keymap.set("n", config.close_key, close, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf })
  vim.keymap.set("n", "<C-c>", close, { buffer = buf })

  state.timer = vim.uv.new_timer()
  state.timer:start(300, 300, vim.schedule_wrap(tick))
  tick()
  return state
end

local function set_lines(lines)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_cursor(state.win, { 1, 0 })
  end
end

--- 展示成功结果。
--- 注意：由 vim.system 的 on_exit（fast event context）调用，必须用 vim.schedule
--- 推迟到主事件循环，否则设置 buffer 选项会触发 E5560。
function M.set_result(stdout)
  vim.schedule(function()
    if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
      return
    end
    if state.timer then
      state.timer:stop()
    end
    vim.bo[state.buf].filetype = "markdown"
    set_lines(vim.split(stdout, "\n"))
  end)
end

--- 展示错误信息。
function M.set_error(code, signal, stderr, msg)
  vim.schedule(function()
    if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
      return
    end
    if state.timer then
      state.timer:stop()
    end
    vim.bo[state.buf].filetype = "text"

    local lines = { "✗ dsh 运行失败" }
    if code ~= nil then
      table.insert(lines, "exit code: " .. tostring(code))
    end
    if signal and signal ~= 0 then
      table.insert(lines, "signal: " .. tostring(signal))
    end
    if msg then
      table.insert(lines, "")
      table.insert(lines, msg)
    end
    if stderr and stderr ~= "" then
      table.insert(lines, "")
      table.insert(lines, "--- stderr ---")
      vim.list_extend(lines, vim.split(stderr, "\n"))
    end
    set_lines(lines)
  end)
end

function M.close()
  close()
end

function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

return M
