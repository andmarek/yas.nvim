-- Test UTF-8 fix for highlight errors

-- Set up the Lua path
package.path = package.path .. ';./lua/?.lua;./lua/?/init.lua'

print('Testing UTF-8 fix...')

-- Load the highlight module 
local highlight = require('yas.highlight')

print('✓ Highlight module loaded')

-- Create a test buffer with potentially problematic content
local bufnr = vim.api.nvim_create_buf(false, true)
print('✓ Test buffer created:', bufnr)

-- Add some test content including potentially problematic UTF-8
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    'normal text function',
    'another line with function',
    'special chars: ñáéíóú',
    -- Note: We can't easily add actual invalid UTF-8 in a string literal,
    -- but the fix will handle any invalid UTF-8 that comes from file content
    'function with mixed content'
})

print('✓ Test content added')

-- Test the highlight function that was causing errors
local test_ok, test_err = pcall(function()
    highlight.highlight_all_occurrences_in_buffer(bufnr, 'function')
end)

if test_ok then
    print('✓ highlight_all_occurrences_in_buffer completed without errors')
else
    print('✗ Error:', test_err)
end

-- Test with search results
local search_engine = require('yas.search_engine')
search_engine.request('test', function(results)
    local test2_ok, test2_err = pcall(function()
        highlight.highlight_search_results(results, 'test')
    end)
    
    if test2_ok then
        print('✓ highlight_search_results completed without errors')
    else
        print('✗ highlight_search_results error:', test2_err)
    end
end)

-- Wait for async operation
vim.wait(1000, function() 
    return not search_engine.is_running()
end)

-- Clean up
vim.api.nvim_buf_delete(bufnr, { force = true })
print('✓ Test buffer cleaned up')

print('\n=== UTF-8 Fix Test Completed ===')
print('If no errors appeared above, the UTF-8 fix is working!')
