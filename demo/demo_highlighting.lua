-- Demo: Real-time highlighting functionality in YAS
-- Run with: :luafile demo_highlighting.lua

-- Add the current directory to package path
package.path = package.path .. ';./lua/?.lua;./lua/?/init.lua'

local yas = require('yas')

print('🎯 YAS Real-time Highlighting Demo')
print('=====================================')
print()
print('This demo shows the new highlighting features:')
print('1. Secondary highlights (YasSecondary) for all search matches')
print('2. Primary highlights (YasPrimary) for focused/current match')
print('3. Real-time updates as you type in the search box')
print()
print('Features implemented:')
print('✓ Two-level highlighting with different highlight groups')
print('✓ Extmarks with namespaces for clean highlight management')
print('✓ Throttled updates (30ms) to prevent flickering')
print('✓ Buffer-local highlights that survive edits')
print('✓ Priority-based overlay system (focus > all matches)')
print('✓ Automatic cleanup when closing YAS finder')
print()

-- Setup YAS with highlighting
yas.setup({
    width = 50,
    position = 'left'
})

print('🚀 Starting YAS finder with highlighting enabled...')
print()
print('Try these steps:')
print('1. Type some text to search (e.g., "function", "test", "local")')
print('2. Notice secondary highlights appear in all open buffers')
print('3. Press Enter to navigate to a result')
print('4. See the focused match highlighted with primary style')
print('5. Press "q" to close and see highlights automatically cleared')
print()
print('Highlight groups you can customize:')
print('- YasSecondary: Background color for all matches')
print('- YasPrimary: Foreground color for focused match')
print()

-- Open YAS finder
vim.defer_fn(function()
    yas.open()
    print('YAS finder opened! Start typing to see real-time highlighting.')
end, 100)
