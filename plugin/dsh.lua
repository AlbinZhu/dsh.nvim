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
