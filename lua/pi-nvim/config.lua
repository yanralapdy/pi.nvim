local M = {}

M.defaults = {
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
}

function M.merge(user_opts)
  return vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), user_opts or {})
end

return M
