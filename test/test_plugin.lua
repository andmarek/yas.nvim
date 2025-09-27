-- Test script to manually load and test the plugin
-- Run this in Neovim with: :luafile test_plugin.lua

-- Add current directory to Lua path
local plugin_dir = vim.fn.getcwd()
package.path = package.path .. ';' .. plugin_dir .. '/lua/?.lua;' .. plugin_dir .. '/lua/?/init.lua'

print("Loading yas.nvim plugin...")

-- Try to require the main module
local ok, yas = pcall(require, 'yas')
if not ok then
  print("Error loading yas module: " .. yas)
  return
end

print("✓ Successfully loaded yas module")

-- Test setup
yas.setup()
print("✓ Setup completed")

-- Define the commands manually
vim.api.nvim_create_user_command('YasOpen', function()
  yas.open()
end, {})

vim.api.nvim_create_user_command('YasClose', function()
  yas.close()
end, {})

vim.api.nvim_create_user_command('YasToggle', function()
  yas.toggle()
end, {})

vim.api.nvim_create_user_command('YasFocus', function()
  yas.focus()
end, {})

print("✓ Commands registered: YasOpen, YasClose, YasToggle, YasFocus")
print("✓ Plugin loaded successfully! Try :YasToggle")
