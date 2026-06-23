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
    local prompt = float.build_prompt(context, text)

    -- Try forwarding to existing pi session (or open pi in free terminal)
    if config.session and config.session.auto_forward then
      local session = require("pi-nvim.session")
      if session.try_forward(prompt) then
        return
      end
    end

    -- Fallback: RPC + output window
    local buf, win = float.open_output(config)

    local function on_message_update(event)
      local delta = event.assistantMessageEvent
      if delta and delta.type == "text_delta" then
        vim.schedule(function()
          float.append_output(buf, delta.delta)
        end)
      end
    end

    local unsub_update = rpc.on_event("message_update", on_message_update)
    rpc.on_event("agent_end", function()
      vim.schedule(function()
        unsub_update()
      end)
    end)

    if vim.api.nvim_buf_is_valid(buf) then
      vim.keymap.set("n", "<C-c>", function()
        rpc.abort()
        float.close_output(win)
      end, { buffer = buf, nowait = true })
    end

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
  local float = require("pi-nvim.float")

  -- Give rpc access to config
  rpc.set_config(config)

  -- Setup visual selection autocmds
  float.setup_visual_autocmds()

  -- Keybinding: <leader>pa — ask a question (input dialog)
  vim.keymap.set("v", config.keymaps.ask, function()
    ask()
  end, { desc = "Ask Pi" })

  -- <leader>pf — send current file path to pi
  vim.keymap.set({ "v", "n" }, "<leader>pf", function()
    local session = require("pi-nvim.session")
    local pane = session.find_pi_pane()
    if not pane then
      vim.notify("[pi] no pi session found", vim.log.levels.ERROR)
      return
    end
    local path = vim.fn.expand("%")
    if path == "" then
      vim.notify("[pi] no file in buffer", vim.log.levels.ERROR)
      return
    end
    session.forward_prompt(path, pane)
    vim.notify("[pi] sent file: " .. path)
  end, { desc = "Pi: send file path" })

  -- <leader>ks — ask about selected code (snacks input)
  -- <leader>ps — unified action menu (send file, ask selection, pick prompt)
  vim.keymap.set("v", "<leader>ps", function()
    local sel = float.get_selection()
    local prompts = require("pi-nvim.prompts").get_all()
    local session = require("pi-nvim.session")

    local items = {
      {
        text = "Send File",
        action = function()
          local path = vim.fn.expand("%")
          if path == "" then
            vim.notify("[pi] no file in buffer", vim.log.levels.ERROR)
            return
          end
          session.try_forward(path)
        end,
      },
      {
        text = "Ask Selection",
        action = function()
          local ok, snacks = pcall(require, "snacks")
          if not ok then
            vim.notify("[pi] snacks.nvim required", vim.log.levels.ERROR)
            return
          end
          if sel then
            vim.notify(
              string.format("[pi] Selection: %s:%d-%d", sel.path, sel.start_row, sel.end_row)
            )
          end
          snacks.input({ prompt = "Ask Pi: " }, function(input)
            if not input or input == "" then
              return
            end
            session.try_forward(float.build_prompt(sel, input))
          end)
        end,
      },
    }

    -- Add all prompts
    for name, prompt in pairs(prompts) do
      table.insert(items, {
        text = "Prompt: " .. prompt.name,
        action = function()
          local text = prompt.prompt:gsub("@this", float.build_prompt(sel, ""))
          session.try_forward(text)
        end,
      })
    end

    vim.ui.select(items, {
      prompt = "Pi action:",
      format_item = function(item)
        return item.text
      end,
    }, function(item)
      if item and item.action then
        item.action()
      end
    end)
  end, { desc = "Pi: select action" })

  -- <leader>kf — pick a prompt (explain/fix/test/etc) and send with context
  vim.keymap.set("v", "<leader>pp", function()
    local prompts = require("pi-nvim.prompts").get_all()
    local sel = float.get_selection()
    local items = {}
    for name, prompt in pairs(prompts) do
      table.insert(items, { text = prompt.name .. " - " .. prompt.description, name = name })
    end

    vim.ui.select(items, {
      prompt = "Pi prompt:",
      format_item = function(item)
        return item.text
      end,
    }, function(item)
      if not item then
        return
      end
      local text = prompts[item.name].prompt:gsub("@this", float.build_prompt(sel, ""))
      require("pi-nvim.session").try_forward(text)
    end)
  end, { desc = "Pi: pick prompt" })

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
