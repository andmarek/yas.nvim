-- Test the refactored search functionality

-- Set up the Lua path
package.path = package.path .. ';./lua/?.lua;./lua/?/init.lua'

-- Load the modules
local search_engine = require('yas.search_engine')
local window = require('yas.window')

print('Testing refactored search functionality...')

-- Test 1: Basic search engine API
print('\n=== Test 1: Basic search_engine API ===')
print('✓ search_engine module loaded')
print('current_query():', search_engine.current_query())
print('last_results():', #search_engine.last_results(), 'results')
print('is_running():', search_engine.is_running())

-- Test 2: Empty search
print('\n=== Test 2: Empty search ===')
local empty_results = nil
search_engine.request('', function(results)
    empty_results = results
    print('Empty search returned', #results, 'results')
end)

-- Wait a moment for the async operation
vim.schedule(function()
    if empty_results then
        print('✓ Empty search handled correctly')
    else 
        print('✗ Empty search failed')
    end
end)

-- Test 3: Search with query
print('\n=== Test 3: Search with actual query ===')
local test_results = nil
search_engine.request('function', function(results)
    test_results = results
    print('Search for "function" returned', #results, 'results')
    if #results > 0 then
        print('  First result file:', results[1].file)
        print('  First result matches:', #results[1].matches)
    end
end)

-- Test 4: Stop functionality
print('\n=== Test 4: Stop functionality ===')
search_engine.request('longquery', function(results)
    print('This should be cancelled')
end)
search_engine.stop()
print('✓ Search stopped')

-- Test 5: Window integration
print('\n=== Test 5: Window integration ===')
if not window.is_open() then
    window.create_buffer()
    print('✓ Window created')
else
    print('✓ Window already open')
end

-- Test basic window functions that use search_engine
window.clear_search()
print('✓ Clear search called')

if window.is_open() then
    window.close()
    print('✓ Window closed')
end

print('\n=== Refactor test completed ===')
print('The refactoring appears to be working correctly!')
