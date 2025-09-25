local config = require('yas.config')
local highlight = require('yas.highlight')
local render = require('yas.render')
local search_engine = require('yas.search_engine')

local M = {}

local state = {
    bufnr = nil,
    winnr = nil,
    prev_winnr = nil,
    search_mode = false, -- Whether we're in search input mode
    results = {},        -- Current search results
    line_index = {},     -- Map buffer line -> result entry {type, file_index, match_index}
    ns = nil,            -- Highlight namespace for selection
    ns_ui = nil,         -- Highlight namespace for UI accents
    collapsed_files = {},
    resize_group = nil,
    last_sidebar_width = nil,
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

local function safe_byteindex(text, char_index)
    local ok, result = pcall(vim.str_byteindex, text or '', char_index or 0)
    if ok and result then
        return result
    end
    return (text and #text) or 0
end

local function compute_cursor_col()
    local prompt = "> "
    local prompt_chars = char_count(prompt)
    local prompt_bytes = bytes_of_chars(prompt, prompt_chars)
    local sidebar_width = M.get_sidebar_width()
    local max_chars = math.max(0, sidebar_width - 4)
    local current_query = search_engine.current_query()
    local display = truncated_display(current_query, max_chars)
    local display_bytes = bytes_of_chars(display, char_count(display))
    return prompt_bytes + display_bytes
end



-- Returns the width of the sidebar in characters (display columns)
function M.get_sidebar_width()
    if state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
        local ok, win_width = pcall(vim.api.nvim_win_get_width, state.winnr)
        if ok and type(win_width) == 'number' then
            return math.max(win_width, 1)
        end
    end
    return config.options.width or 40
end

-- Trims the match preview to fit within the sidebar width
-- This supports resizing the sidebar width so that it's actually nice
function M.trim_match_preview(text, sidebar_width, prefix, column, length)
    prefix = prefix or ''
    sidebar_width = sidebar_width or M.get_sidebar_width()
    local available_width = math.max(5, sidebar_width - vim.fn.strwidth(prefix) - 4)
    local total_chars = vim.fn.strchars(text)

    local match_start = math.max(0, math.min(column or 0, total_chars))
    local match_length = math.max(1, length or 1)
    local match_end = math.min(total_chars, match_start + match_length)
    local actual_match_length = match_end - match_start

    if vim.fn.strwidth(text) <= available_width then
        return text, match_start, actual_match_length
    end

    local slice_start = math.max(0, match_start - math.floor(available_width * 0.25))
    local slice_end = math.min(total_chars, slice_start + available_width)

    -- ensure the match fits inside the slice
    if match_end > slice_end then
        slice_end = match_end
        slice_start = math.max(0, slice_end - available_width)
    end
    if match_start < slice_start then
        slice_start = match_start
        slice_end = math.min(total_chars, slice_start + available_width)
    end

    local slice_len = slice_end - slice_start
    local snippet = vim.fn.strcharpart(text, slice_start, slice_len)

    local highlight_start = match_start - slice_start
    local highlight_len = actual_match_length

    local needs_left = slice_start > 0
    local needs_right = slice_end < total_chars

    if needs_left then
        snippet = '…' .. snippet:sub(2) -- Remove first char and add ellipsis
        if highlight_start > 0 then
            highlight_start = highlight_start
        else
            -- Match starts in the removed part
            highlight_len = highlight_len - 1 + highlight_start
            highlight_start = 1
        end
    end

    if needs_right and vim.fn.strchars(snippet) > 0 then
        local snippet_chars = vim.fn.strchars(snippet)
        snippet = vim.fn.strcharpart(snippet, 0, snippet_chars - 1) .. '…'
        -- Adjust highlight if it extends past the truncation
        if highlight_start + highlight_len > snippet_chars then
            highlight_len = math.max(0, snippet_chars - highlight_start)
        end
    end

    -- Final bounds checking
    local final_snippet_chars = vim.fn.strchars(snippet)
    highlight_start = math.max(0, math.min(highlight_start, final_snippet_chars - 1))
    highlight_len = math.max(1, math.min(highlight_len, final_snippet_chars - highlight_start))

    return snippet, highlight_start, highlight_len
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
        state.ns = vim.api.nvim_create_namespace('yas-finder-selection')
        state.ns_ui = vim.api.nvim_create_namespace('yas-finder-ui')

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

    M.ensure_resize_autocmd()
    state.last_sidebar_width = M.get_sidebar_width()

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
        -- Stop any running searches
        search_engine.stop()

        -- Clear all highlights before closing
        highlight.clear_all_highlights()

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
        -- Defer rendering to avoid "not allowed to change text" error during expr evaluation
        vim.schedule(function()
            M.render_content()
            M.perform_search_and_update(new_query)
        end)
    end

    -- Backspace
    vim.keymap.set('i', '<BS>', function()
        if not state.search_mode then return '<BS>' end
        local current_query = search_engine.current_query()
        local chars = char_count(current_query)
        if chars > 0 then
            -- remove last character by chars, not bytes
            local newq = vim.fn.strcharpart(current_query, 0, chars - 1)
            commit_change(newq)
        end
        return '' -- do not insert/delete in buffer
    end, { buffer = bufnr, expr = true, silent = true })

    -- Space
    vim.keymap.set('i', '<Space>', function()
        if not state.search_mode then return ' ' end
        local current_query = search_engine.current_query()
        commit_change(current_query .. ' ')
        return ''
    end, { buffer = bufnr, expr = true, silent = true })

    -- Printable ASCII range
    for c = 32, 126 do
        local key = string.char(c)
        if key ~= ' ' then -- Space handled above
            vim.keymap.set('i', key, function()
                if not state.search_mode then return key end
                local current_query = search_engine.current_query()
                commit_change(current_query .. key)
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
-- Render the complete sidebar content
function M.render_content()
    if not state.bufnr then return end

    local sidebar_width = M.get_sidebar_width()

    -- If the last sidebar width is different than the current width,
    -- then update the state's last sidebar width
    if state.last_sidebar_width ~= sidebar_width then
        state.last_sidebar_width = sidebar_width
    end

    local lines, idx_map = render.render_content(state, sidebar_width, M.trim_match_preview)

    vim.api.nvim_set_option_value('modifiable', true, { buf = state.bufnr })
    vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
    vim.api.nvim_set_option_value('modifiable', false, { buf = state.bufnr })

    -- Save line index for navigation
    state.line_index = idx_map

    -- Refresh selection highlight after render
    M.update_selection_highlight()
    M.apply_result_highlights()

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

    local current_query = search_engine.current_query()

    if char == '\b' or char == '\127' then -- Backspace
        if #current_query > 0 then
            local new_query = current_query:sub(1, -2)
            -- Immediate UI update, then search
            M.render_content()
            M.perform_search_and_update(new_query)
        end
    elseif char:match('[%w%s%p]') then -- Printable characters
        local new_query = current_query .. char
        -- Immediate UI update, then search
        M.render_content()
        M.perform_search_and_update(new_query)
    end
end

-- Perform search and update display (with debouncing)
function M.perform_search_and_update(query)
    search_engine.request(query or '', function(results)
        state.results = results or {}
        M.render_content()
        -- Highlight search results in open buffers
        highlight.highlight_search_results(state.results, query or '')
    end)
end

-- Clear search
function M.clear_search()
    search_engine.stop()
    state.results = {}
    state.search_mode = false
    M.perform_search_and_update('') -- This will clear the search_engine's state too
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

    local function open_location(filepath, lnum, col, length)
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

        -- Highlight the focused match using our highlight module
        if length then
            local bufnr = vim.fn.bufnr('%')
            highlight.highlight_focus(bufnr, lnum, col, length)
        end
    end

    if entry.type == 'match' then
        local file_result = state.results[entry.file_index]
        if not file_result then return end
        local match = file_result.matches[entry.match_index]
        if not match then return end
        open_location(file_result.file, match.line_number, match.column, match.length)
    elseif entry.type == 'file' then
        local file_result = state.results[entry.file_index]
        if not file_result then return end
        local first = file_result.matches[1]
        local line_number = first and first.line_number or 1
        local col = first and first.column or 0
        local length = first and first.length or 1
        open_location(file_result.file, line_number, col, length)
    end
end

-- Update selection highlight (current cursor line if it's a file or match)
function M.update_selection_highlight()
    if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then return end
    if not state.ns then state.ns = vim.api.nvim_create_namespace('yas-finder-selection') end
    if not state.ns_ui then state.ns_ui = vim.api.nvim_create_namespace('yas-finder-ui') end

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

function M.apply_result_highlights()
    if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then return end
    if not state.ns_ui then state.ns_ui = vim.api.nvim_create_namespace('yas-finder-ui') end

    vim.api.nvim_buf_clear_namespace(state.bufnr, state.ns_ui, 0, -1)

    local lines = vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false)
    for idx, meta in ipairs(state.line_index) do
        if meta.type == 'header' and idx == 1 then
            vim.api.nvim_buf_add_highlight(state.bufnr, state.ns_ui, config.options.highlights.title or 'Title', idx - 1,
                0, -1)
        elseif meta.type == 'header' and idx == 2 then
            vim.api.nvim_buf_add_highlight(state.bufnr, state.ns_ui, config.options.highlights.subtitle or 'Comment',
                idx - 1, 0, -1)
        elseif meta.type == 'divider' then
            vim.api.nvim_buf_add_highlight(state.bufnr, state.ns_ui, config.options.highlights.divider or 'LineNr',
                idx - 1, 0, -1)
        elseif meta.type == 'input' then
            vim.api.nvim_buf_add_highlight(state.bufnr, state.ns_ui, config.options.highlights.prompt or 'Identifier',
                idx - 1, 0, 2)
            local line = lines[idx] or ''
            local prompt_width = 2
            vim.api.nvim_buf_add_highlight(state.bufnr, state.ns_ui, config.options.highlights.input or 'Normal', idx - 1,
                prompt_width, -1)
        elseif meta.type == 'label' then
            vim.api.nvim_buf_add_highlight(state.bufnr, state.ns_ui, config.options.highlights.section or 'Include',
                idx - 1, 0, -1)
        elseif meta.type == 'file' then
            local line = lines[idx] or ''
            local icon_end = vim.fn.byteidx(line, char_count('▾ '))
            if icon_end > 0 then
                vim.api.nvim_buf_add_highlight(state.bufnr, state.ns_ui,
                    config.options.highlights.folder_icon or 'Special', idx - 1, 0, icon_end)
            end
            local open_paren = line:find('%(')
            if open_paren then
                vim.api.nvim_buf_add_highlight(state.bufnr, state.ns_ui,
                    config.options.highlights.file_name or 'Directory', idx - 1, icon_end, open_paren - 1)
                vim.api.nvim_buf_add_highlight(state.bufnr, state.ns_ui,
                    config.options.highlights.match_count or 'Number', idx - 1, open_paren - 1, -1)
            end
        elseif meta.type == 'match' then
            local line = lines[idx] or ''
            local prefix_chars = vim.fn.strchars(meta.prefix or '')
            local prefix_end = prefix_chars > 0 and safe_byteindex(line, prefix_chars) or 0
            if prefix_end > 0 then
                vim.api.nvim_buf_add_highlight(state.bufnr, state.ns_ui,
                    config.options.highlights.line_number or 'LineNr', idx - 1, 0, prefix_end)
            end

            local highlight_start = math.max(0, math.floor(meta.highlight_start or 0))
            local highlight_length = math.max(1, math.floor(meta.highlight_length or 1))

            local start_char = prefix_chars + highlight_start
            local end_char = start_char + highlight_length

            local start_byte = safe_byteindex(line, start_char)
            local end_byte = safe_byteindex(line, end_char)
            if end_byte <= start_byte then
                end_byte = safe_byteindex(line, start_char + highlight_length)
            end
            if end_byte <= start_byte then
                end_byte = math.min(#line, start_byte + highlight_length)
            end

            vim.api.nvim_buf_add_highlight(state.bufnr, state.ns_ui, config.options.highlights.match or 'Search', idx - 1,
                start_byte, end_byte)
        elseif meta.type == 'help' then
            vim.api.nvim_buf_add_highlight(state.bufnr, state.ns_ui, config.options.highlights.help_text or 'Comment',
                idx - 1, 0, -1)
        end
    end
end

function M.ensure_resize_autocmd()
    if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then return end
    if state.resize_group then return end

    local group_name = 'yas-resize-' .. state.bufnr
    state.resize_group = vim.api.nvim_create_augroup(group_name, { clear = true })

    vim.api.nvim_create_autocmd('VimResized', {
        group = state.resize_group,
        callback = function()
            if not state.winnr or not vim.api.nvim_win_is_valid(state.winnr) then
                return
            end
            local new_width = M.get_sidebar_width()
            if state.last_sidebar_width ~= new_width then
                state.last_sidebar_width = new_width
                vim.schedule(M.render_content)
            end
        end,
    })

    -- window-local resize (e.g., dragging vsplit)
    vim.api.nvim_create_autocmd('WinResized', {
        group = state.resize_group,
        callback = function(args)
            if not state.winnr or not vim.api.nvim_win_is_valid(state.winnr) then
                return
            end

            local matches = args and args.match
            if matches then
                local windows = {}
                for winid in string.gmatch(matches, '%d+') do
                    windows[tonumber(winid)] = true
                end
                if not windows[state.winnr] then
                    return
                end
            end

            local new_width = M.get_sidebar_width()
            if state.last_sidebar_width ~= new_width then
                state.last_sidebar_width = new_width
                vim.schedule(M.render_content)
            end
        end,
    })
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
