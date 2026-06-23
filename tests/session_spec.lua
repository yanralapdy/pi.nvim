local session = require("pi-nvim.session")

describe("pi-nvim.session", function()
  local orig_executable, orig_system, orig_tmux

  before_each(function()
    orig_executable = vim.fn.executable
    orig_system = vim.fn.system
    orig_tmux = vim.env.TMUX
  end)

  after_each(function()
    vim.fn.executable = orig_executable
    vim.fn.system = orig_system
    vim.env.TMUX = orig_tmux
  end)

  it("is_tmux_available returns false when tmux not installed", function()
    vim.fn.executable = function(cmd)
      if cmd == "tmux" then
        return 0
      end
      return orig_executable(cmd)
    end
    assert.is_false(session.is_tmux_available())
  end)

  it("is_tmux_available returns false when not in tmux session", function()
    vim.fn.executable = function()
      return 1
    end
    vim.env.TMUX = nil
    assert.is_false(session.is_tmux_available())
  end)

  it("is_tmux_available returns true when tmux is installed and in session", function()
    vim.fn.executable = function()
      return 1
    end
    vim.env.TMUX = "/tmp/tmux-1000/default,12345,0"
    assert.is_true(session.is_tmux_available())
  end)

  it("find_pi_pane returns nil when no pi processes in tmux", function()
    vim.fn.executable = function()
      return 1
    end
    vim.env.TMUX = "/tmp/tmux-1000/default,12345,0"
    vim.fn.system = function(cmd)
      if cmd[1] == "tmux" and cmd[2] == "display-message" then
        local fmt = cmd[4] or ""
        if fmt:match("window_id") then
          return "@1"
        end
        if fmt:match("session_id") then
          return "sess1"
        end
      end
      if cmd[1] == "tmux" and cmd[2] == "list-panes" then
        return "1001 %0 @1 sess1\n1002 %1 @1 sess1\n"
      end
      if cmd[1] == "ps" then
        return "1001 999 zsh zsh\n1002 999 zsh zsh\n5001 1002 nvim nvim\n"
      end
      return ""
    end
    assert.is_nil(session.find_pi_pane())
  end)

  it("find_pi_pane returns pane_id when pi found as descendant", function()
    vim.fn.executable = function()
      return 1
    end
    vim.env.TMUX = "/tmp/tmux-1000/default,12345,0"
    vim.fn.system = function(cmd)
      if cmd[1] == "tmux" and cmd[2] == "display-message" then
        local fmt = cmd[4] or ""
        if fmt:match("window_id") then
          return "@1"
        end
        if fmt:match("session_id") then
          return "sess1"
        end
      end
      if cmd[1] == "tmux" and cmd[2] == "list-panes" then
        return "1001 %0 @1 sess1\n2001 %1 @1 sess1\n"
      end
      if cmd[1] == "ps" then
        return "1001 999 zsh zsh\n2001 999 zsh zsh\n3001 2001 node node /path/to/pi\n"
      end
      return ""
    end
    assert.is.equal("%1", session.find_pi_pane())
  end)

  it("find_pi_pane filters out our RPC subprocess", function()
    vim.fn.executable = function()
      return 1
    end
    vim.env.TMUX = "/tmp/tmux-1000/default,12345,0"
    vim.fn.system = function(cmd)
      if cmd[1] == "tmux" and cmd[2] == "display-message" then
        local fmt = cmd[4] or ""
        if fmt:match("window_id") then
          return "@1"
        end
        if fmt:match("session_id") then
          return "sess1"
        end
      end
      if cmd[1] == "tmux" and cmd[2] == "list-panes" then
        return "2001 %1 @1 sess1\n"
      end
      if cmd[1] == "ps" then
        return "2001 999 zsh zsh\n3001 2001 node node /path/to/pi --mode rpc --no-session\n"
      end
      return ""
    end
    assert.is_nil(session.find_pi_pane())
  end)

  it("find_pi_pane ignores the ps command itself", function()
    vim.fn.executable = function()
      return 1
    end
    vim.env.TMUX = "/tmp/tmux-1000/default,12345,0"
    vim.fn.system = function(cmd)
      if cmd[1] == "tmux" and cmd[2] == "display-message" then
        local fmt = cmd[4] or ""
        if fmt:match("window_id") then
          return "@1"
        end
        if fmt:match("session_id") then
          return "sess1"
        end
      end
      if cmd[1] == "tmux" and cmd[2] == "list-panes" then
        return "1001 %0 @1 sess1\n"
      end
      if cmd[1] == "ps" then
        return "1001 999 zsh zsh\n5001 1001 ps /bin/ps -A -o pid=,ppid=,comm=,command=\n"
      end
      return ""
    end
    assert.is_nil(session.find_pi_pane())
  end)

  it("find_free_terminal skips panes running nvim", function()
    vim.fn.executable = function()
      return 1
    end
    vim.env.TMUX = "/tmp/tmux-1000/default,12345,0"
    vim.fn.system = function(cmd)
      if cmd[1] == "tmux" and cmd[2] == "display-message" then
        local fmt = cmd[4] or ""
        if fmt:match("window_id") then
          return "@1"
        end
        if fmt:match("session_id") then
          return "sess1"
        end
      end
      if cmd[1] == "tmux" and cmd[2] == "list-panes" then
        return "1001 %0 @1 sess1\n1002 %1 @1 sess1\n"
      end
      if cmd[1] == "ps" then
        return "1001 999 zsh zsh\n1002 999 zsh zsh\n5001 1002 nvim nvim\n"
      end
      return ""
    end
    assert.is.equal("%0", session.find_free_terminal())
  end)

  it("try_forward returns false for empty text", function()
    vim.fn.executable = function()
      return 0
    end
    vim.env.TMUX = nil
    assert.is_false(session.try_forward(""))
    assert.is_false(session.try_forward(nil))
  end)

  it("try_forward returns true when forwarded successfully", function()
    vim.fn.executable = function()
      return 1
    end
    vim.env.TMUX = "/tmp/tmux-1000/default,12345,0"
    vim.fn.system = function(cmd)
      if cmd[1] == "tmux" and cmd[2] == "list-panes" then
        return "2001 %1 @1 sess1\n"
      end
      if cmd[1] == "ps" then
        return "2001 999 zsh zsh\n3001 2001 node node /path/to/pi\n"
      end
      return ""
    end
    assert.is_true(session.try_forward("hello from nvim"))
  end)
end)
