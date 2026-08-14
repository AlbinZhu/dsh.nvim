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

-- ---- dsh-tianshu-tui 终端集成 ----

vim.api.nvim_create_user_command("DshTui", function(cmd)
  local text = table.concat(cmd.fargs, " ")
  mod().toggle_tui({ text = text ~= "" and text or nil })
end, {
  nargs = "*",
  desc = "Toggle the dsh-tianshu TUI in a terminal. With args, type them into the TUI input.",
})

vim.api.nvim_create_user_command("DshTuiFloat", function()
  mod().open_tui({ layout = "float" })
end, { desc = "Open the dsh-tianshu TUI in a floating terminal" })

vim.api.nvim_create_user_command("DshTuiSplit", function()
  mod().open_tui({ layout = "split" })
end, { desc = "Open the dsh-tianshu TUI in a horizontal split terminal" })

vim.api.nvim_create_user_command("DshTuiVSplit", function()
  mod().open_tui({ layout = "vsplit" })
end, { desc = "Open the dsh-tianshu TUI in a vertical split terminal" })

vim.api.nvim_create_user_command("DshTuiTab", function()
  mod().open_tui({ layout = "tab" })
end, { desc = "Open the dsh-tianshu TUI in a new tab terminal" })

vim.api.nvim_create_user_command("DshTuiClose", function()
  mod().close_tui()
end, { desc = "Close/hide the dsh-tianshu TUI window" })

vim.api.nvim_create_user_command("DshTuiInstall", function()
  mod().tui_install()
end, { desc = "Install the dsh-tianshu TUI plugin into the tui profile" })
