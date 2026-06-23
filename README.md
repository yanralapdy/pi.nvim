# pi.nvim

Neovim plugin for the [Pi coding agent](https://github.com/earendil-works/pi-coding-agent). Select code, ask a question, watch the response stream into a floating window. Pi runs as a subprocess talking JSON-Lines over stdin/stdout.

## Features

- **RPC core** — spawns Pi in `--mode rpc`, manages the subprocess lifecycle, auto-restarts on crash
- **Session detection** — when Pi is running in a tmux pane, `<leader>pa` forwards your prompt directly to the active session
- **Fallback terminal** — without tmux, Pi opens in a Neovim terminal split
- **Floating ask** — select code, press `<leader>pa`, type your question, get a streaming response
- **Visual selection context** — file path, line range, and selected code are pre-filled into the prompt
- **Lazy start** — Pi boots only when you trigger the first ask
- **Persistent session** — one global RPC process per Neovim instance, stays alive between asks
- **Clean shutdown** — subprocess killed on Neovim exit via `VimLeavePre`
- **Health check** — `:checkhealth pi-nvim` verifies Pi installation and config
- **Optional snacks.nvim integration** — enhanced input UI when snacks is available

## Requirements

- Neovim 0.7+
- Node.js >= 22.19.0 (required by pi-coding-agent)
- [Pi](https://github.com/earendil-works/pi-coding-agent) installed and configured with at least one model
  ```bash
  npm i -g @earendil-works/pi-coding-agent
  ```
- (Optional) tmux — enables session forwarding to existing Pi panes
- (Optional) [snacks.nvim](https://github.com/folke/snacks.nvim) for the enhanced input window

## Installation

### lazy.nvim

```lua
{
  "yanralapdy/pi.nvim",
  lazy = false, -- health check needs plugin in rtp at startup
  opts = {},
  dependencies = { "folke/snacks.nvim" }, -- optional
}
```

### packer.nvim

```lua
use {
  "yanralapdy/pi.nvim",
  config = function()
    require("pi-nvim").setup({})
  end,
}
```

### Manual

```bash
git clone https://github.com/yanralapdy/pi.nvim \
  ~/.local/share/nvim/site/pack/plugins/start/pi.nvim
```

## Configuration

Default options:

```lua
require("pi-nvim").setup({
  pi_cmd = "pi",
  pi_args = { "--mode", "rpc", "--no-session" },
  snacks = true,
  float_input = {
    width = 80,
    height = 20,
    border = "rounded",
  },
  float_output = {
    width = 80,
    height = 30,
    border = "rounded",
  },
  keymaps = {
    ask = "<leader>pa",
    select = "<leader>ps",
    file = "<leader>pf",
    prompt = "<leader>pp",
  },
})
```

| Option | Default | Description |
|--------|---------|-------------|
| `pi_cmd` | `"pi"` | Path to the Pi CLI binary |
| `pi_args` | `{ "--mode", "rpc", "--no-session" }` | Arguments passed to Pi |
| `snacks` | `true` | Use snacks.nvim for input if available |
| `float_input` | see above | Input window dimensions and border style |
| `float_output` | see above | Output window dimensions and border style |
| `session.auto_forward` | `true` | Forward prompts to existing pi tmux session when available |
| `keymaps.ask` | `"<leader>pa"` | Keybinding to trigger the ask flow |
| `keymaps.select` | `"<leader>ps"` | Keybinding for the action menu |
| `keymaps.file` | `"<leader>pf"` | Keybinding to send file path to Pi |
| `keymaps.prompt` | `"<leader>pp"` | Keybinding to pick a prompt |

## Usage

### Visual mode

1. Select code with `V` or `v`
2. Press `<leader>pa`
3. The floating input window opens — type your question and press `Enter` to submit
4. The selected code (file path, line range, content) is automatically included in the prompt sent to Pi
5. The output window opens and streams Pi's response
6. Press `q` or `<Esc>` to close the output window

### Normal mode

Press `<leader>pa` without a selection to ask a general question. The input window opens empty.

### Tmux integration (optional)

If tmux is installed and a Pi session is running in a tmux pane, `<leader>pa` forwards your prompt directly to that session instead of opening a new terminal. Without tmux, Pi opens in a Neovim terminal split automatically.

### Keybindings

| Key | Mode | Action |
|-----|------|--------|
| `<leader>pa` | n, v | Ask Pi — opens input, sends prompt with context |
| `<leader>ps` | n, v | Action menu — send file, ask selection, or pick a prompt |
| `<leader>pf` | n, v | Send current file path to existing Pi session |
| `<leader>pp` | n, v | Pick a prompt (explain, fix, test, etc.) and send with context |

### Commands

| Command | Action |
|---------|--------|
| `:PiAsk` | Trigger the ask flow (same as `<leader>pa` in normal mode) |
| `:checkhealth pi-nvim` | Verify installation and configuration |

### Output window keybindings

| Key | Action |
|-----|--------|
| `q` | Close the output window |
| `<Esc>` | Close the output window |
| `<C-c>` | Abort Pi and close the output window |

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                    Neovim Process                     │
│                                                      │
│  ┌──────────┐   ┌──────────┐   ┌──────────────────┐ │
│  │ init.lua │   │ config   │   │ health.lua        │ │
│  │ setup()  │──▶│ defaults │   │ :checkhealth      │ │
│  │ commands │   │ merge    │   │ verify pi install │ │
│  └────┬─────┘   └──────────┘   └──────────────────┘ │
│       │                                               │
│       ▼                                               │
│  ┌──────────────────────────────────────────────┐    │
│  │              rpc.lua (the bus)                │    │
│  │                                              │    │
│  │  spawn()      → pi --mode rpc (child proc)   │    │
│  │  send(cmd)    → stdin JSONL write             │    │
│  │  on_event()   ← stdout JSONL read             │    │
│  │  on_exit()    ← process exit/crash            │    │
│  │  abort()      → SIGINT or abort command       │    │
│  │  is_running() → check process state           │    │
│  └───┬──────────────────────────────────────────┘    │
│      │                                               │
│      ▼                                               │
│  ┌─────────┐                                        │
│  │ float   │                                        │
│  │ input   │                                        │
│  │ output  │                                        │
│  └─────────┘                                        │
└──────────────────────────────────────────────────────┘
                         │
                         │ stdin/stdout (JSON-Lines)
                         ▼
┌──────────────────────────────────────────────────────┐
│              pi --mode rpc (child process)            │
│                                                      │
│  stdin  ←  {"type":"prompt","message":"..."}         │
│  stdout →  {"type":"message_update",...}             │
│                                                      │
│  Tools: read | edit | write | bash | grep | find     │
└──────────────────────────────────────────────────────┘
```

## How it works

1. You press `<leader>pa` in visual mode
2. The plugin captures the selection range and content
3. If Pi is running in a tmux pane, the prompt is forwarded directly to that session and you're done
4. Otherwise, a floating input window opens with a pre-filled template containing file path, line numbers, and selected code
5. You type your question and submit
6. The plugin spawns Pi (if not already running) and sends the prompt via JSON-Lines over stdin
7. A floating output window opens and streams Pi's response chunk-by-chunk
8. The RPC process stays alive after closing the output window, ready for the next ask

## License

MIT
