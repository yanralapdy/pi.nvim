# pi.nvim

Neovim plugin for the [Pi coding agent](https://github.com/earendil-works/pi-coding-agent). Select code, ask a question, watch the response stream into a floating window. Pi runs as a subprocess talking JSON-Lines over stdin/stdout.

## Features

- **RPC core** — spawns Pi in `--mode rpc`, manages the subprocess lifecycle, auto-restarts on crash
- **Floating ask** — select code, press `<leader>pa`, type your question, get a streaming response
- **Visual selection context** — file path, line range, and selected code are pre-filled into the prompt
- **Lazy start** — Pi boots only when you trigger the first ask
- **Persistent session** — one global RPC process per Neovim instance, stays alive between asks
- **Clean shutdown** — subprocess killed on Neovim exit via `VimLeavePre`
- **Health check** — `:checkhealth pi-nvim` verifies Pi installation and config
- **Optional snacks.nvim integration** — enhanced input UI when snacks is available

## Requirements

- Neovim 0.7+
- [Pi](https://github.com/earendil-works/pi-coding-agent) installed and configured with at least one model
  ```bash
  npm i -g @earendil-works/pi-coding-agent
  ```
- (Optional) [snacks.nvim](https://github.com/folke/snacks.nvim) for the enhanced input window

## Installation

### lazy.nvim

```lua
{
  "yanralapdy/pi.nvim",
  opts = {},
  -- Optional: only load when you call setup
  lazy = true,
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
| `keymaps.ask` | `"<leader>pa"` | Keybinding to trigger the ask flow |

## Usage

### Visual mode

1. Select code with `V` or `v`
2. Press `<leader>pa`
3. The floating input window opens with the selection pre-filled:
   ```
   # init.lua:10-25
   ```lua
   function M.setup(user_opts)
     ...
   end
   ```

   # Your question:
   ```
4. Type your question, press `Enter` to submit
5. The output window opens and streams Pi's response
6. Press `q` or `<Esc>` to close the output window

### Normal mode

Press `<leader>pa` without a selection to ask a general question. The input window opens empty.

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
3. A floating input window opens with a pre-filled template containing file path, line numbers, and selected code
4. You type your question and submit
5. The plugin spawns Pi (if not already running) and sends the prompt via JSON-Lines over stdin
6. A floating output window opens and streams Pi's response chunk-by-chunk
7. The RPC process stays alive after closing the output window, ready for the next ask

## License

MIT
