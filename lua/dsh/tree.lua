--- 文件树 / 选择器集成：取出光标下、visual 选中或已标记的文件路径。
---
--- 行为参照 coder/claudecode.nvim 的文件树集成（nvim-tree、neo-tree、oil、
--- mini.files、netrw、snacks picker），但只依赖各插件的公开 API；
--- 缺少对应插件时返回错误信息，而不是抛异常。

local M = {}

--- 支持的 filetype（同时用来注册 buffer-local 按键）。
M.filetypes = { "NvimTree", "neo-tree", "oil", "minifiles", "netrw", "snacks_picker_list" }

local supported = {}
for _, ft in ipairs(M.filetypes) do
  supported[ft] = true
end

--- 缓冲区是否是受支持的文件树 / 选择器。
---@param buf integer|nil 缓冲区编号，默认当前缓冲区
function M.is_explorer(buf)
  return supported[vim.bo[buf or 0].filetype] == true
end

--- 去掉空值与重复项，保持原有顺序。
local function unique(paths)
  local seen, out = {}, {}
  for _, p in ipairs(paths) do
    if type(p) == "string" and p ~= "" and not seen[p] then
      seen[p] = true
      out[#out + 1] = p
    end
  end
  return out
end

--- visual 选中的行区间；没有区间时取光标所在行。
local function line_span(range)
  if range then
    return range[1], range[2]
  end
  local line = vim.api.nvim_win_get_cursor(0)[1]
  return line, line
end

-- 每个适配器返回 files（可能为空的列表）；插件不可用时返回 nil, err。
-- range = { first, last } 表示 visual 选中的缓冲区行，nil 表示只取光标所在项。

local function from_nvim_tree()
  local ok, api = pcall(require, "nvim-tree.api")
  if not ok then
    return nil, "nvim-tree 不可用。"
  end
  local out = {}
  -- 先取已标记（bookmark）的节点；没有标记再取光标下的节点。
  for _, node in ipairs(api.marks.list() or {}) do
    out[#out + 1] = node.absolute_path
  end
  if #out == 0 then
    local node = api.tree.get_node_under_cursor()
    if node and node.name ~= ".." then
      out[1] = node.absolute_path
    end
  end
  return out
end

local function from_neo_tree(range)
  local ok, manager = pcall(require, "neo-tree.sources.manager")
  if not ok then
    return nil, "neo-tree 不可用。"
  end
  local state = manager.get_state(vim.b.neo_tree_source or "filesystem")
  if not state or not state.tree then
    return nil, "neo-tree 的状态不可用。"
  end
  local out = {}
  local function add(node)
    -- 跳过提示行（message）和没有路径的节点；多选时也跳过根节点（深度 1）。
    if not node or node.type == "message" or not node.path or node.path == "" then
      return
    end
    if range and node.get_depth and node:get_depth() <= 1 then
      return
    end
    out[#out + 1] = node.path
  end
  if range then
    for line = range[1], range[2] do
      add(state.tree:get_node(line))
    end
  else
    add(state.tree:get_node())
  end
  return out
end

local function from_oil(range)
  local ok, oil = pcall(require, "oil")
  if not ok then
    return nil, "oil.nvim 不可用。"
  end
  local buf = vim.api.nvim_get_current_buf()
  local dir = oil.get_current_dir(buf)
  if not dir then
    return nil, "无法获取 oil 的当前目录。"
  end
  local out = {}
  local first, last = line_span(range)
  for line = first, last do
    local entry = oil.get_entry_on_line(buf, line)
    if entry and entry.name and entry.name ~= ".." and entry.name ~= "." then
      out[#out + 1] = dir .. entry.name
    end
  end
  return out
end

local function from_mini_files(range)
  local ok, mini = pcall(require, "mini.files")
  if not ok then
    return nil, "mini.files 不可用。"
  end
  local buf = vim.api.nvim_get_current_buf()
  local out = {}
  local first, last = line_span(range)
  for line = first, last do
    local entry = mini.get_fs_entry(buf, line)
    if entry and entry.path and entry.path ~= "" then
      out[#out + 1] = entry.path
    end
  end
  return out
end

local function from_netrw()
  if vim.fn.exists("*netrw#Expose") ~= 1 or vim.fn.exists("*netrw#Call") ~= 1 then
    return nil, "netrw 不可用。"
  end
  local out = {}
  -- 先取用 mf 标记过的文件；没有再取光标下的条目。
  -- netrw#Expose 在变量不存在时返回字符串 "n/a"，所以要确认拿到的是列表。
  local ok, marked = pcall(vim.fn["netrw#Expose"], "netrwmarkfilelist")
  if ok and type(marked) == "table" then
    for _, path in ipairs(marked) do
      out[#out + 1] = vim.fn.fnamemodify(path, ":p")
    end
  end
  if #out == 0 then
    local word_ok, word = pcall(vim.fn["netrw#Call"], "NetrwGetWord")
    if word_ok and type(word) == "string" and word ~= "" and word ~= "." and word ~= ".." and word ~= "../" then
      local dir = vim.b.netrw_curdir or vim.fn.getcwd()
      out[1] = vim.fn.fnamemodify(dir .. "/" .. word, ":p")
    end
  end
  return out
end

local function from_snacks()
  local ok, snacks = pcall(require, "snacks")
  if not ok then
    return nil, "snacks.nvim 不可用。"
  end
  -- snacks.picker 通过 metatable 懒加载，访问本身就可能抛错，所以放进 pcall。
  local pickers_ok, pickers = pcall(function()
    return snacks.picker.get({ tab = true })
  end)
  if not pickers_ok or not pickers or #pickers == 0 then
    return nil, "没有活动的 snacks picker。"
  end
  -- 优先取列表窗口正是当前窗口的 picker，否则取这个标签页里最新打开的一个。
  local current_win = vim.api.nvim_get_current_win()
  local picker = pickers[#pickers]
  for _, p in ipairs(pickers) do
    local win = p.list and p.list.win and p.list.win.win
    if win == current_win then
      picker = p
      break
    end
  end
  -- 有 Tab 选中的条目就用它们，否则取光标所在的条目。
  local sel_ok, items = pcall(function()
    return picker:selected({ fallback = true })
  end)
  if not sel_ok or type(items) ~= "table" then
    return nil, "无法读取 snacks picker 的选择。"
  end
  local out = {}
  for _, item in ipairs(items) do
    -- 没有文件路径的条目（寄存器、命令、未保存的缓冲区等）直接跳过。
    if type(item.file) == "string" then
      local path_ok, path = pcall(snacks.picker.util.path, item)
      if not path_ok or not path then
        path = type(item.cwd) == "string" and (item.cwd .. "/" .. item.file) or item.file
      end
      out[#out + 1] = path
    end
  end
  return out
end

local adapters = {
  NvimTree = from_nvim_tree,
  ["neo-tree"] = from_neo_tree,
  oil = from_oil,
  minifiles = from_mini_files,
  netrw = from_netrw,
  snacks_picker_list = from_snacks,
}

--- 取出当前文件树缓冲区里选中的文件 / 目录路径。
--- 必须在文件树所在的窗口里调用（按键映射、命令都满足）。
---@param range integer[]|nil { first, last }：visual 选中的行；nil 表示只取光标所在项
---@return string[]|nil files 路径列表（去重）；失败为 nil
---@return string|nil err 失败原因
function M.selected_files(range)
  local ft = vim.bo.filetype
  local adapter = adapters[ft]
  if not adapter then
    return nil, "当前缓冲区不是受支持的文件树（filetype: " .. ft .. "）。"
  end
  local files, err = adapter(range)
  if not files then
    return nil, err
  end
  files = unique(files)
  if #files == 0 then
    return nil, "没有可添加的文件（光标下为空？）。"
  end
  return files
end

return M
