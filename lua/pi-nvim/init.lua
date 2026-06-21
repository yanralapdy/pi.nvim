local M = {}

-- Store merged config from setup()
M._config = nil

local function ask()
  local rpc = require("pi-nvim.rpc")
  local float = require("pi-nvim.float")
  local config = M._config or require("pi-nvim.config").defaults

  local context = float.get_selection()

  float.open_input(function(text)
    if not text then
      return
    end

    -- Build the prompt with context
    local prompt = text
    if context then
      prompt = string.format(
        "# %s:%d-%d\n```%s\n%s\n```\n\n%s",
        context.path,
        context.start_row,
        context.end_row,
        context.filetype,
        context.code,
        text
      )
    end

    -- Open output window
    local buf, win = float.open_output(config)

    -- Track text deltas for the output buffer
    local function on_message_update(event)
      local delta = event.assistantMessageEvent
      if delta and delta.type == "text_delta" then
        vim.schedule(function()
          float.append_output(buf, delta.delta)
        end)
      end
    end

    -- Subscribe to events
    local unsub_update = rpc.on_event("message_update", on_message_update)

    -- Clean up on agent_end
    rpc.on_event("agent_end", function()
      vim.schedule(function()
        unsub_update()
      end)
    end)

    -- Abort handler: Ctrl-C in output window closes and aborts Pi
    if vim.api.nvim_buf_is_valid(buf) then
      vim.keymap.set("n", "<C-c>", function()
        rpc.abort()
        float.close_output(win)
      end, { buffer = buf, nowait = true })
    end

    -- Send the prompt
    rpc.prompt(prompt)
  end, {
    context = context,
    config = config,
  })
end

function M.setup(user_opts)
  local config = require("pi-nvim.config").merge(user_opts)
  M._config = config
  local rpc = require("pi-nvim.rpc")

  -- Give rpc access to config
  rpc.set_config(config)

  -- Keybinding: <leader>pa in visual and normal mode
  vim.keymap.set({ "v", "n" }, config.keymaps.ask, function()
    ask()
  end, { desc = "Ask Pi" })

  -- User command: :PiAsk
  vim.api.nvim_create_user_command("PiAsk", function()
    ask()
  end, { desc = "Ask Pi a question" })

  -- Cleanup on Neovim exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      rpc.dispose()
    end,
  })

  return { config = config }
end

return M
