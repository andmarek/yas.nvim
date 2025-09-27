# YAS.nvim Agent Guide

## Goal
- Create a VsCode-like plugin for fuzzy search across files powered by Ripgrep. It should basically emulate VsCode's "Search" functionality.

## Test Commands
- Run plugin manually: `:luafile test_plugin.lua` (loads plugin in current Neovim session)
- Test ripgrep: `:luafile test_ripgrep.lua` (tests search backend)
- Test plugin: `:YasToggle` to open/close finder

## Architecture
- **Neovim plugin** structure with `lua/` and `plugin/` directories
- **Main modules**: `init.lua` (API), `window.lua` (UI), `search.lua` (backend), `config.lua` (settings)
- **Search backend**: ripgrep (preferred) with vim fallback for text search
- **UI**: Custom sidebar window with real-time search input

## Code Style
- **Lua conventions**: snake_case for functions/variables, PascalCase for modules
- **Module pattern**: Local `M = {}` table with functions, `return M` at end
- **Error handling**: pcall wrapper with vim.notify for user feedback
- **Config**: Deep merge user options with defaults in config.lua
- **Keymaps**: Buffer-local keymaps with callback functions, not command strings
- **State management**: Local state tables, not global variables
- **API calls**: Use vim.api.nvim_* functions, vim.fn.* for legacy functions
- **String formatting**: string.format() for complex strings, concatenation for simple
- **Comments**: Minimal, focus on why not what
