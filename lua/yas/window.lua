local config = require('yas.config')

local M = {}

local state = {
    bufnr = nil,
    winnr = nil,
    search_query = '',
    search_mode = false, -- Whether we're in search input mode
    results = {},      -- Current search results
    cursor_line = 4,   -- Line where cursor should be positioned (search input line)
    search_timer = nil, -- Timer for debounced search
}

-- Create the sidebar window
function M.create()
    local opts = config.options

    -- Create buffer if it doesn't exist
    if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
        state.bufnr = vim.api.nvim_create_buf(false, true)

        -- Set buffer options
        vim.api.nvim_set_option_value('buftype', 'nofile', { buf = state.bufnr })
        vim.api.nvim_set_option_value('swapfile', false, { buf = state.bufnr })
        vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = state.bufnr })
        vim.api.nvim_set_option_value('filetype', 'yas-finder', { buf = state.bufnr })
        vim.api.nvim_buf_set_name(state.bufnr, 'YAS Finder')

        -- Set up insert mode autocmds for seamless search experience
        M.setup_search_autocmds(state.bufnr)

        M.setup_buffer_keymaps(state.bufnr)
    end

    -- Save current window to return focus later
    local current_win = vim.api.nvim_get_current_win()

    -- Create sidebar split
    if opts.position == 'left' then
        vim.cmd('topleft vsplit')
    else
        vim.cmd('botright vsplit')
    end

    -- Get the new window (should be current after split)
    state.winnr = vim.api.nvim_get_current_win()

    -- Set the buffer in the new window
    vim.api.nvim_win_set_buf(state.winnr, state.bufnr)

    -- Set window width
    vim.api.nvim_win_set_width(state.winnr, opts.width)

    -- Set window options for sidebar behavior
    vim.api.nvim_win_set_option(state.winnr, 'number', false)
    vim.api.nvim_win_set_option(state.winnr, 'relativenumber', false)
    vim.api.nvim_win_set_option(state.winnr, 'wrap', false)
    vim.api.nvim_win_set_option(state.winnr, 'cursorline', true)
    vim.api.nvim_win_set_option(state.winnr, 'winfixwidth', true)
    vim.api.nvim_win_set_option(state.winnr, 'signcolumn', 'no')
    vim.api.nvim_win_set_option(state.winnr, 'foldcolumn', '0')

    -- Start in search mode and focus the sidebar
    state.search_mode = true
    M.render_content()
    vim.api.nvim_set_current_win(state.winnr)
    
    -- Position cursor at end of search text and enter insert mode
    vim.schedule(function()
        if state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
            local cursor_col = #state.search_query + 2  -- Account for "│ " prefix
            vim.api.nvim_win_set_cursor(state.winnr, { 3, cursor_col })
            vim.cmd('startinsert')
        end
    end)
end

-- Close the window
function M.close()
    if state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
        -- Switch to the sidebar window before closing to avoid issues
        local current_win = vim.api.nvim_get_current_win()
        vim.api.nvim_set_current_win(state.winnr)
        vim.cmd('close')
        state.winnr = nil

        -- Return to previous window if it's still valid
        if current_win ~= state.winnr and vim.api.nvim_win_is_valid(current_win) then
            vim.api.nvim_set_current_win(current_win)
        end
    end
end

-- Focus the sidebar window
function M.focus()
    if state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
        vim.api.nvim_set_current_win(state.winnr)
    end
end

-- Check if sidebar is currently open
function M.is_open()
    return state.winnr and vim.api.nvim_win_is_valid(state.winnr)
end

-- Setup autocmds and insert mode keymaps for seamless search
function M.setup_search_autocmds(bufnr)
    -- Create autocmd group for this buffer
    local group = vim.api.nvim_create_augroup('yas-search-' .. bufnr, { clear = true })
    
    -- Handle leaving insert mode
    vim.api.nvim_create_autocmd('InsertLeave', {
        group = group,
        buffer = bufnr,
        callback = function()
            if state.search_mode then
                M.stop_search()
            end
        end,
    })
    
    -- Set up insert mode keymaps for text input
    M.setup_insert_mode_keymaps(bufnr)
end

-- Setup insert mode keymaps for seamless text input
function M.setup_insert_mode_keymaps(bufnr)
    -- All printable characters
    local chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-=[]{}|;:,.<>?`~'
    for i = 1, #chars do
        local char = chars:sub(i, i)
        vim.api.nvim_buf_set_keymap(bufnr, 'i', char, '', {
            callback = function()
                if state.search_mode then
                    state.search_query = state.search_query .. char
                    M.render_content()
                    M.perform_search_and_update()
                end
                return false -- Allow vim to handle the actual insertion
            end,
            noremap = true,
            silent = true
        })
    end

    -- Space
    vim.api.nvim_buf_set_keymap(bufnr, 'i', '<Space>', '', {
        callback = function()
            if state.search_mode then
                state.search_query = state.search_query .. ' '
                M.render_content()
                M.perform_search_and_update()
            end
            return false -- Allow vim to handle the actual insertion
        end,
        noremap = true,
        silent = true
    })

    -- Backspace
    vim.api.nvim_buf_set_keymap(bufnr, 'i', '<BS>', '', {
        callback = function()
            if state.search_mode and #state.search_query > 0 then
                state.search_query = state.search_query:sub(1, -2)
                M.render_content()
                M.perform_search_and_update()
            end
            return false -- Allow vim to handle the actual deletion
        end,
        noremap = true,
        silent = true
    })
end

-- Setup buffer keymaps
function M.setup_buffer_keymaps(bufnr)
    local opts = { noremap = true, silent = true, buffer = bufnr }
    local keymaps = config.options.keymaps

    -- 'q' always quits
    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'q', '', {
        callback = function()
            require('yas').close()
        end,
        noremap = true,
        silent = true
    })

    -- Select result or exit search mode
    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<CR>', '', {
        callback = function()
            if state.search_mode then
                M.stop_search()
            else
                M.select_result()
            end
        end,
        noremap = true,
        silent = true
    })

    -- Escape to exit search mode (primary way to exit)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Esc>', '', {
        callback = function()
            if state.search_mode then
                M.stop_search()
            end
        end,
        noremap = true,
        silent = true
    })

    -- Clear search entirely
    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<C-c>', '', {
        callback = function()
            M.clear_search()
        end,
        noremap = true,
        silent = true
    })

    -- Special handling for 'i' to enter insert mode properly
    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'i', '', {
        callback = function()
            M.start_search()
        end,
        noremap = true,
        silent = true
    })

    -- Start search mode with other printable characters (but not 'i' or 'q')
    local function setup_char_maps()
        -- All printable characters except 'i' and 'q'
        local chars = 'abcdefghjklmnoprstuvwxyzABCDEFGHJKLMNOPRSTUVWXYZ0123456789!@#$%^&*()_+-=[]{}|;:,.<>?`~'
        for i = 1, #chars do
            local char = chars:sub(i, i)
            vim.api.nvim_buf_set_keymap(bufnr, 'n', char, '', {
                callback = function()
                    if not state.search_mode then
                        M.start_search()
                    end
                    M.handle_char_input(char)
                end,
                noremap = true,
                silent = true
            })
        end

        -- Space
        vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Space>', '', {
            callback = function()
                if not state.search_mode then
                    M.start_search()
                end
                M.handle_char_input(' ')
            end,
            noremap = true,
            silent = true
        })

        -- Backspace
        vim.api.nvim_buf_set_keymap(bufnr, 'n', '<BS>', '', {
            callback = function()
                if state.search_mode then
                    M.handle_char_input('\b')
                end
            end,
            noremap = true,
            silent = true
        })
    end

    setup_char_maps()

    -- Navigation keys when not in search mode
    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'j', '', {
        callback = function()
            if not state.search_mode then
                vim.cmd('normal! j')
            end
        end,
        noremap = true,
        silent = true
    })

    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'k', '', {
        callback = function()
            if not state.search_mode then
                vim.cmd('normal! k')
            end
        end,
        noremap = true,
        silent = true
    })
end

-- Render initial content
function M.render_initial()
    if not state.bufnr then return end

    M.render_content()
end

-- Render the complete sidebar content
function M.render_content()
    if not state.bufnr then return end

    local lines = {}

    -- Header
    table.insert(lines, '┌─ YAS Finder ─────────────────────┐')
    table.insert(lines, '│ Search in files:                 │')

    -- Search input line - properly format to fit in box
    local search_display = state.search_query
    if search_display == '' then
        search_display = '(type to search...)'
    end

    -- Ensure the search display fits within 32 characters and pad properly
    local truncated = search_display:sub(1, 32)
    local padded = truncated .. string.rep(' ', math.max(0, 32 - #truncated))
    table.insert(lines, '│ ' .. padded .. ' │')
    table.insert(lines, '└──────────────────────────────────┘')
    table.insert(lines, '')

    -- Results or help
    if state.search_query == '' then
        table.insert(lines, 'Keybindings:')
        table.insert(lines, '  i     - Start search')
        table.insert(lines, '  <CR>  - Go to result')
        table.insert(lines, '  za    - Toggle file')
        table.insert(lines, '  dd    - Remove result')
        table.insert(lines, '  q     - Close finder')
        table.insert(lines, '')
        table.insert(lines, 'Start typing to search files...')
    else
        -- Show results
        if #state.results == 0 then
            table.insert(lines, string.format('No results for: %s', state.search_query))
        else
            table.insert(lines, string.format('Results for: %s', state.search_query))
            table.insert(lines, '')

            for _, file_result in ipairs(state.results) do
                local clean_filename = file_result.file:gsub('[\r\n]', '')
                table.insert(lines, string.format('📁 %s (%d matches)', clean_filename, #file_result.matches))

                for _, match in ipairs(file_result.matches) do
                    local preview = match.text:gsub('[\r\n]', ' '):gsub('^%s*', ''):gsub('%s*$', ''):sub(1, 45)
                    table.insert(lines, string.format('    %d: %s', match.line_number, preview))
                end
                table.insert(lines, '')
            end
        end
    end

    vim.api.nvim_set_option_value('modifiable', true, { buf = state.bufnr })
    vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
    vim.api.nvim_set_option_value('modifiable', false, { buf = state.bufnr })

    -- Position cursor on search line when in search mode (use vim.schedule to avoid timing issues)
    if state.search_mode and state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
        vim.schedule(function()
            if state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
                -- Position cursor at the end of the search query (after the text, accounting for "│ " prefix)
                local cursor_col = #state.search_query + 2 -- 2 for "│ " prefix
                vim.api.nvim_win_set_cursor(state.winnr, { 3, cursor_col })
            end
        end)
    end
end

-- Start search input mode
function M.start_search()
    state.search_mode = true
    M.render_content()

    -- Focus the sidebar window
    if state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
        vim.api.nvim_set_current_win(state.winnr)
        -- Position cursor and enter insert mode
        vim.schedule(function()
            if state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
                local cursor_col = #state.search_query + 2
                vim.api.nvim_win_set_cursor(state.winnr, { 3, cursor_col })
                vim.cmd('startinsert')
            end
        end)
    end
end

-- Stop search input mode
function M.stop_search()
    state.search_mode = false
    M.render_content()
end

-- Handle character input during search
function M.handle_char_input(char)
    if not state.search_mode then return end

    if char == '\b' or char == '\127' then -- Backspace
        if #state.search_query > 0 then
            state.search_query = state.search_query:sub(1, -2)
            -- Immediate UI update, then search
            M.render_content()
            M.perform_search_and_update()
        end
    elseif char:match('[%w%s%p]') then -- Printable characters
        state.search_query = state.search_query .. char
        -- Immediate UI update, then search
        M.render_content()
        M.perform_search_and_update()
    end
end

-- Perform search and update display (with debouncing)
function M.perform_search_and_update()
    -- Cancel previous timer if it exists
    if state.search_timer then
        if not state.search_timer:is_closing() then
            state.search_timer:stop()
            state.search_timer:close()
        end
        state.search_timer = nil
    end

    if state.search_query == '' then
        state.results = {}
        M.render_content()
        return
    end

    -- Debounce search by 100ms (much faster)
    state.search_timer = vim.loop.new_timer()
    state.search_timer:start(100, 0, vim.schedule_wrap(function()
        local ok, search = pcall(require, 'yas.search')
        if not ok then
            vim.notify('Error loading search module: ' .. search, vim.log.levels.ERROR)
            return
        end

        local search_ok, search_err = pcall(function()
            search.perform_search(state.search_query, function(results)
                if results then
                    state.results = results
                    M.render_content()
                else
                    vim.notify('Search returned no results', vim.log.levels.WARN)
                end
            end)
        end)

        if not search_ok then
            vim.notify('Search error: ' .. tostring(search_err), vim.log.levels.ERROR)
            state.results = {}
            M.render_content()
        end

        if state.search_timer and not state.search_timer:is_closing() then
            state.search_timer:close()
            state.search_timer = nil
        end
    end))
end

-- Clear search
function M.clear_search()
    state.search_query = ''
    state.results = {}
    state.search_mode = false
    M.render_content()
end

-- Select current result
function M.select_result()
    -- TODO: Implement navigation to selected result
    print('Select result - TODO: implement')
end

-- Toggle file expand/collapse
function M.toggle_file()
    -- TODO: Implement file toggle
    print('Toggle file - TODO: implement')
end

-- Remove result
function M.remove_result()
    -- TODO: Implement result removal
    print('Remove result - TODO: implement')
end

return M
