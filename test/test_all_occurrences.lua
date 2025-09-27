-- Test all occurrences highlighting
-- Run with: :luafile test_all_occurrences.lua

-- Add the current directory to package path
package.path = package.path .. ';./lua/?.lua;./lua/?/init.lua'

local highlight = require('yas.highlight')

print('Testing ALL occurrences highlighting...')

-- Initialize highlight groups
highlight.setup_highlights()

-- Create a test buffer with multiple occurrences of "test"
local bufnr = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    'This is a test file for testing',
    'Another test line with test content',
    'A third line for testing TEST purposes',
    'Final test line with Test data and testing functions'
})

print('Created buffer with content:')
local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
for i, line in ipairs(lines) do
    print(string.format('  %d: %s', i, line))
end

print('\nSearching for all occurrences of "test"...')

-- Test the new function
highlight.highlight_all_occurrences_in_buffer(bufnr, 'test')

-- Wait a moment for the highlighting to apply
vim.defer_fn(function()
    print('✓ Applied highlights to ALL occurrences of "test" in the buffer')
    print('This should highlight:')
    print('  - Line 1: "test" and "test"ing')
    print('  - Line 2: "test" (2 times)')
    print('  - Line 3: "test"ing and "TEST"')
    print('  - Line 4: "Test" and "test"ing')
    
    print('\nTotal expected highlights: ~8 occurrences')
    
    -- Test focus highlight on top
    vim.defer_fn(function()
        print('\nAdding focus highlight on line 2, col 8...')
        highlight.highlight_focus(bufnr, 2, 8, 4)
        print('✓ Focus highlight should overlay secondary highlight')
        
        -- Clean up
        vim.defer_fn(function()
            highlight.clear_highlights(bufnr)
            vim.api.nvim_buf_delete(bufnr, { force = true })
            print('\n✓ Test completed - all highlights cleared')
        end, 1000)
        
    end, 500)
    
end, 200)

print('Test initiated. Watch for highlights to appear...')
