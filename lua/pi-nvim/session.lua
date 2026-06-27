-- pi-nvim session detection: find a running pi TUI in tmux and forward prompts to it.
-- Ponytail: tmux-only detection for v1; add PID-file detection if pi gets a --write-pid flag.

local M = {}

--- Check if tmux is available and we're inside a tmux session.
function M.is_tmux_available()
  if vim.fn.executable("tmux") ~= 1 then
    return false
  end
  return vim.env.TMUX ~= nil
end

--- Build a process tree from `ps -A`.
-- Returns {children = {[ppid] = {pid, ...}}, comm = {[pid] = comm}, cmd = {[pid] = args}}.
-- ponytail: one `ps -A` scan avoids flaky `pgrep -P` from vim.fn.system on macOS.
local function build_process_tree()
  local tree = { children = {}, comm = {}, cmd = {} }
  local raw = vim.fn.system({ "ps", "-A", "-o", "pid=,ppid=,comm=,command=" })
  if not raw or raw == "" then
    return tree
  end
  for _, line in ipairs(vim.split(vim.trim(raw), "\n", { trimempty = true })) do
    local pid, ppid, comm, args = line:match("^%s*(%d+)%s+(%d+)%s+(%S+)%s+(.+)$")
    if pid then
      tree.comm[pid] = comm
      tree.cmd[pid] = args
      tree.children[ppid] = tree.children[ppid] or {}
      table.insert(tree.children[ppid], pid)
    end
  end
  return tree
end

--- Recursively check if any descendant of pid matches the predicate.
local function tree_has_match(tree, pid, matches)
  local proc = { comm = tree.comm[tostring(pid)], args = tree.cmd[tostring(pid)] }
  if proc.comm and matches(proc) then
    return true
  end
  for _, child in ipairs(tree.children[tostring(pid)] or {}) do
    if tree_has_match(tree, child, matches) then
      return true
    end
  end
  return false
end

local function is_pi_tui(proc)
  -- Match pi executable (comm pi/pi-*/node/sh/bash) and pi as a distinct word in args.
  local comm = proc.comm or ""
  local comm_ok = comm == "pi"
    or comm:match("^pi[-_]")
    or comm == "node"
    or comm == "sh"
    or comm == "bash"
  if not comm_ok then
    return false
  end
  return proc.args:match("%f[%w]pi%f[%W]")
    and not proc.args:match("%-%-mode rpc")
    and not proc.args:match("%-%-no%-session")
end

--- List tmux panes matching a filter, sorted by priority.
--- Priority: same window → other windows in same session → other sessions.
--- @param filter_fn function(pane_pid): boolean
--- @return table list of pane_id strings
local function list_panes_by_priority(filter_fn)
  if not M.is_tmux_available() then
    return {}
  end

  local cur_window = vim.fn.trim(vim.fn.system({ "tmux", "display-message", "-p", "#{window_id}" }))
  local cur_session =
    vim.fn.trim(vim.fn.system({ "tmux", "display-message", "-p", "#{session_id}" }))

  local raw = vim.fn.system({
    "tmux",
    "list-panes",
    "-a",
    "-F",
    "#{pane_pid} #{pane_id} #{window_id} #{session_id}",
  })
  if not raw or raw == "" then
    return {}
  end

  local same_window, other_window, other_session = {}, {}, {}

  for _, line in ipairs(vim.split(raw, "\n", { trimempty = true })) do
    local pid, pane_id, win_id, sess_id = line:match("^(%d+) (%S+) (%S+) (%S+)")
    if pid and filter_fn(tonumber(pid)) then
      if win_id == cur_window then
        table.insert(same_window, pane_id)
      elseif sess_id == cur_session then
        table.insert(other_window, pane_id)
      else
        table.insert(other_session, pane_id)
      end
    end
  end

  local result = {}
  vim.list_extend(result, same_window)
  vim.list_extend(result, other_window)
  vim.list_extend(result, other_session)
  return result
end

--- Find a tmux pane running the pi TUI (not our RPC subprocess).
-- @return pane_id string or nil
function M.find_pi_pane()
  local tree = build_process_tree()
  local panes = list_panes_by_priority(function(pane_pid)
    return tree_has_match(tree, pane_pid, is_pi_tui)
  end)
  return panes[1]
end

--- Send text to a tmux pane using bracketed paste mode.
-- Handles multi-line text correctly (from kiro.nvim pattern).
-- @param text string Text to send
-- @param pane_id string Target pane
-- @param submit boolean|nil Press Enter after sending (default false)
-- @return boolean success
function M.forward_prompt(text, pane_id, submit)
  if not text or text == "" or not pane_id then
    return false
  end
  local function send(...)
    vim.fn.system({ "tmux", "send-keys", "-t", pane_id, ... })
  end
  -- Start bracketed paste
  send("\x1b[200~")
  -- Send each line, using Enter as separator
  local lines = vim.split(text, "\n", { plain = true })
  for i, line in ipairs(lines) do
    if i > 1 then
      send("\r")
    end
    send("-l", line)
  end
  -- End bracketed paste
  send("\x1b[201~")
  -- Auto-submit if requested
  if submit then
    send("Enter")
  end
  return true
end

local terminal_apps =
  { nvim = true, yazi = true, lazygit = true, btop = true, htop = true, tmux = true }

local function is_terminal_app(proc)
  if terminal_apps[proc.comm] then
    return true
  end
  -- Fallback for wrapper scripts that exec the real app.
  for app in pairs(terminal_apps) do
    if proc.args:match("%f[%w]" .. app .. "%f[%W]") then
      return true
    end
  end
  return false
end

--- Find a tmux pane that's just a terminal (no app running).
-- @return pane_id string or nil
function M.find_free_terminal()
  local tree = build_process_tree()
  local panes = list_panes_by_priority(function(pane_pid)
    return not tree_has_match(tree, pane_pid, is_terminal_app)
  end)
  return panes[1]
end

--- Open pi in a tmux pane and send the prompt.
-- Finds a free terminal or creates a new pane.
-- @param submit boolean|nil Press Enter after sending (default false)
-- @return boolean success
function M.open_pi_with_prompt(text, submit)
  if not M.is_tmux_available() then
    return false
  end

  local pane_id = M.find_free_terminal()
  if pane_id then
    local function raw_send(...)
      vim.fn.system({ "tmux", "send-keys", "-t", pane_id, ... })
    end
    raw_send("-l", "pi")
    raw_send("Enter")
    vim.defer_fn(function()
      M.forward_prompt(text, pane_id, submit)
    end, 1500)
    return true
  end

  -- No free pane — create a new one
  local pi_cmd = require("pi-nvim.config").defaults.pi_cmd
  vim.fn.system({ "tmux", "split-window", "-h", "-l", "50%", pi_cmd })
  if vim.v.shell_error ~= 0 then
    return false
  end
  local new_pane = vim.fn.trim(vim.fn.system({ "tmux", "display-message", "-p", "#{pane_id}" }))
  vim.defer_fn(function()
    M.forward_prompt(text, new_pane, submit)
  end, 1500)
  return true
end

--- Open pi in a nvim terminal (vertical split, :Vex style).
-- Sends the prompt after pi starts.
-- @param submit boolean|nil Press Enter after sending (default false)
-- @return boolean success
function M.open_pi_in_nvim_terminal(text, submit)
  -- Save current window
  local prev_win = vim.api.nvim_get_current_win()

  -- Open vertical split with terminal
  vim.cmd("botright vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(win, math.floor(vim.o.columns / 2))

  -- Start terminal with pi
  local pi_cmd = require("pi-nvim.config").defaults.pi_cmd
  vim.cmd("terminal " .. pi_cmd)
  local buf = vim.api.nvim_get_current_buf()
  local chan = vim.bo.channel

  -- Close the split when pi exits
  vim.api.nvim_create_autocmd("TermClose", {
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
      end)
    end,
  })

  -- Wait for pi to start, then send the prompt
  vim.defer_fn(function()
    pcall(vim.api.nvim_chan_send, chan, text .. (submit and "\r" or ""))
  end, 1000)

  -- Return to previous window
  if vim.api.nvim_win_is_valid(prev_win) then
    vim.api.nvim_set_current_win(prev_win)
  end

  return true
end

--- Testable hooks for reading buffer options.
function M._buf_buftype(buf)
  return vim.bo[buf].buftype
end

function M._buf_channel(buf)
  return vim.bo[buf].channel
end

--- Find an existing pi process running in a Neovim terminal buffer.
-- @return number|nil chan, number|nil buf
function M.find_pi_terminal()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if M._buf_buftype(buf) == "terminal" then
      local chan = M._buf_channel(buf)
      if chan and chan > 0 then
        local info = vim.api.nvim_get_chan_info(chan)
        local argv = info and info.argv
        if argv then
          -- ponytail: terminal spawns a shell (zsh/bash/sh) wrapping the command.
          -- Check all argv elements for "pi" as a distinct word, not just argv[1].
          for _, arg in ipairs(argv) do
            if arg:match("%f[%w]pi%f[^%w]") or vim.fn.fnamemodify(arg, ":t") == "pi" then
              return chan, buf
            end
          end
        end
      end
    end
  end
  return nil, nil
end

--- Send text to an existing nvim terminal pi session.
-- @param submit boolean|nil Press Enter after sending (default false)
-- @return boolean success
function M.forward_to_terminal(text, chan, submit)
  if not chan or chan <= 0 then
    return false
  end
  pcall(vim.api.nvim_chan_send, chan, text .. (submit and "\r" or ""))
  return true
end

--- Try to forward text to an existing pi pane, or open pi in a terminal.
-- @param text string Text to send
-- @param submit boolean|nil Press Enter after sending (default false)
-- @return boolean forwarded
function M.try_forward(text, submit)
  if not text or text == "" then
    return false
  end
  if M.is_tmux_available() then
    local pane_id = M.find_pi_pane()
    if pane_id then
      return M.forward_prompt(text, pane_id, submit)
    end
    return M.open_pi_with_prompt(text, submit)
  end
  local chan = M.find_pi_terminal()
  if chan then
    return M.forward_to_terminal(text, chan, submit)
  end
  return M.open_pi_in_nvim_terminal(text, submit)
end

return M
