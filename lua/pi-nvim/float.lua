local M = {}

--- Get the current visual selection range and content
--- @return table|nil { path, start_row, end_row, code, filetype } or nil if no selection
function M.get_selection()
  -- Check if selection marks are valid (works after leaving visual mode)
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  -- getpos returns [bufnum, lnum, col, off] — lnum=0 means no valid mark
  if start_pos[2] == 0 or end_pos[2] == 0 then
    return nil
  end

  local start_row = start_pos[2]
  local end_row = end_pos[2]
  local start_col = start_pos[3]
  local end_col = end_pos[3]

  -- If no actual selection (same position), return nil
  if start_row == end_row and start_col == end_col then
    return nil
  end

  -- Get buffer lines
  local lines = vim.api.nvim_buf_get_lines(0, start_row - 1, end_row, false)
  if #lines == 0 then
    return nil
  end

  -- Adjust first and last lines for column selection
  if #lines == 1 then
    lines[1] = lines[1]:sub(start_col, end_col)
  else
    lines[1] = lines[1]:sub(start_col)
    lines[#lines] = lines[#lines]:sub(1, end_col)
  end

  local code = table.concat(lines, "\n")
  local path = vim.fn.expand("%")
  local filetype = vim.bo.filetype

  return {
    path = path,
    start_row = start_row,
    end_row = end_row,
    code = code,
    filetype = filetype,
  }
end

--- Build a context template for the input window
--- @param context table|nil Selection context from get_selection()
--- @return string
function M.build_template(context)
  if not context then
    return "# Ask Pi:\n"
  end

  return string.format(
    "# %s:%d-%d\n```%s\n%s\n```\n\n# Your question:\n",
    context.path,
    context.start_row,
    context.end_row,
    context.filetype,
    context.code
  )
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

--- Open a floating output window for streaming responses
--- @return number buf, number win
function M.open_output(config)
  config = config or require("pi-nvim.config").defaults

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"

  local width = config.float_output.width
  local height = config.float_output.height
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = config.float_output.border,
    title = " Pi Response ",
    title_pos = "center",
    focusable = true,
  })

  -- Close keymaps
  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })

  return buf, win
end

--- Append text to the output buffer
--- @param buf number Buffer handle
--- @param text string Text to append
function M.append_output(buf, text)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local lines = vim.split(text, "\n", { plain = true })
  local line_count = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_lines(buf, line_count - 1, line_count, false, lines)
end

--- Close a floating output window
--- @param win number Window handle
function M.close_output(win)
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

return M
