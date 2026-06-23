local M = {}

M.state = {
  job_id = nil,
  is_running = false,
  is_streaming = false,
  buffer = {},
  buffer_str = "",
  listeners = {},
}

local config = nil

function M.set_config(cfg)
  config = cfg
end

--- Check if the RPC process is running
--- @return boolean
function M.is_running()
  return M.state.is_running
end

function M.spawn(cfg)
  cfg = cfg or config
  if not cfg then
    return nil, "No config provided. Call rpc.set_config() first."
  end

  -- Kill existing process if any
  if M.state.job_id then
    pcall(vim.fn.jobstop, M.state.job_id)
  end

  -- Validate pi is executable (R-01: security check)
  if vim.fn.executable(cfg.pi_cmd) ~= 1 then
    return nil,
      "pi not found at '" .. cfg.pi_cmd .. "'. Install: npm i -g @earendil-works/pi-coding-agent"
  end

  -- R-01: Use array form to prevent shell injection
  local cmd = vim.list_extend({ cfg.pi_cmd }, cfg.pi_args)

  -- Ensure correct node version is first in PATH (derive from pi's location)
  local pi_dir = vim.fn.fnamemodify(vim.fn.exepath(cfg.pi_cmd), ":h")
  local path = pi_dir .. ":" .. (vim.env.PATH or "")

  M.state.job_id = vim.fn.jobstart(cmd, {
    pty = true,
    env = { PATH = path, HOME = vim.env.HOME },
    on_stdout = function(_, data)
      if data then
        M._on_data(data)
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            vim.notify("[pi stderr] " .. line, vim.log.levels.WARN)
          end
        end
      end
    end,
    on_exit = function(_, code)
      local was_running = M.state.is_running
      M.state.is_running = false
      M.state.is_streaming = false

      -- R-02: Auto-restart on unexpected crash
      if was_running and code ~= 0 and code ~= 143 then
        vim.notify("[pi] Process crashed (code " .. code .. "). Restarting...", vim.log.levels.WARN)
        vim.defer_fn(function()
          M.spawn()
        end, 500)
      elseif code ~= 0 and code ~= 143 then
        vim.notify("[pi] Process exited with code " .. tostring(code), vim.log.levels.ERROR)
      end
    end,
  })

  if M.state.job_id <= 0 then
    M.state.job_id = nil
    return nil, "Failed to start pi. Is it installed? (npm i -g @earendil-works/pi-coding-agent)"
  end

  M.state.is_running = true
  M.state.buffer = {}
  M.state.buffer_str = ""
  return M.state.job_id
end

--- R-04: Efficient JSONL reader using table-based buffer
function M._on_data(chunks)
  -- Append chunks to buffer table
  for _, chunk in ipairs(chunks) do
    table.insert(M.state.buffer, chunk)
  end

  -- Process complete lines
  while true do
    -- Concatenate only when looking for line boundaries
    local buf = table.concat(M.state.buffer)
    M.state.buffer = {}

    -- Prepend any leftover from previous call
    if #M.state.buffer_str > 0 then
      buf = M.state.buffer_str .. buf
      M.state.buffer_str = ""
    end

    -- Find line terminator (\n or \r)
    local newline = buf:find("\n", 1, true)
    local cr = buf:find("\r", 1, true)
    local split_at = newline and cr and math.min(newline, cr) or newline or cr
    if not split_at then
      -- No complete line found, save remainder
      M.state.buffer_str = buf
      break
    end

    local line = buf:sub(1, split_at - 1)
    -- Skip past the line terminator(s)
    local next_pos = split_at + 1
    -- If we hit \r, check if followed by \n (\r\n)
    if buf:sub(split_at, split_at) == "\r" and buf:sub(next_pos, next_pos) == "\n" then
      next_pos = next_pos + 1
    end
    -- Save remaining for next iteration
    M.state.buffer_str = buf:sub(next_pos)

    if #line > 0 then
      local ok, msg = pcall(vim.json.decode, line)
      if ok then
        M._dispatch(msg)
      end
    end
  end
end

function M._dispatch(event)
  -- Update state
  if event.type == "agent_start" then
    M.state.is_streaming = true
  elseif event.type == "agent_end" then
    M.state.is_streaming = false
  end

  local listeners = M.state.listeners[event.type]
  if listeners then
    for _, cb in ipairs(listeners) do
      cb(event)
    end
  end
end

function M.on_event(event_type, callback)
  if not M.state.listeners[event_type] then
    M.state.listeners[event_type] = {}
  end
  table.insert(M.state.listeners[event_type], callback)

  -- Return unsubscribe function
  return function()
    local list = M.state.listeners[event_type]
    if list then
      for i, cb in ipairs(list) do
        if cb == callback then
          table.remove(list, i)
          break
        end
      end
    end
  end
end

function M.send(cmd)
  if not M.state.job_id or not M.state.is_running then
    return false, "RPC process not running"
  end
  local json = vim.json.encode(cmd)
  local ok = pcall(vim.fn.chansend, M.state.job_id, json .. "\n")
  return ok
end

function M.prompt(text)
  if not M.state.is_running then
    local _, err = M.spawn()
    if err then
      return false, err
    end
  end
  return M.send({ type = "prompt", message = text })
end

function M.abort()
  return M.send({ type = "abort" })
end

function M.dispose()
  if M.state.is_streaming then
    pcall(M.abort)
  end
  if M.state.job_id then
    pcall(vim.fn.jobstop, M.state.job_id)
  end
  M.state.job_id = nil
  M.state.is_running = false
  M.state.is_streaming = false
  M.state.buffer = {}
  M.state.buffer_str = ""
  M.state.listeners = {}
end

return M
