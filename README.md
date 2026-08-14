# dsh.nvim

在 Neovim 中使用 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的 AI 编码代理
<br>_Bring the DeepSeek Harness (`dsh`) coding agent into your editor_

[![Neovim](https://img.shields.io/badge/Neovim-%3E%3D0.10-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/AlbinZhu/dsh.nvim?style=social)](https://github.com/AlbinZhu/dsh.nvim)

`dsh.nvim` 是一个轻量级 Neovim 插件，把 `dsh` 的一次性任务模式（`headless` profile）接入编辑器：在浮窗里提问、审查当前文件、或把选中的代码发给 AI 代理，结果直接显示在浮窗中，无需离开 Neovim。

`dsh.nvim` is a lightweight Neovim plugin that wraps `dsh --profile headless`. Ask questions in a floating window, review the current file, or send a visual selection — the agent's answer is rendered right in the editor.

## ✨ 特性 · Features

- 🪟 **浮窗交互** — 提问与结果都在一个浮动窗口里，按 `q` / `<Esc>` 关闭
- 💬 **三种入口** — 直接提问、审查当前文件、处理选中文本
- ⚡ **开箱即用** — 自动探测 `dsh` 路径（`PATH` → `~/.npm/_npx` 下的最新副本）
- 🧩 **完全可定制** — 提示词模板、工作目录、超时、窗口样式、按键映射
- 🔌 **Lua API** — 可被其它插件或配置脚本调用
- 🖥️ **兼容 Neovim ≥ 0.10** — 基于 `vim.system` / `vim.fs`

## 📋 要求 · Requirements

- Neovim ≥ 0.10
- [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的 `dsh` CLI（`@deepseek-ai/dsh`）

请参考 [deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) 安装 `dsh`；或直接让插件自动探测 `~/.npm/_npx` 下的副本。

## 📦 安装 · Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "AlbinZhu/dsh.nvim",
  lazy = false, -- 插件很小，直接启动加载即可
  config = function()
    require("dsh").setup()
  end,
}
```

按需懒加载（可选）：

```lua
{
  "AlbinZhu/dsh.nvim",
  event = "VeryLazy",
  config = function()
    require("dsh").setup()
  end,
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use({
  "AlbinZhu/dsh.nvim",
  config = function()
    require("dsh").setup()
  end,
})
```

### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'AlbinZhu/dsh.nvim'
" 然后在你的配置里：
" lua require("dsh").setup()
```

## 🚀 快速上手 · Quick Start

| 命令 Command | 作用 Description |
|---|---|
| `:Dsh 帮我看看这个项目` | 直接提问 · Ask directly |
| `:Dsh` | 弹出输入框提问 · Prompt via input dialog |
| `:DshFile` | 审查当前文件 · Review the current file |
| `:'<,'>DshSelection` | 处理选中的文本 · Send the visual selection |
| `:DshCancel` | 取消任务 · Cancel the running job |

默认按键映射（在 `setup()` 中注册，可关闭）· _Default keymaps (registered in `setup()`, can be disabled):_

| 按键 Key | 动作 Action |
|---|---|
| `<leader>da` | 提问 · Ask |
| `<leader>df` | 审查当前文件 · Review file |
| `<leader>ds` (visual) | 处理选中文本 · Send selection |

## ⚙️ 配置 · Configuration

```lua
require("dsh").setup({
  dsh_cmd = nil,            -- dsh 可执行文件；nil = 自动探测（PATH → ~/.npm/_npx 最新副本）
  profile = "headless",     -- dsh profile
  launcher_args = {},       -- 额外的启动器参数，例如 { "--patch", "/path/x.yml" }
  cwd = "root",             -- 运行目录："root"(git 根) | "buffer" | "cwd" | 绝对路径
  timeout_ms = nil,         -- 任务超时（毫秒），nil = 不限
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
  },
  window = {
    relative = "editor",
    width = 0.72,           -- 小数按编辑器尺寸换算；也支持整数（字符列）
    height = 0.5,
    row = 0.25,             -- (1 - height) / 2，配合 anchor="NW" 居中
    col = 0.14,             -- (1 - width) / 2
    anchor = "NW",
    border = "rounded",
    title = " dsh ",
    title_pos = "center",
    style = "minimal",
    focusable = true,
  },
})
```

- `keymaps` 里的某一项设为 `nil` / `false` / `""` 即禁用该映射。
- 未调用 `setup()` 时命令仍可用（默认配置），只是不会注册按键映射。

## 🔌 Lua API

```lua
require("dsh").setup(opts)     -- 配置 + 注册按键
require("dsh").run(task)       -- 运行任务
require("dsh").ask(prompt?)    -- 提问（无参数时弹出输入框）
require("dsh").ask_file()      -- 审查当前文件
require("dsh").ask_visual()    -- 处理视觉选择
require("dsh").cancel()        -- 取消任务
```

## 🧠 工作原理 · How it works

插件最终执行：

```
dsh --profile headless -- "<任务文本>"
```

`headless` 模式只把最后一条非空回复写到 stdout（成功退出码 `0`，失败退出码 `1`），因此浮窗在运行期显示 spinner，结束后一次性展示结果；出错时把 stderr 一并展示。

## ❓ 常见问题 · FAQ

**Q：第一次运行很慢？**
`headless` profile 首次使用会自动初始化，第一次运行会多花几秒，属正常现象。

**Q：提示找不到 `dsh`？**
插件会按 `dsh_cmd` → `PATH` → `~/.npm/_npx/*/node_modules/.bin/dsh` 的顺序探测。都不行就显式指定：

```lua
require("dsh").setup({ dsh_cmd = "/绝对/路径/dsh" })
```

**Q：结果窗口怎么关闭？**
按 `q`、`<Esc>` 或 `<C-c>`。

## 🗺️ Roadmap

- [ ] 流式输出（配合 dsh 未来支持增量输出）
- [ ] 会话/多轮对话支持
- [ ] 把结果写入 split / quickfix

## 🤝 Contributing

欢迎提 issue 和 PR。改动请保持现有代码风格，并确保 `require("dsh")` 可正常加载。

## 📄 License

[MIT](./LICENSE) © 2026 AlbinZhu

## 🙏 Acknowledgements

感谢 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 项目。
