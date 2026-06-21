local M = {}

function M.check()
  vim.health.start("pi-nvim")

  -- Check pi CLI
  local has_pi = vim.fn.executable("pi") == 1
  if has_pi then
    vim.health.ok("pi CLI found")
  else
    vim.health.error("pi not found. Install: npm i -g @earendil-works/pi-coding-agent")
    return
  end

  -- Check pi version
  local version = vim.fn.system({ "pi", "--version" })
  vim.health.info("pi version: " .. vim.trim(version))

  -- Check config directory
  local agent_dir = vim.fn.expand("~/.pi/agent")
  if vim.fn.isdirectory(agent_dir) == 1 then
    vim.health.ok("Pi config directory found: " .. agent_dir)
  else
    vim.health.warn("Pi config directory not found. Run pi first to initialize.")
  end

  -- Check auth
  local auth_file = agent_dir .. "/auth.json"
  if vim.fn.filereadable(auth_file) == 1 then
    vim.health.ok("Auth file found")
  else
    vim.health.info("No auth.json found. Check env vars (ANTHROPIC_API_KEY, OPENAI_API_KEY, etc.)")
  end

  -- Check Neovim version
  if vim.fn.has("nvim-0.7") == 1 then
    vim.health.ok("Neovim version supports jobstart()")
  else
    vim.health.error("Neovim 0.7+ required for job control")
  end

  -- Optional dependencies
  local has_snacks = pcall(require, "snacks")
  if has_snacks then
    vim.health.ok("snacks.nvim found (enhanced input UI)")
  else
    vim.health.info("snacks.nvim not installed. Using built-in vim.ui.input")
  end
end

return M
