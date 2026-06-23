local rpc = require("pi-nvim.rpc")

describe("pi-nvim.rpc", function()
  before_each(function()
    rpc.dispose()
  end)

  after_each(function()
    rpc.dispose()
  end)

  it("starts in stopped state", function()
    assert.is_false(rpc.is_running())
  end)

  it("can register and unsubscribe listeners", function()
    local called = false
    local unsub = rpc.on_event("test_event", function()
      called = true
    end)
    assert.is_function(unsub)
    unsub()
  end)

  it("dispatches to typed listeners", function()
    local received = nil
    rpc.on_event("message_update", function(ev)
      received = ev
    end)

    rpc._dispatch({ type = "message_update", data = "test" })
    assert.is.same({ type = "message_update", data = "test" }, received)
  end)

  it("send returns false when not running", function()
    local ok, err = rpc.send({ type = "test" })
    assert.is_false(ok)
    assert.is_truthy(err:match("not running"))
  end)

  it("prompt returns false when not running and spawn fails", function()
    -- pi_cmd set to non-existent binary
    rpc.set_config({ pi_cmd = "nonexistent_pi_binary", pi_args = {} })
    local ok, err = rpc.prompt("test")
    assert.is_false(ok)
  end)
end)
