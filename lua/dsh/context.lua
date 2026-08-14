--- 上下文辅助：当前文件、工作目录、视觉选择等。

local M = {}

--- 当前缓冲区的绝对路径（无文件名时返回 nil）。
function M.current_file()
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return nil
  end
  return vim.fn.fnamemodify(name, ":p")
end

--- 读取文件内容（失败返回 nil）。
function M.file_content(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

--- 解析任务运行时的工作目录。
---@param mode string "root" | "buffer" | "cwd" | 绝对路径
function M.resolve_cwd(mode)
  if type(mode) == "string" and vim.fn.isdirectory(mode) == 1 then
    return mode
  end

  if mode == "buffer" then
    local file = M.current_file()
    if file then
      return vim.fn.fnamemodify(file, ":h")
    end
    return vim.fn.getcwd()
  end

  if mode == "root" then
    local file = M.current_file()
    local dir = (file and vim.fn.fnamemodify(file, ":h")) or vim.fn.getcwd()
    return vim.fs.root(dir, { ".git", ".hg", ".svn" }) or dir
  end

  -- "cwd" 或其它未知值：回退到 Neovim 当前目录
  return vim.fn.getcwd()
end

--- 当前视觉选择文本（charwise 精确到列，linewise/blockwise 取整行）。
function M.visual_selection()
  local buf = vim.api.nvim_get_current_buf()
  local mode = vim.fn.visualmode()
  local start = vim.fn.getpos("'<")
  local finish = vim.fn.getpos("'>")

  local sl, sc = start[2], start[3] -- 1-based line, 1-based byte col
  local el, ec = finish[2], finish[3]

  -- linewise (V) 与 blockwise (Ctrl-v) 均取整行
  if mode == "V" or mode == "\22" then
    local lines = vim.api.nvim_buf_get_lines(buf, sl - 1, el, false)
    return table.concat(lines, "\n")
  end

  -- charwise：字节列，包含首尾标记
  local lines = vim.api.nvim_buf_get_lines(buf, sl - 1, el, false)
  if #lines == 1 then
    return string.sub(lines[1], sc, ec)
  end
  lines[1] = string.sub(lines[1], sc)
  lines[#lines] = string.sub(lines[#lines], 1, ec)
  return table.concat(lines, "\n")
end

return M
