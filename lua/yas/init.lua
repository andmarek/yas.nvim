local M = {}

local config = require('yas.config')
local window = require('yas.window')
--local search = require('yas.search')
local highlight = require('yas.highlight')

-- Open the finder
function M.open()
    if window.is_open() then
        window.focus()
        return
    end

    window.create_buffer()
end

-- Close the finder
function M.close()
    if not window.is_open() then
        return
    end

    window.close()
end

-- Toggle the finder
function M.toggle()
    if window.is_open() then
        M.close()
    else
        M.open()
    end
end

-- Focus the finder (open if closed)
function M.focus()
    if not window.is_open() then
        M.open()
    else
        window.focus()
    end
end

-- Focus input mode without opening/closing YAS
function M.insert()
    if window.is_open() then
        window.focus_input()
    else
        -- If YAS is closed, this function doesn't open it
        vim.notify("YAS finder is not open. Use :YasToggle to open it.", vim.log.levels.WARN)
    end
end

-- Directory navigation functions
function M.next_directory()
    if window.is_open() then
        window.jump_to_next_file()
    end
end

function M.prev_directory()
    if window.is_open() then
        window.jump_to_prev_file()
    end
end

-- Smart fold current directory
function M.fold_current()
    if window.is_open() then
        window.collapse_current_file()
    end
end

-- Setup function for user configuration
function M.setup(opts)
    config.setup(opts or {})
    highlight.setup_highlights()
end

return M
