local float = require("pi-nvim.float")

describe("pi-nvim.float", function()
  it("returns nil when no selection marks", function()
    local result = float.get_selection()
    -- In headless mode with no buffer, should return nil
    assert.is_nil(result)
  end)

  it("builds prompt without context", function()
    local prompt = float.build_prompt(nil, "hello world")
    assert.is.equal("hello world", prompt)
  end)

  it("builds prompt with context", function()
    local sel = {
      path = "test.lua",
      start_row = 10,
      end_row = 20,
      filetype = "lua",
      code = "print('hello')",
    }
    local prompt = float.build_prompt(sel, "what does this do?")
    assert.is_truthy(prompt:match("test%.lua:10%-20"))
    assert.is_truthy(prompt:match("lua"))
    assert.is_truthy(prompt:match("what does this do?"))
  end)

end)
