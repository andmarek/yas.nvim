local config = require('yas.config')

local M = {}

local state = {
    bufnr = nil,
    winnr = nil,
    prev_winnr = nil,
    search_query = '',
    search_mode = false, -- Whether we're in search input mode
    results = {},      -- Current search results
    search_timer = nil, -- Timer for debounced search
    line_index = {},    -- Map buffer line -> result entry {type, file_index, match_index}
    ns = nil,           -- Highlight namespace
    collapsed_files = {},
}

-- Helper functions for proper cursor positioning
local function char_count(s)
    return vim.fn.strchars(s or "")
end

local function bytes_of_chars(s, n_chars)
    -- returns byte index for n_chars codepoints (0 for 0 chars)
    return vim.str_byteindex(s or "", n_chars or 0)
end

local function truncated_display(query, max_chars)
    -- Truncate by characters, not bytes
    return vim.fn.strcharpart(query or "", 0, max_chars or 32)
end

local function compute_cursor_col()
    local prompt = "│ "
    local prompt_bytes = bytes_of_chars(prompt, char_count(prompt))  -- 4 bytes
    local display = truncated_display(state.search_query, 32)
    local display_bytes = bytes_of_chars(display, char_count(display))
    return prompt_bytes + display_bytes
end

-- Create the sidebar window
function M.create_buffer()
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

        -- Create highlight namespace
        state.ns = vim.api.nvim_create_namespace('yas-finder')

        -- Ensure selection highlight follows the cursor
        M.ensure_cursor_highlight_autocmd()
    end

    -- Save current window to return focus later
    local current_win = vim.api.nvim_get_current_win()
    state.prev_winnr = current_win

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
            local cursor_col = compute_cursor_col()
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
    local function commit_change(new_query)
        state.search_query = new_query
        -- Defer rendering to avoid "not allowed to change text" error during expr evaluation
        vim.schedule(function()
            M.render_content()
            M.perform_search_and_update()
        end)
    end

    -- Backspace
    vim.keymap.set('i', '<BS>', function()
        if not state.search_mode then return '<BS>' end
        local chars = char_count(state.search_query)
        if chars > 0 then
            -- remove last character by chars, not bytes
            local newq = vim.fn.strcharpart(state.search_query, 0, chars - 1)
            commit_change(newq)
        end
        return '' -- do not insert/delete in buffer
    end, { buffer = bufnr, expr = true, silent = true })

    -- Space
    vim.keymap.set('i', '<Space>', function()
        if not state.search_mode then return ' ' end
        commit_change(state.search_query .. ' ')
        return ''
    end, { buffer = bufnr, expr = true, silent = true })

    -- Printable ASCII range
    for c = 32, 126 do
        local key = string.char(c)
        if key ~= ' ' then -- Space handled above
            vim.keymap.set('i', key, function()
                if not state.search_mode then return key end
                commit_change(state.search_query .. key)
                return ''
            end, { buffer = bufnr, expr = true, silent = true })
        end
    end
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

    -- Toggle file expand/collapse
    vim.api.nvim_buf_set_keymap(bufnr, 'n', keymaps.toggle_file or 'za', '', {
        callback = function()
            if not state.search_mode then
                M.toggle_file()
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
    local idx_map = {}

    -- Header
    table.insert(lines, '┌─ YAS Finder ─────────────────────┐')
    table.insert(idx_map, { type = 'header' })
    table.insert(lines, '│ Search in files:                 │')
    table.insert(idx_map, { type = 'header' })

    -- Search input line - properly format to fit in box
    local search_display = state.search_query
    if search_display == '' then
        search_display = '(type to search...)'
    end

    -- Ensure the search display fits within 32 characters and pad properly
    local display = truncated_display(search_display, 32)
    local width = vim.fn.strwidth(display)
    local padded = display .. string.rep(' ', math.max(0, 32 - width))
    table.insert(lines, '│ ' .. padded .. ' │')
    table.insert(idx_map, { type = 'input' })
    table.insert(lines, '└──────────────────────────────────┘')
    table.insert(idx_map, { type = 'header' })
    table.insert(lines, '')
    table.insert(idx_map, { type = 'blank' })

    -- Results or help
    if state.search_query == '' then
        table.insert(lines, 'Keybindings:')
        table.insert(idx_map, { type = 'help' })
        table.insert(lines, '  i     - Start search')
        table.insert(idx_map, { type = 'help' })
        table.insert(lines, '  <CR>  - Go to result')
        table.insert(idx_map, { type = 'help' })
        table.insert(lines, '  za    - Toggle file')
        table.insert(idx_map, { type = 'help' })
        table.insert(lines, '  dd    - Remove result')
        table.insert(idx_map, { type = 'help' })
        table.insert(lines, '  q     - Close finder')
        table.insert(idx_map, { type = 'help' })
        table.insert(lines, '')
        table.insert(idx_map, { type = 'blank' })
        table.insert(lines, 'Start typing to search files...')
        table.insert(idx_map, { type = 'help' })
    else
        -- Show results
        if #state.results == 0 then
            table.insert(lines, string.format('No results for: %s', state.search_query))
            table.insert(idx_map, { type = 'empty' })
        else
            table.insert(lines, string.format('Results for: %s', state.search_query))
            table.insert(idx_map, { type = 'label' })
            table.insert(lines, '')
            table.insert(idx_map, { type = 'blank' })

            for file_index, file_result in ipairs(state.results) do
                local clean_filename = file_result.file:gsub('[\r\n]', '')
                local is_collapsed = state.collapsed_files[clean_filename] == true
                local icon = is_collapsed and '▸' or '▾'
                table.insert(lines, string.format('%s 📁 %s (%d matches)', icon, clean_filename, #file_result.matches))
                table.insert(idx_map, {
                    type = 'file',
                    file_index = file_index,
                    collapsed = is_collapsed,
                    file = clean_filename,
                })

                if not is_collapsed then
                    for match_index, match in ipairs(file_result.matches) do
                        local preview = match.text:gsub('[\r\n]', ' '):gsub('^%s*', ''):gsub('%s*$', ''):sub(1, 45)
                        table.insert(lines, string.format('    %d: %s', match.line_number, preview))
                        table.insert(idx_map, { type = 'match', file_index = file_index, match_index = match_index })
                    end
                    table.insert(lines, '')
                    table.insert(idx_map, { type = 'blank' })
                end
            end
        end
    end

    vim.api.nvim_set_option_value('modifiable', true, { buf = state.bufnr })
    vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
    vim.api.nvim_set_option_value('modifiable', false, { buf = state.bufnr })

    -- Save line index for navigation
    state.line_index = idx_map

    -- Refresh selection highlight after render
    M.update_selection_highlight()

    -- Position cursor on search line when in search mode (use vim.schedule to avoid timing issues)
    if state.search_mode and state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
        vim.schedule(function()
            if state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
                -- Position cursor at the end of the search query
                local cursor_col = compute_cursor_col()
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
                local cursor_col = compute_cursor_col()
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
    if not state.winnr or not vim.api.nvim_win_is_valid(state.winnr) then
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(state.winnr)
    local line = cursor[1]
    local entry = state.line_index[line]
    if not entry then return end

    local function open_location(filepath, lnum, col)
        local fname = vim.fn.fnamemodify(filepath, ':p')

        -- Choose a target window (prefer previous window)
        local target_win = state.prev_winnr
        if not target_win or not vim.api.nvim_win_is_valid(target_win) or target_win == state.winnr then
            -- Try go to previous window; if still the sidebar, create a split
            vim.cmd('wincmd p')
            target_win = vim.api.nvim_get_current_win()
            if target_win == state.winnr then
                vim.cmd('vsplit')
                target_win = vim.api.nvim_get_current_win()
            end
        else
            vim.api.nvim_set_current_win(target_win)
        end

        vim.cmd('edit ' .. vim.fn.fnameescape(fname))
        pcall(vim.api.nvim_win_set_cursor, target_win, { lnum, math.max(0, col or 0) })
        vim.cmd('normal! zvzz')
    end

    if entry.type == 'match' then
        local file_result = state.results[entry.file_index]
        if not file_result then return end
        local match = file_result.matches[entry.match_index]
        if not match then return end
        open_location(file_result.file, match.line_number, match.column)
    elseif entry.type == 'file' then
        local file_result = state.results[entry.file_index]
        if not file_result then return end
        local first = file_result.matches[1]
        local line_number = first and first.line_number or 1
        local col = first and first.column or 0
        open_location(file_result.file, line_number, col)
    end
end

-- Update selection highlight (current cursor line if it's a file or match)
function M.update_selection_highlight()
    if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then return end
    if not state.ns then state.ns = vim.api.nvim_create_namespace('yas-finder') end

    vim.api.nvim_buf_clear_namespace(state.bufnr, state.ns, 0, -1)

    if not state.winnr or not vim.api.nvim_win_is_valid(state.winnr) then return end

    local cursor = vim.api.nvim_win_get_cursor(state.winnr)
    local line = cursor[1]
    local entry = state.line_index[line]
    if not entry then return end

    if entry.type == 'match' or entry.type == 'file' then
        local hl = config.options.highlights.selection or 'Visual'
        -- Highlight the entire line
        vim.api.nvim_buf_add_highlight(state.bufnr, state.ns, hl, line - 1, 0, -1)
    end
end

-- Autocmd to refresh selection highlight on CursorMoved within the window
do
    local group
    function M.ensure_cursor_highlight_autocmd()
        if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then return end
        if group then return end
        group = vim.api.nvim_create_augroup('yas-finder-cursor-' .. state.bufnr, { clear = true })
        vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'WinEnter', 'BufEnter' }, {
            group = group,
            buffer = state.bufnr,
            callback = function()
                M.update_selection_highlight()
            end,
        })
    end
end

-- Toggle file expand/collapse
function M.toggle_file()
    if not state.winnr or not vim.api.nvim_win_is_valid(state.winnr) then
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(state.winnr)
    local line = cursor[1]
    local entry = state.line_index[line]
    if not entry or entry.type ~= 'file' then
        return
    end

    local record = state.results[entry.file_index]
    if not record then
        return
    end

    local clean_filename = record.file
    if not clean_filename then
        return
    end

    state.collapsed_files[clean_filename] = not entry.collapsed

    M.render_content()
end

-- Remove result
function M.remove_result()
    -- TODO: Implement result removal
    print('Remove result - TODO: implement')
end

-- Expose internal state for testing (development only)
if vim.g.yas_debug then
    M._get_state = function() return state end
    M._compute_cursor_col = compute_cursor_col
end

return M
