-- Test runner for YAS.nvim
-- Usage: :luafile run_tests.lua

-- Enable debug mode for internal state access
vim.g.yas_debug = true

-- Load the plugin and testing framework
local feedback = require('test_feedback')

print("YAS.nvim Test Suite")
print("===================")

-- Run cursor positioning tests
local success = feedback.run_cursor_tests()

if success then
    print("\n🎉 All tests passed!")
else
    print("\n❌ Some tests failed. Check output above.")
end

-- Show final state dump
print("\nFinal state dump:")
local state = feedback.dump_state()
for k, v in pairs(state) do
    if type(v) == 'table' and k ~= 'notifications' then
        print(k .. ": " .. vim.inspect(v))
    elseif k ~= 'notifications' then
        print(k .. ": " .. tostring(v))
    end
end

if #state.notifications > 0 then
    print("\nNotifications during test:")
    for _, notif in ipairs(state.notifications) do
        local level_str = notif.level == vim.log.levels.ERROR and "ERROR" or
                         notif.level == vim.log.levels.WARN and "WARN" or "INFO"
        print(string.format("  [%s] %s", level_str, notif.message))
    end
end
