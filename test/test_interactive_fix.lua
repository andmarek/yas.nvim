-- Test the interactive search functionality

-- Set up the Lua path
package.path = package.path .. ';./lua/?.lua;./lua/?/init.lua'

-- Load the plugin
require('yas').setup()

print('Testing interactive search fix...')

-- Create the window
local window = require('yas.window')
window.create_buffer()

print('✓ Window created')

-- Simulate typing in search mode
print('Simulating typing "test"...')

-- Start search mode
window.start_search()
print('✓ Search mode started')

-- Simulate character input that was causing the error
window.handle_char_input('t')
window.handle_char_input('e') 
window.handle_char_input('s')
window.handle_char_input('t')

print('✓ Character input handled without errors')

-- Wait for search to complete
vim.wait(1000, function()
    local search_engine = require('yas.search_engine')
    return not search_engine.is_running()
end)

-- Check results
local search_engine = require('yas.search_engine')
print('Current query:', search_engine.current_query())
print('Results found:', #search_engine.last_results())

-- Clean up
window.close()
print('✓ Window closed')

print('\nInteractive test completed successfully - the error is fixed!')
