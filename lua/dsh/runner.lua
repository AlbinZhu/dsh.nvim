--- 负责拼装并运行 `dsh --profile headless "task"`，收集 stdout/stderr。

local M = {}

local active = nil

--- 解析 dsh 可执行文件：显式配置 > PATH > ~/.npm/_npx 下的最新副本。
local function resolve_dsh_cmd(config)
  if config.dsh_cmd and config.dsh_cmd ~= "" then
    return vim.fn.expand(config.dsh_cmd)
  end
  if vim.fn.executable("dsh") == 1 then
    return "dsh"
  end
  local found = vim.fn.glob(vim.fn.expand("~/.npm/_npx/*/node_modules/.bin/dsh"), false, true)
  if type(found) == "table" and #found > 0 then
    table.sort(found, function(a, b)
      return vim.fn.getftime(a) > vim.fn.getftime(b)
    end)
    return found[1]
  end
  return nil
end

--- 拼装命令；失败时返回 nil, 错误信息。
function M.build_command(config, task)
  local cmd = resolve_dsh_cmd(config)
  if not cmd then
    return nil, "找不到 dsh 可执行文件，请在 require('dsh').setup({ dsh_cmd = '/path/to/dsh' }) 中指定。"
  end

  local argv = { cmd, "--profile", config.profile }
  vim.list_extend(argv, config.launcher_args or {})
  table.insert(argv, "--") -- 启动器会消费一个 `--`，之后的文本原样作为任务参数
  table.insert(argv, task)
  return argv
end

--- 取消正在运行的任务（发送 SIGTERM）。
function M.cancel()
  if active then
    active:kill(15)
    active = nil
    return true
  end
  return false
end

---@param callbacks table { on_stdout?, on_stderr?, on_exit, on_error? }
function M.run(config, task, callbacks)
  if active then
    active:kill(15)
    active = nil
  end

  local argv, err = M.build_command(config, task)
  if not argv then
    if callbacks.on_error then
      callbacks.on_error(err)
    end
    return nil
  end

  local out, errout = {}, {}

  local opts = {
    cwd = require("dsh.context").resolve_cwd(config.cwd),
    text = true,
    stdout = function(_err, data)
      if data and data ~= "" then
        table.insert(out, data)
        if callbacks.on_stdout then
          callbacks.on_stdout(data)
        end
      end
    end,
    stderr = function(_err, data)
      if data and data ~= "" then
        table.insert(errout, data)
        if callbacks.on_stderr then
          callbacks.on_stderr(data)
        end
      end
    end,
  }

  if config.timeout_ms and config.timeout_ms > 0 then
    opts.timeout = config.timeout_ms
  end

  active = vim.system(argv, opts, function(obj)
    active = nil
    callbacks.on_exit(obj.code, obj.signal, table.concat(out), table.concat(errout))
  end)

  return active
end

return M
