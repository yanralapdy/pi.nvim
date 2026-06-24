.PHONY: lint format test check test-session

lint:
	luacheck lua/

format:
	stylua lua/

check: lint format test

test:
	nvim --headless -u /dev/null \
		--cmd "set rtp+=/tmp/plenary.nvim" \
		--cmd "set rtp+=." \
		-c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

test-config:
	nvim --headless -u /dev/null \
		--cmd "set rtp+=/tmp/plenary.nvim" \
		--cmd "set rtp+=." \
		-c "PlenaryBustedFile tests/config_spec.lua"

test-float:
	nvim --headless -u /dev/null \
		--cmd "set rtp+=/tmp/plenary.nvim" \
		--cmd "set rtp+=." \
		-c "PlenaryBustedFile tests/float_spec.lua"

test-session:
	nvim --headless -u /dev/null \
		--cmd "set rtp+=/tmp/plenary.nvim" \
		--cmd "set rtp+=." \
		-c "PlenaryBustedFile tests/session_spec.lua"
