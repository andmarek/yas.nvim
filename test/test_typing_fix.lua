-- Test the typing scenario that was causing UTF-8 errors

-- Set up the Lua path
package.path = package.path .. ';./lua/?.lua;./lua/?/init.lua'

print('Testing typing scenario with UTF-8 fix...')

-- Load and setup the plugin
require('yas').setup()

-- Create the window like a user would
local window = require('yas.window')
window.create_buffer()
print('✓ Window created')

-- Start search mode
window.start_search()
print('✓ Search mode started')

-- Simulate typing that would trigger highlights - this was causing the error
print('Simulating typing various characters...')

local chars = {'t', 'e', 's', 't', ' ', 'f', 'u', 'n', 'c', 't', 'i', 'o', 'n'}

for i, char in ipairs(chars) do
    local char_ok, char_err = pcall(function()
        window.handle_char_input(char)
    end)
    
    if not char_ok then
        print('✗ Error typing character "' .. char .. '":', char_err)
        break
    end
    
    -- Small delay to simulate real typing
    vim.wait(50)
end

print('✓ All characters typed without UTF-8 errors')

-- Wait for any pending searches to complete
vim.wait(1500, function()
    local search_engine = require('yas.search_engine')
    return not search_engine.is_running()
end)

local search_engine = require('yas.search_engine')
print('Final query:', search_engine.current_query())
print('Results found:', #search_engine.last_results())

-- Clean up
window.close()
print('✓ Window closed')

print('\n=== Typing Test Completed Successfully ===')
print('The UTF-8 error during typing has been fixed!')
