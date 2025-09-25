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

-- Setup function for user configuration
function M.setup(opts)
    config.setup(opts or {})
    highlight.setup_highlights()
end

return M
