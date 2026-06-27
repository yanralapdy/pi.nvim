local M = {}

local function ask()
  local float = require("pi-nvim.float")
  local session = require("pi-nvim.session")

  local context = float.get_selection()

  float.open_input(function(text)
    if not text then
      return
    end
    local prompt = float.build_prompt(context, text)
    session.try_forward(prompt)
  end)
end

function M.setup(user_opts)
  local config = require("pi-nvim.config").merge(user_opts)
  local float = require("pi-nvim.float")

  -- Setup visual selection autocmds
  float.setup_visual_autocmds()

  -- Keybinding: <leader>pa — ask a question (input dialog)
  vim.keymap.set("v", config.keymaps.ask, function()
    ask()
  end, { desc = "Ask Pi" })

  -- <leader>pf — send current file path to pi
  vim.keymap.set({ "v", "n" }, config.keymaps.file, function()
    local session = require("pi-nvim.session")
    local path = vim.fn.expand("%")
    if path == "" then
      vim.notify("[pi] no file in buffer", vim.log.levels.ERROR)
      return
    end
    if session.try_forward(path) then
      vim.notify("[pi] sent file: " .. path)
    else
      vim.notify("[pi] no pi session found", vim.log.levels.ERROR)
    end
  end, { desc = "Pi: send file path" })

  -- <leader>ps — unified action menu (send file, ask selection, pick prompt)
  vim.keymap.set("v", config.keymaps.select, function()
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
          session.try_forward(text, true)
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

  -- <leader>pp — pick a prompt (explain/fix/test/etc) and send with context
  vim.keymap.set("v", config.keymaps.prompt, function()
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
      require("pi-nvim.session").try_forward(text, true)
    end)
  end, { desc = "Pi: pick prompt" })

  -- User command: :PiAsk
  vim.api.nvim_create_user_command("PiAsk", function()
    ask()
  end, { desc = "Ask Pi a question" })

  return { config = config }
end

return M
