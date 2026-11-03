-- dsh.nvim 命令入口。命令在此注册，按键映射由 require("dsh").setup() 负责。
if vim.g.loaded_dsh ~= nil then
  return
end
vim.g.loaded_dsh = 1

local function mod()
  return require("dsh")
end

vim.api.nvim_create_user_command("Dsh", function(cmd)
  local prompt = table.concat(cmd.fargs, " ")
  if prompt == "" then
    mod().ask()
  else
    mod().run(prompt)
  end
end, {
  nargs = "*",
  complete = "file",
  desc = "Ask dsh (headless) a question. With no args, opens an input prompt.",
})

vim.api.nvim_create_user_command("DshFile", function()
  mod().ask_file()
end, { desc = "Ask dsh to review the current file" })

vim.api.nvim_create_user_command("DshSelection", function()
  mod().ask_visual()
end, { range = true, desc = "Ask dsh about the visual selection" })

vim.api.nvim_create_user_command("DshCancel", function()
  mod().cancel()
end, { desc = "Cancel the running dsh job" })

-- ---- dsh-TUI 终端集成 ----

vim.api.nvim_create_user_command("DshTui", function(cmd)
  local text = table.concat(cmd.fargs, " ")
  mod().toggle_tui({ text = text ~= "" and text or nil })
end, {
  nargs = "*",
  desc = "Toggle the dsh-TUI in a terminal. With args, type them into the TUI input.",
})

vim.api.nvim_create_user_command("DshTuiFloat", function()
  mod().open_tui({ layout = "float" })
end, { desc = "Open the dsh-TUI in a floating terminal" })

vim.api.nvim_create_user_command("DshTuiSplit", function()
  mod().open_tui({ layout = "split" })
end, { desc = "Open the dsh-TUI in a horizontal split terminal" })

vim.api.nvim_create_user_command("DshTuiVSplit", function()
  mod().open_tui({ layout = "vsplit" })
end, { desc = "Open the dsh-TUI in a vertical split terminal" })

vim.api.nvim_create_user_command("DshTuiTab", function()
  mod().open_tui({ layout = "tab" })
end, { desc = "Open the dsh-TUI in a new tab terminal" })

vim.api.nvim_create_user_command("DshTuiClose", function()
  mod().close_tui()
end, { desc = "Close/hide the dsh-TUI window" })

vim.api.nvim_create_user_command("DshTuiFocus", function()
  mod().focus_tui()
end, { desc = "Smart focus: hide the dsh-TUI if you are in it, focus it if visible, otherwise open it" })

vim.api.nvim_create_user_command("DshTuiResume", function(cmd)
  mod().resume_tui(cmd.args ~= "" and cmd.args or nil)
end, {
  nargs = "?",
  desc = "Start the dsh-TUI with --resume [session-id] (the last session by default)",
})

-- :DshTuiFile [path] [start] [end]；不带参数 = 当前缓冲区文件。
-- complete = "file" 的命令，Neovim 会先把参数里的 % # ~ 展开，这里只负责转成绝对路径。
vim.api.nvim_create_user_command("DshTuiFile", function(cmd)
  local function expand_path(p)
    return p ~= "" and vim.fn.fnamemodify(p, ":p") or p
  end

  -- 末尾的纯数字（至多两个）是行号，但路径本身不能只剩一个数字。
  local args = vim.deepcopy(cmd.fargs)
  local lines = {}
  while #args > 1 and #lines < 2 and args[#args]:match("^%d+$") do
    table.insert(lines, 1, tonumber(table.remove(args)))
  end

  local path = expand_path(table.concat(args, " "))
  if #lines > 0 and vim.fn.filereadable(path) ~= 1 then
    -- 去掉数字后的路径并不存在：整串都当作路径（文件名里可以有空格和数字）。
    path, lines = expand_path(table.concat(cmd.fargs, " ")), {}
  end
  mod().tui_add_file(path, lines[1], lines[2])
end, {
  nargs = "*",
  complete = "file",
  desc = "Add a file to the dsh-TUI: [path] [start] [end] (mention by default, or content per tui.file_mode)",
})

vim.api.nvim_create_user_command("DshTuiTreeAdd", function(cmd)
  mod().tui_add_tree(cmd.range > 0 and { cmd.line1, cmd.line2 } or nil)
end, {
  range = true,
  desc = "Add the file(s) under the cursor (or selected lines) in a file explorer to the dsh-TUI input",
})

vim.api.nvim_create_user_command("DshTuiSelection", function()
  mod().tui_add_selection()
end, { range = true, desc = "Add the visual selection to the dsh-TUI input" })

vim.api.nvim_create_user_command("DshTuiInstall", function()
  mod().tui_install()
end, { desc = "Install the dsh-TUI plugin into the dsh-tui profile" })
