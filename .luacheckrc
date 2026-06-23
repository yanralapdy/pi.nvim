-- luacheck configuration for pi.nvim
std = "lua51"
globals = {
  "vim",
  "describe",
  "it",
  "assert",
  "before_each",
  "after_each",
  "pending",
}
read_globals = {
  "vim",
}
exclude_files = {
  "tests/**/*.lua",
}

-- Neovim plugin patterns
ignore = {
  "212/.*",  -- unused argument
  "213/.*",  -- unused loop variable
}

files["lua/pi-nvim/float.lua"] = {
  ignore = { "122" },  -- setting read-only field (vim.bo metatable)
}

files["lua/pi-nvim/chat.lua"] = {
  ignore = { "122" },  -- setting read-only field (vim.bo/wo metatable)
}
