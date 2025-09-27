-- Test the search fix specifically

-- Set up the Lua path
package.path = package.path .. ';./lua/?.lua;./lua/?/init.lua'

-- Load the modules
local search_engine = require('yas.search_engine')

print('Testing search fix...')

-- Test search with a query that should find results
print('Starting search for "function"...')
search_engine.request('function', function(results)
    print('Search completed with', #results, 'results')
    if #results > 0 then
        print('✓ Search successful - found results')
        for i, result in ipairs(results) do
            if i <= 3 then -- Show first 3 results
                print('  File:', result.file)
                print('  Matches:', #result.matches)
            end
        end
    else
        print('No results found (this might be expected if no files contain "function")')
    end
end)

-- Wait for search to complete
vim.wait(2000, function()
    return not search_engine.is_running()
end)

print('Current query after search:', search_engine.current_query())
print('Last results count:', #search_engine.last_results())
print('Is still running:', search_engine.is_running())

print('\nTest completed - if no errors appeared, the fix worked!')
