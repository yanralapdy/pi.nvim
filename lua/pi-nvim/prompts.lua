-- pi-nvim prompts: predefined prompts for common tasks.

local M = {}

M.prompts = {
  explain = {
    name = "Explain",
    prompt = "Explain @this and its context",
    description = "Get an explanation of the selected code",
  },
  fix = {
    name = "Fix",
    prompt = "Fix @this",
    description = "Fix issues in the selected code",
  },
  document = {
    name = "Document",
    prompt = "Add comments documenting @this",
    description = "Add documentation comments",
  },
  test = {
    name = "Test",
    prompt = "Add tests for @this",
    description = "Generate tests for the selected code",
  },
  review = {
    name = "Review",
    prompt = "Review @this for correctness and readability",
    description = "Code review of the selected code",
  },
  optimize = {
    name = "Optimize",
    prompt = "Optimize @this for performance and readability",
    description = "Optimize the selected code",
  },
}

function M.get_all()
  return M.prompts
end

return M
