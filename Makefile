.PHONY: lint format test check test-session

lint:
	luacheck lua/

format:
	stylua lua/

check: lint format test

test:
	nvim --headless -u /Users/tnkapdy/.dotfiles/nvim/.config/nvim/init.lua \
		-c "lua require('lazy').load({plugins = {'plenary.nvim'}})" \
		-c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

test-config:
	nvim --headless -u /Users/tnkapdy/.dotfiles/nvim/.config/nvim/init.lua \
		-c "lua require('lazy').load({plugins = {'plenary.nvim'}})" \
		-c "PlenaryBustedFile tests/config_spec.lua"

test-rpc:
	nvim --headless -u /Users/tnkapdy/.dotfiles/nvim/.config/nvim/init.lua \
		-c "lua require('lazy').load({plugins = {'plenary.nvim'}})" \
		-c "PlenaryBustedFile tests/rpc_spec.lua"

test-float:
	nvim --headless -u /Users/tnkapdy/.dotfiles/nvim/.config/nvim/init.lua \
		-c "lua require('lazy').load({plugins = {'plenary.nvim'}})" \
		-c "PlenaryBustedFile tests/float_spec.lua"

test-session:
	nvim --headless -u /Users/tnkapdy/.dotfiles/nvim/.config/nvim/init.lua \
		-c "lua require('lazy').load({plugins = {'plenary.nvim'}})" \
		-c "PlenaryBustedFile tests/session_spec.lua"
