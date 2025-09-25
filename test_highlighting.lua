-- Test highlighting functionality for YAS
-- Run with: :luafile test_highlighting.lua

-- Add the current directory to package path
package.path = package.path .. ';./lua/?.lua;./lua/?/init.lua'

local highlight = require('yas.highlight')

print('Testing YAS highlighting functionality...')

-- Test 1: Setup highlights
print('1. Setting up highlight groups...')
highlight.setup_highlights()

-- Create a test buffer with some content
local bufnr = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    'This is a test file',
    'Another test line with some content',
    'A third line for testing purposes',
    'Final line with test data'
})

-- Test 2: Highlight all matches
print('2. Testing highlight_all function...')
local test_matches = {
    { line_number = 1, column = 10, length = 4 },  -- "test" in line 1
    { line_number = 2, column = 8, length = 4 },   -- "test" in line 2
    { line_number = 3, column = 23, length = 7 },  -- "testing" in line 3
    { line_number = 4, column = 17, length = 4 }   -- "test" in line 4
}

highlight.highlight_all(bufnr, test_matches)
print('Applied secondary highlights to buffer ' .. bufnr)

-- Test 3: Highlight focus match
print('3. Testing highlight_focus function...')
vim.defer_fn(function()
    highlight.highlight_focus(bufnr, 2, 8, 4)  -- Focus on "test" in line 2
    print('Applied focus highlight to line 2')
    
    -- Test 4: Schedule refresh
    print('4. Testing scheduled refresh...')
    local new_matches = {
        { line_number = 1, column = 5, length = 2 },  -- "is" in line 1
        { line_number = 3, column = 2, length = 5 }   -- "third" in line 3
    }
    
    highlight.schedule_highlight_refresh(bufnr, new_matches, 50)
    print('Scheduled highlight refresh')
    
    -- Test 5: Clear highlights after a delay
    vim.defer_fn(function()
        print('5. Testing clear_highlights function...')
        highlight.clear_highlights(bufnr)
        print('Cleared all highlights from buffer ' .. bufnr)
        
        -- Clean up test buffer
        vim.api.nvim_buf_delete(bufnr, { force = true })
        print('Test completed successfully!')
        
        -- Show available namespaces
        print('Available highlight namespaces:')
        print('- yas_all (secondary highlights): ' .. highlight.ns_all)
        print('- yas_focus (primary/focus highlights): ' .. highlight.ns_focus)
        
        -- Show highlight groups
        print('\nHighlight groups defined:')
        print('- YasSecondary: background highlights for all matches')
        print('- YasPrimary: foreground highlights for focused match')
        
    end, 1500)
    
end, 500)

print('Highlighting tests initiated. Results will appear over the next 2 seconds.')
