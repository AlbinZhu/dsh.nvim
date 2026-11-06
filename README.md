# dsh.nvim

Talk to the [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)
coding agent without leaving Neovim.

[![Neovim](https://img.shields.io/badge/Neovim-%3E%3D0.10-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/AlbinZhu/dsh.nvim?style=social)](https://github.com/AlbinZhu/dsh.nvim)

**English** · [简体中文](./README.zh-CN.md)

<!-- markdownlint-disable MD033 -->
<p align="center">
  <img src="doc/screenshot.jpg" width="100%"
    alt="dsh.nvim: the dsh TUI in a split, next to your code">
</p>
<!-- markdownlint-enable MD033 -->

Use DeepSeek Harness the way you already use claudecode.nvim. The full
interactive `dsh` session opens in a split next to your code, and your file or
selection is one keypress away.

## ✨ Why dsh.nvim

- 🖥️ **The full TUI, inside Neovim** — the interactive
  [dsh-TUI](https://github.com/ccch1mneyyy/dsh-TUI) runs in a split, with
  sessions and `/resume`.
- 📎 **Context in one keypress** — send a file, a selection or a line range as
  an `@mention`. Your input stays short.
- ⌨️ **Works like claudecode.nvim** — the same commands, the same window keys and
  the same way of adding context. If you know one, you already know the other.
- ⚡ **Zero setup** — finds `dsh` on your `PATH` or under `~/.npm/_npx`.
- 🧩 **Configurable** — keymaps, layouts, window style and a Lua API.

## 🚀 Quick start

Install the `dsh` CLI and the dsh-TUI plugin (details in
[Install dsh-TUI](#install-dsh-tui)):

```sh
npm install -g @deepseek-ai/dsh
dsh plugin --profile dsh-tui add @deepseek-harness-tui/dsh-tui
```

Then, in Neovim, press `<leader>tt`. The agent opens next to your code,
ready to type.

## 🔄 Use it like claudecode.nvim

DeepSeek Harness is a terminal coding agent. dsh.nvim gives it the same workflow
you know from claudecode.nvim:

- `<leader>tt` (or `:DshTui`) opens the agent next to your code, like `:ClaudeCode`.
- Type your request in the TUI, as you would in Claude Code. Adding context never
  submits anything; you press Enter when you are ready.
- `<leader>tf` adds the current file as an `@` mention. In visual mode, `<leader>ts`
  adds the selection, and in a file explorer it adds the file under the cursor.
- `<leader>tF` focuses the agent or hides it, `<leader>tr` resumes the last session,
  and `Ctrl+h/j/k/l` moves between windows.

For the full mapping, see [Coming from claudecode.nvim](#-coming-from-claudecodenvim).

## 📦 Installation

### Requirements

- Neovim 0.10 or newer
- The `dsh` CLI: `npm install -g @deepseek-ai/dsh`, or let the plugin find the
  copy under `~/.npm/_npx`
- For the TUI: Node.js `^22.19` or `>=24`, `pnpm`, and the dsh-TUI plugin
  (see [Install dsh-TUI](#install-dsh-tui))

### Install dsh-TUI

dsh-TUI is the interactive terminal app of DeepSeek Harness. dsh.nvim runs it
inside Neovim, so install it once from a shell:

```sh
# 1. the dsh CLI (skip this if you already have it)
npm install -g @deepseek-ai/dsh

# 2. the dsh-TUI plugin, installed into its own `dsh-tui` profile
dsh plugin --profile dsh-tui add @deepseek-harness-tui/dsh-tui

# 3. check that the TUI starts
dsh --profile dsh-tui
```

- Without a global install, replace `dsh` with `npx -y @deepseek-ai/dsh`.
- The first install uses `pnpm` to fetch dependencies, which takes a while.
- `dsh plugin --profile dsh-tui <args>` runs `pnpm <args>` inside that profile.
- dsh.nvim finds `dsh` on your `PATH` or under `~/.npm/_npx`. Set `dsh_cmd`
  if it lives elsewhere.

To update the plugin, run:

```sh
dsh plugin --profile dsh-tui update --latest @deepseek-harness-tui/dsh-tui
```

If the TUI reports that the plugin and the dsh version do not match, update the
plugin (or the dsh CLI) so that the two agree.

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "AlbinZhu/dsh.nvim",
  lazy = false, -- small enough to load at startup, so commands always exist
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
" then, in your config:
" lua require("dsh").setup()
```

## 🖥️ Use the TUI

The interactive dsh-TUI runs in a Neovim terminal, as a vertical split by
default. It also works as a horizontal split, a float or a tab.

| Command | What it does |
| --- | --- |
| `:DshTui [text]` | Toggle the TUI; `text` goes into its input line |
| `:DshTuiFocus` | Focus the TUI; hide it if you are already in it |
| `:DshTuiFloat` / `Split` / `VSplit` / `Tab` | Open in a given layout |
| `:DshTuiResume [id]` | Resume the last session, or the given one |
| `:DshTuiFile [path] [start] [end]` | Add a file, or only some of its lines |
| `:'<,'>DshTuiSelection` | Add the selection |
| `:DshTuiTreeAdd` | In a file explorer, add the file under the cursor |
| `:DshTuiClose` | Hide the TUI; it keeps running |

| Key | Action |
| --- | --- |
| `<leader>tt` | Toggle the TUI |
| `<leader>tF` | Focus the TUI, or hide it |
| `<leader>tr` | Resume the last session |
| `<leader>tf` | Add the current file |
| `<leader>ts` (visual) | Add the selection |
| `<leader>ts` (file explorer) | Add the file under the cursor |

### Working with the TUI

- **Typing** — opening or focusing the TUI puts you in terminal mode, ready to
  type. Returning to it from another window does the same.
- **Moving around** — `<C-h>` `<C-j>` `<C-k>` `<C-l>` move to the window in that
  direction and leave terminal mode. `<C-\><C-n>` followed by `q` hides the
  window.
- **Everything else** goes to the TUI, including `q`, `<Esc>`, `Ctrl+B` and
  `Ctrl+R`.
- **Exiting** — press `Ctrl+C` twice within a second.
- **Context** — selections and files go in as `@"lua/foo.lua"#L12-14`
  mentions, with paths relative to the TUI's working directory. A selection
  from a buffer with unsaved changes is pasted instead, because dsh-TUI reads
  files from disk.
- **Terminal** — when snacks.nvim is installed, the TUI uses its terminal, so
  your snacks keys apply. Set `tui.provider = "native"` to always use Neovim's
  built-in terminal.

## ⚙️ Configuration

Everything works without configuration. To change a few things:

```lua
require("dsh").setup({
  tui = { layout = "split" },
})
```

Most useful options:

| Option | Default | Description |
| --- | --- | --- |
| `tui.cwd` | `"root"` | `"root"` (git root), `"buffer"`, `"cwd"` or a path |
| `tui.layout` | `"vsplit"` | `"float"`, `"split"`, `"vsplit"` or `"tab"` |
| `tui.vsplit.size` | `0.3` | vertical split width, fraction of the editor |
| `tui.provider` | `"auto"` | snacks if installed, else `"native"` |
| `tui.file_mode` | `"mention"` | `"mention"` or `"content"` |
| `tui.selection_mode` | `"mention"` | `"mention"` or `"content"` |
| `tui.auto_insert` | `true` | enter terminal mode when the TUI gets focus |
| `tui.window_nav` | all `true` | Ctrl+hjkl; `false` frees a direction |

With `"mention"`, files and selections are referenced with `@`; with
`"content"`, the content itself is pasted. The full reference is in
`:help dsh`.

### Avoiding key clashes

Some default keys may clash with other plugins. LazyVim, for example, uses the
`<leader>t` group. Move the TUI keys under a prefix of your own:

```lua
require("dsh").setup({
  keymaps = {
    tui = "<leader>At",
    tui_file = "<leader>AF",
    tui_visual = "<leader>AS",
  },
})
```

Set any entry in `keymaps` to `false` to disable it.

## 🔌 Lua API

```lua
local dsh = require("dsh")

dsh.setup({ tui = { layout = "split" } }) -- configure and register keymaps
dsh.open_tui({ layout = "float", text = "hi" }) -- open or focus the TUI
dsh.toggle_tui()                          -- show or hide the TUI
dsh.focus_tui()                           -- focus it, or hide it if focused
dsh.resume_tui("session-id")              -- --resume "session-id" (nil = last)
dsh.close_tui()                           -- hide the TUI window
dsh.tui_add_file("lua/foo.lua", 12, 14)   -- a file, optionally just some lines
dsh.tui_add_files({ "lua", "README.md" }) -- several files or directories
dsh.tui_add_tree()                        -- file explorer: the file under cursor
dsh.tui_add_selection()                   -- add the visual selection
dsh.tui_paste("text")                     -- bracketed paste, never presses Enter
require("dsh.tui").send("text")           -- type text into the TUI input line
```

## 🔀 Coming from claudecode.nvim

The commands and window keys follow claudecode.nvim, so the habits carry over.

| claudecode.nvim | dsh.nvim |
| --- | --- |
| `:ClaudeCode` · `<leader>ac` | `:DshTui` · `<leader>tt` |
| `:ClaudeCodeFocus` · `<leader>af` | `:DshTuiFocus` · `<leader>tF` |
| `:ClaudeCode --resume` · `<leader>ar` | `:DshTuiResume` · `<leader>tr` |
| `:ClaudeCodeAdd %` · `<leader>ab` | `:DshTuiFile` · `<leader>tf` |
| `:ClaudeCodeSend` · `<leader>as` | `:DshTuiSelection` · `<leader>ts` |
| `:ClaudeCodeTreeAdd` · `<leader>as` | `:DshTuiTreeAdd` · `<leader>ts` |
| `Ctrl+h/j/k/l` in the terminal | the same keys |
| `:ClaudeCodeSelectModel` · `<leader>am` | `:DshTui`, then type `/model` |
| `:ClaudeCodeDiffAccept` / `Deny` | none: dsh has no IDE diff protocol |

## 🧠 How it works

- **The TUI** runs `dsh --profile dsh-tui` in a `:terminal` buffer. Hiding it
  keeps the process alive, so showing it again returns to the same session.
- **Context** is typed into the TUI's input line. Nothing is submitted for you.

## ❓ FAQ

### dsh is not found

The plugin checks `dsh_cmd`, then `dsh` on `PATH`, then `~/.npm/_npx`. Set the
path explicitly:

```lua
require("dsh").setup({ dsh_cmd = "/path/to/dsh" })
```

### Missing profile or plugin

Run the install command once:

```sh
dsh plugin --profile dsh-tui add @deepseek-harness-tui/dsh-tui
```

### Leaving insert mode in the TUI

Use `<C-h>` `<C-j>` `<C-k>` `<C-l>` to move to another window, or press
`<C-\><C-n>`.

### `Ctrl+J`, `Ctrl+K` or `Ctrl+L` do nothing

The window keys take them. dsh-TUI uses them for newline, delete to end of line
and redraw. Free the one you need, for example:

```lua
require("dsh").setup({ tui = { window_nav = { j = false } } })
```

## 🤝 Contributing

Issues and pull requests are welcome. Keep the existing style, and check that
the plugin still loads:

```sh
nvim --headless -u NONE --cmd 'set rtp+=.' -c 'lua require("dsh")' -c 'qa!'
```

## 📄 License

[MIT](./LICENSE) © 2026 AlbinZhu

## 🙏 Acknowledgements

Thanks to the
[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) project.
