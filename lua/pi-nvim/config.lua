local M = {}

M.defaults = {
  pi_cmd = "pi",
  snacks = true,
  float_input = {
    width = 80,
    height = 20,
    border = "rounded",
  },
  keymaps = {
    ask = "<leader>pa",
    select = "<leader>ps",
    file = "<leader>pf",
    prompt = "<leader>pp",
  },
}

function M.merge(user_opts)
  return vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), user_opts or {})
end

return M
