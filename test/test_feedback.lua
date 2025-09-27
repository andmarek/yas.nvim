-- Test feedback framework for YAS.nvim
-- Provides automated testing and state inspection for agent development

local M = {}

-- Test state tracking
local test_state = {
    results = {},
    current_test = nil,
    start_time = nil,
}

-- Helper to capture vim notifications
local notifications = {}
local original_notify = vim.notify
vim.notify = function(msg, level, opts)
    table.insert(notifications, {
        message = msg,
        level = level or vim.log.levels.INFO,
        time = vim.fn.reltime(),
        opts = opts
    })
    return original_notify(msg, level, opts)
end

-- Test helper functions
function M.start_test(name)
    test_state.current_test = name
    test_state.start_time = vim.fn.reltime()
    notifications = {}
    print("Starting test: " .. name)
end

function M.assert_cursor_position(expected_row, expected_col, description)
    local yas = require('yas')
    local window = require('yas.window')
    
    if not window.is_open() then
        error("YAS window is not open for test: " .. (description or "cursor position"))
    end
    
    -- Get current cursor position  
    local winnr = vim.api.nvim_get_current_win()
    local row, col = unpack(vim.api.nvim_win_get_cursor(winnr))
    
    local success = (row == expected_row and col == expected_col)
    local result = {
        test = description or "cursor position",
        expected = string.format("row=%d, col=%d", expected_row, expected_col),
        actual = string.format("row=%d, col=%d", row, col),
        success = success,
        time = vim.fn.reltime(test_state.start_time)
    }
    
    table.insert(test_state.results, result)
    
    if success then
        print("✓ " .. (description or "Cursor position correct"))
    else
        print("✗ " .. (description or "Cursor position wrong") .. 
              string.format(" - expected (%d,%d), got (%d,%d)", expected_row, expected_col, row, col))
    end
    
    return success
end

function M.assert_no_errors(description)
    local error_notifications = {}
    for _, notif in ipairs(notifications) do
        if notif.level == vim.log.levels.ERROR then
            table.insert(error_notifications, notif.message)
        end
    end
    
    local success = #error_notifications == 0
    local result = {
        test = description or "no errors",
        expected = "0 errors",
        actual = string.format("%d errors", #error_notifications),
        success = success,
        errors = error_notifications,
        time = vim.fn.reltime(test_state.start_time)
    }
    
    table.insert(test_state.results, result)
    
    if success then
        print("✓ " .. (description or "No errors"))
    else
        print("✗ " .. (description or "Errors detected") .. ": " .. table.concat(error_notifications, "; "))
    end
    
    return success
end

function M.simulate_typing(text, delay_ms)
    delay_ms = delay_ms or 10
    
    for i = 1, #text do
        local char = text:sub(i, i)
        vim.api.nvim_input(char)
        vim.wait(delay_ms)
    end
end

function M.get_search_query()
    -- Access internal state for testing
    local window = require('yas.window')
    if window._get_state then
        return window._get_state().search_query
    end
    return nil
end

function M.dump_state()
    local yas = require('yas')
    local window = require('yas.window')
    
    local state = {
        window_open = window.is_open(),
        notifications = notifications,
        test_results = test_state.results,
    }
    
    if window.is_open() then
        local winnr = vim.api.nvim_get_current_win()
        local row, col = unpack(vim.api.nvim_win_get_cursor(winnr))
        state.cursor = { row = row, col = col }
        local search_engine = require('yas.search_engine')
        state.search_query = search_engine.current_query()
    end
    
    return state
end

function M.finish_test()
    local elapsed = vim.fn.reltimestr(vim.fn.reltime(test_state.start_time))
    local passed = 0
    local failed = 0
    
    for _, result in ipairs(test_state.results) do
        if result.success then
            passed = passed + 1
        else
            failed = failed + 1
        end
    end
    
    print(string.format("Test '%s' completed in %ss: %d passed, %d failed", 
          test_state.current_test, elapsed, passed, failed))
    
    if failed > 0 then
        print("Failed assertions:")
        for _, result in ipairs(test_state.results) do
            if not result.success then
                print(string.format("  - %s: expected %s, got %s", 
                      result.test, result.expected, result.actual))
            end
        end
    end
    
    return failed == 0
end

-- Comprehensive test suite
function M.run_cursor_tests()
    M.start_test("cursor_positioning")
    
    -- Close any existing windows
    local yas = require('yas')
    if yas then
        yas.close()
    end
    vim.wait(50)
    
    -- Test 1: Opening window positions cursor correctly
    yas.open()
    vim.wait(100)
    
    M.assert_cursor_position(3, 4, "cursor position on open") -- "│ " is 4 bytes
    M.assert_no_errors("window opening")
    
    -- Test 2: Typing updates cursor position
    vim.api.nvim_input('i') -- Enter insert mode
    vim.wait(50)
    
    M.simulate_typing("test")
    vim.wait(100)
    
    M.assert_cursor_position(3, 8, "cursor position after typing 'test'") -- 4 + 4 chars = 8
    M.assert_no_errors("typing in insert mode")
    
    -- Test 3: Backspace updates cursor position
    vim.api.nvim_input('<BS><BS>')
    vim.wait(100)
    
    M.assert_cursor_position(3, 6, "cursor position after backspace") -- 4 + 2 chars = 6
    M.assert_no_errors("backspace handling")
    
    -- Test 4: Clear and retype
    vim.api.nvim_input('<C-c>') -- Clear search
    vim.wait(50)
    
    vim.api.nvim_input('i')
    M.simulate_typing("hello world")
    vim.wait(100)
    
    M.assert_cursor_position(3, 15, "cursor position with longer text") -- 4 + 11 chars = 15
    M.assert_no_errors("longer text input")
    
    yas.close()
    
    return M.finish_test()
end

-- Expose internal state for testing (only in test mode)
function M.expose_internals()
    local window = require('yas.window')
    
    -- Add getter for internal state
    window._get_state = function()
        return window._internal_state or {}
    end
end

return M
