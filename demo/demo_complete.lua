-- Complete demo of YAS with ALL occurrences highlighting
-- Run with: :luafile demo_complete.lua

-- Add the current directory to package path
package.path = package.path .. ';./lua/?.lua;./lua/?/init.lua'

local yas = require('yas')

print('🎯 YAS Complete Highlighting Demo')
print('==================================')
print()
print('NEW: Now highlights ALL occurrences in each file!')
print()
print('Features:')
print('✓ Secondary highlights (YasSecondary) for ALL occurrences')
print('✓ Primary highlights (YasPrimary) for focused match')
print('✓ Real-time updates as you type')
print('✓ Auto-highlight newly opened files')
print('✓ Case-insensitive search highlighting')
print()

-- Setup YAS
yas.setup({
    width = 60,
    position = 'left'
})

print('📂 Created sample_file.txt with multiple "test" occurrences')
print()

-- Open the sample file in background so it gets highlighted
vim.cmd('edit sample_file.txt')

print('🚀 Opening YAS finder...')
print()
print('Try this:')
print('1. Type "test" - see ALL occurrences highlighted in sample_file.txt')
print('2. Click on any result - see focused highlight overlay')
print('3. Try "function" to see function highlights')
print('4. Open other files - they auto-highlight with current search')
print()

vim.defer_fn(function()
    yas.open()
    print('YAS opened! Start typing to see ALL occurrences highlighted!')
end, 100)
