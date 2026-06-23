local M = {}

--- Cached visual range (captured by ModeChanged autocmd)
local _visual_range = nil

--- Setup autocmds to capture visual selection
function M.setup_visual_autocmds()
  local group = vim.api.nvim_create_augroup("PiNvimVisual", { clear = true })

  -- Capture marks when exiting visual mode
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    pattern = "[vVxX]:n",
    callback = function()
      local srow = vim.fn.getpos("'<")[2]
      local erow = vim.fn.getpos("'>")[2]
      if srow > 0 and erow > 0 then
        _visual_range = { srow = srow, erow = erow }
      end
    end,
  })

  -- Clear cache when entering visual mode
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    pattern = "n:[vVxX]",
    callback = function()
      _visual_range = nil
    end,
  })
end

--- Get the current visual selection range and content
--- @return table|nil { path, start_row, end_row, code, filetype } or nil if no selection
function M.get_selection()
  local mode = vim.fn.mode()
  local srow, erow

  -- If in visual mode, use live positions (marks aren't set yet)
  if mode:match("[vVxX]") then
    srow = vim.fn.getpos("v")[2]
    erow = vim.fn.getpos(".")[2]
  else
    -- After visual mode, check marks first, then cache
    local mark_s = vim.fn.getpos("'<")[2]
    local mark_e = vim.fn.getpos("'>")[2]
    if mark_s > 0 and mark_e > 0 then
      srow, erow = mark_s, mark_e
    elseif _visual_range then
      srow, erow = _visual_range.srow, _visual_range.erow
    else
      return nil
    end
  end

  if not srow or not erow or srow == 0 or erow == 0 then
    return nil
  end

  if srow > erow then
    srow, erow = erow, srow
  end

  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, srow - 1, erow, false)
  if #lines == 0 then
    return nil
  end

  return {
    path = vim.fn.expand("%"),
    start_row = srow,
    end_row = erow,
    code = table.concat(lines, "\n"),
    filetype = vim.bo[buf].filetype,
  }
end

--- Build a prompt with optional selection context.
--- @param sel table|nil Selection from get_selection()
--- @param text string The user's question or prompt template
--- @return string
function M.build_prompt(sel, text)
  if not sel then
    return text
  end
  return string.format(
    "%s:%d-%d\n```%s\n%s\n```\n\n%s",
    sel.path,
    sel.start_row,
    sel.end_row,
    sel.filetype,
    sel.code,
    text
  )
end

--- Build the initial value for the input window.
--- @param sel table|nil Selection from get_selection()
--- @return string
function M.build_template(sel)
  -- ponytail: empty default; pre-filling the full context block duplicates build_prompt's work.
  return ""
end

--- Open a floating input window
--- @param callback function(text|nil) Called with the input text, or nil on cancel
--- @param opts table|nil { context: table|nil, config: table|nil }
function M.open_input(callback, opts)
  opts = opts or {}
  local context = opts.context
  local config = opts.config or require("pi-nvim.config").defaults

  -- Try snacks.nvim first
  if config.snacks then
    local ok, snacks = pcall(require, "snacks")
    if ok and snacks.input then
      local template = M.build_template(context)
      snacks.input({
        prompt = "Ask Pi: ",
        value = template,
        win = {
          width = config.float_input.width,
          height = config.float_input.height,
          border = config.float_input.border,
        },
      }, function(input)
        if input and input ~= "" then
          callback(input)
        else
          callback(nil)
        end
      end)
      return
    end
  end

  -- Fallback: manual floating window
  M._open_fallback_input(callback, config, context)
end

--- Fallback input using a floating window with a scratch buffer
--- @param callback function(text|nil)
--- @param config table Plugin config
--- @param context table|nil Selection context
function M._open_fallback_input(callback, config, context)
  local template = M.build_template(context)
  local lines = vim.split(template, "\n", { plain = true })

  -- Create scratch buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "pi-nvim-input"

  -- Calculate window dimensions
  local width = config.float_input.width
  local height = math.min(#lines + 2, config.float_input.height)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create floating window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = config.float_input.border,
    title = " Ask Pi ",
    title_pos = "center",
  })

  -- Place cursor at end of template
  vim.api.nvim_win_set_cursor(win, { #lines, #lines[#lines] + 1 })
  vim.cmd("startinsert")

  -- Keymaps
  local function submit()
    local content = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = table.concat(content, "\n")
    vim.api.nvim_win_close(win, true)
    vim.cmd("stopinsert")
    callback(text)
  end

  local function cancel()
    vim.api.nvim_win_close(win, true)
    vim.cmd("stopinsert")
    callback(nil)
  end

  -- Enter to submit (normal mode)
  vim.keymap.set("n", "<CR>", submit, { buffer = buf, nowait = true })
  -- Escape to cancel
  vim.keymap.set("n", "<Esc>", cancel, { buffer = buf, nowait = true })
  -- Ctrl-C to cancel in insert mode
  vim.keymap.set("i", "<C-c>", cancel, { buffer = buf, nowait = true })
  -- Enter in insert mode submits (go to normal mode first to avoid newline)
  vim.keymap.set("i", "<CR>", function()
    vim.cmd("stopinsert")
    submit()
  end, { buffer = buf, nowait = true })
end

return M
