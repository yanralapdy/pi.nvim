local rpc = require("pi-nvim.rpc")
local config = require("pi-nvim.config")

describe("pi-nvim.integration", function()
  before_each(function()
    rpc.dispose()
    rpc.set_config(config.merge({
      pi_args = { "--mode", "rpc", "--no-session" },
    }))
  end)

  after_each(function()
    rpc.dispose()
  end)

  it("can spawn pi process", function()
    local job_id, err = rpc.spawn()
    assert.is_truthy(job_id)
    assert.is_nil(err)
    assert.is_true(rpc.is_running())
    rpc.dispose()
  end)

  it("can send a prompt and receive response", function()
    local got_end = false
    local got_text = false

    rpc.on_event("agent_end", function()
      got_end = true
    end)

    rpc.on_event("message_update", function(ev)
      local d = ev.assistantMessageEvent
      if d and d.type == "text_delta" and d.delta then
        got_text = true
      end
    end)

    local ok = rpc.prompt("Say only: TEST_OK")
    assert.is_true(ok)

    -- Wait up to 20s for response
    vim.wait(20000, function() return got_end end, 100)

    assert.is_true(got_end, "Should receive agent_end")
    assert.is_true(got_text, "Should receive text delta")
  end)
end)
