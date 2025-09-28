local config = require('yas.config')
local highlight = require('yas.highlight')
local render = require('yas.render')
local search_engine = require('yas.search_engine')

local M = {}

local state = {
    bufnr = nil,
    winnr = nil,
    input_bufnr = nil,   -- Floating input window buffer
    input_winnr = nil,   -- Floating input window
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

-- Create or update the floating input window
function M._create_input_window()
    if not state.winnr or not vim.api.nvim_win_is_valid(state.winnr) then
        return
    end

    local sidebar_width = M.get_sidebar_width()
    local input_width = math.max(1, sidebar_width - 2) -- Account for border

    -- Create input buffer if needed
    if not state.input_bufnr or not vim.api.nvim_buf_is_valid(state.input_bufnr) then
        state.input_bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_option_value('buftype', 'nofile', { buf = state.input_bufnr })
        vim.api.nvim_set_option_value('swapfile', false, { buf = state.input_bufnr })
        vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = state.input_bufnr })
        vim.api.nvim_set_option_value('buflisted', false, { buf = state.input_bufnr })
        vim.api.nvim_set_option_value('filetype', 'yas-input', { buf = state.input_bufnr })
        vim.api.nvim_buf_set_name(state.input_bufnr, 'YAS Input')

        -- Set up input keymaps and autocmds
        M.setup_input_keymaps(state.input_bufnr)
        M.attach_input_autocmds(state.input_bufnr)
    end

    -- Close existing input window if it exists
    if state.input_winnr and vim.api.nvim_win_is_valid(state.input_winnr) then
        vim.api.nvim_win_close(state.input_winnr, true)
    end

    -- Create floating input window
    local win_config = {
        relative = 'win',
        win = state.winnr,
        row = 2,  -- Position it on the empty line (line 3, 0-indexed)
        col = 0,
        width = input_width,
        height = 1,
        style = 'minimal',
        border = 'rounded',
        focusable = true,
        zindex = 10,  -- Lower z-index to avoid overlapping other plugins
        title = ' Search ',
        title_pos = 'left'
    }

    state.input_winnr = vim.api.nvim_open_win(state.input_bufnr, true, win_config) -- true = enter window

    -- Set window options
    vim.api.nvim_win_set_option(state.input_winnr, 'winblend', 10)
    vim.api.nvim_win_set_option(state.input_winnr, 'wrap', false)
    vim.api.nvim_win_set_option(state.input_winnr, 'cursorline', false)
    vim.api.nvim_win_set_option(state.input_winnr, 'signcolumn', 'no')

    -- Set initial content with current query (buffer is now always modifiable)
    local current_query = search_engine.current_query()
    vim.api.nvim_set_option_value('modifiable', true, { buf = state.input_bufnr })
    vim.api.nvim_buf_set_lines(state.input_bufnr, 0, -1, false, { current_query })
    -- Keep buffer modifiable for real Vim editing
    
    -- Update placeholder
    M.update_placeholder(current_query, false)
    
    -- Position cursor at end and enter insert mode
    vim.schedule(function()
        if state.input_winnr and vim.api.nvim_win_is_valid(state.input_winnr) then
            vim.api.nvim_win_set_cursor(state.input_winnr, { 1, vim.fn.strchars(current_query) })
            vim.cmd('startinsert!')
        end
    end)
end

-- Resize the floating input window to match sidebar width
function M._resize_input_window()
    if not state.input_winnr or not vim.api.nvim_win_is_valid(state.input_winnr) then
        -- If window doesn't exist but we're in search mode, create it
        if state.search_mode then
            M._create_input_window()
        end
        return
    end

    local sidebar_width = M.get_sidebar_width()
    local input_width = math.max(1, sidebar_width - 2) -- Account for border
    
    -- Update window configuration
    local win_config = {
        relative = 'win',
        win = state.winnr,
        row = 2,
        col = 0,
        width = input_width,
        height = 1,
        style = 'minimal',
        border = 'rounded',
        focusable = true,
        zindex = 10,  -- Lower z-index to avoid overlapping other plugins
        title = ' Search ',
        title_pos = 'left'
    }
    
    vim.api.nvim_win_set_config(state.input_winnr, win_config)
end

-- Temporarily hide input window (to prevent overlap with other plugins)
function M.hide_input_window_temporarily()
    if state.input_winnr and vim.api.nvim_win_is_valid(state.input_winnr) then
        -- Don't actually close the window, just hide it with zindex manipulation
        -- or move it off-screen temporarily
        local current_config = vim.api.nvim_win_get_config(state.input_winnr)
        current_config.zindex = 1  -- Very low z-index
        vim.api.nvim_win_set_config(state.input_winnr, current_config)
    end
end

-- Show input window (restore from temporary hiding)
function M.show_input_window()
    if state.input_winnr and vim.api.nvim_win_is_valid(state.input_winnr) then
        local current_config = vim.api.nvim_win_get_config(state.input_winnr)
        current_config.zindex = 10  -- Restore normal z-index
        vim.api.nvim_win_set_config(state.input_winnr, current_config)
    end
end

-- Setup minimal keymaps for the floating input window (Vim editing is now native)
function M.setup_input_keymaps(bufnr)
    local opts = { noremap = true, silent = true, buffer = bufnr }
    local keymaps = config.options.keymaps

    -- Close YAS
    vim.keymap.set({ 'n', 'i' }, '<Esc>', function()
        require('yas').close()
    end, opts)

    -- Switch to results pane (don't open file)
    vim.keymap.set({ 'n', 'i' }, keymaps.focus_results or '<CR>', function()
        M.focus_results()
    end, opts)

    -- Alternative close binding
    if keymaps.close then
        local close_key = keymaps.close
        if close_key:match('<leader>') then
            close_key = close_key:gsub('<leader>', vim.g.mapleader or '\\')
        end
        vim.keymap.set({ 'n', 'i' }, close_key, function()
            require('yas').close()
        end, opts)
    end

    -- Scroll results while staying in input
    vim.keymap.set('n', '<C-j>', function()
        if state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
            vim.api.nvim_win_call(state.winnr, function() 
                vim.cmd('normal! 5j') 
                M.update_selection_highlight()
            end)
        end
    end, opts)

    vim.keymap.set('n', '<C-k>', function()
        if state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
            vim.api.nvim_win_call(state.winnr, function() 
                vim.cmd('normal! 5k') 
                M.update_selection_highlight()
            end)
        end
    end, opts)
end

-- Open the currently selected result (used from input window)
function M.open_selected_result()
    if not state.winnr or not vim.api.nvim_win_is_valid(state.winnr) then
        return
    end
    
    -- Get the current cursor position in the results window
    local cursor = vim.api.nvim_win_get_cursor(state.winnr)
    local line = cursor[1]
    local entry = state.line_index[line]
    
    if entry and (entry.type == 'match' or entry.type == 'file') then
        M.select_result()
    else
        -- If no specific result is selected, try to find the first match
        for lnum, idx_entry in pairs(state.line_index) do
            if idx_entry.type == 'match' then
                -- Position cursor on first match and select it
                vim.api.nvim_win_set_cursor(state.winnr, { lnum, 0 })
                M.select_result()
                break
            end
        end
    end
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

-- Attach buffer change autocmds to enable real Vim editing
function M.attach_input_autocmds(bufnr)
    local group = vim.api.nvim_create_augroup('yas-input-changes', { clear = true })
    
    -- React to buffer content changes
    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
        group = group,
        buffer = bufnr,
        callback = function()
            local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ''
            -- Debug: uncomment next line to see when autocmds fire
            -- print("TextChanged fired with content:", line)
            M.perform_search_and_update(line)
            M.update_placeholder(line)
        end,
    })
    
    -- Hide floating window when focus moves to non-YAS windows (prevents overlap)
    local hide_group = vim.api.nvim_create_augroup('yas-window-focus', { clear = true })
    vim.api.nvim_create_autocmd('WinEnter', {
        group = hide_group,
        callback = function()
            local current_win = vim.api.nvim_get_current_win()
            local current_buf = vim.api.nvim_win_get_buf(current_win)
            local filetype = vim.api.nvim_get_option_value('filetype', { buf = current_buf })
            
            -- Hide if we're not in a YAS window
            if not (filetype == 'yas-input' or filetype == 'yas-finder') then
                M.hide_input_window_temporarily()
            else
                M.show_input_window()
            end
        end,
    })
    
    -- Ensure single line (flatten multiple lines to single line)
    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
        group = group,
        buffer = bufnr,
        callback = function()
            local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            if #lines > 1 then
                local txt = table.concat(lines, ' ')
                vim.schedule(function()
                    if vim.api.nvim_buf_is_valid(bufnr) then
                        vim.api.nvim_set_option_value('modifiable', true, { buf = bufnr })
                        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { txt })
                        vim.api.nvim_set_option_value('modifiable', false, { buf = bufnr })
                    end
                end)
            end
        end,
    })
    
    -- Update placeholder on insert enter/leave
    vim.api.nvim_create_autocmd('InsertEnter', {
        group = group,
        buffer = bufnr,
        callback = function()
            local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ''
            M.update_placeholder(line, true) -- true = in insert mode
        end,
    })
    
    vim.api.nvim_create_autocmd('InsertLeave', {
        group = group,
        buffer = bufnr,
        callback = function()
            local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ''
            M.update_placeholder(line, false) -- false = not in insert mode
        end,
    })
end

-- Update placeholder and search icon based on current query
function M.update_placeholder(query, in_insert_mode)
    if not state.input_bufnr or not vim.api.nvim_buf_is_valid(state.input_bufnr) then
        return
    end

    local ns_input = vim.api.nvim_create_namespace('yas-input-ui')
    vim.api.nvim_buf_clear_namespace(state.input_bufnr, ns_input, 0, -1)
    
    if query == '' and not in_insert_mode then
        -- Show placeholder only when not in insert mode and empty
        vim.api.nvim_buf_set_extmark(state.input_bufnr, ns_input, 0, 0, {
            virt_text = { { '󰱼 Search files...', 'Comment' } },
            virt_text_pos = 'overlay',
            hl_mode = 'combine'
        })
    elseif query ~= '' then
        -- Show search icon when there's content
        vim.api.nvim_buf_set_extmark(state.input_bufnr, ns_input, 0, 0, {
            virt_text = { { '󰱼 ', 'Identifier' } },
            virt_text_pos = 'inline',
        })
    end
end

-- Update the content of the floating input window (legacy function, kept for compatibility)
function M.update_input_content(query)
    if not state.input_bufnr or not vim.api.nvim_buf_is_valid(state.input_bufnr) then
        return
    end

    vim.api.nvim_set_option_value('modifiable', true, { buf = state.input_bufnr })
    vim.api.nvim_buf_set_lines(state.input_bufnr, 0, -1, false, { query })
    vim.api.nvim_set_option_value('modifiable', false, { buf = state.input_bufnr })

    M.update_placeholder(query)

    -- Position cursor at end if window is focused
    if state.input_winnr and vim.api.nvim_win_is_valid(state.input_winnr) then
        if vim.api.nvim_get_current_win() == state.input_winnr then
            vim.api.nvim_win_set_cursor(state.input_winnr, { 1, vim.fn.strchars(query) })
        end
    end
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

    -- Start in search mode and render content
    state.search_mode = true
    M.render_content()
    
    -- Create floating input window
    M._create_input_window()
    
    -- Focus the input window and enter insert mode
    vim.schedule(function()
        if state.input_winnr and vim.api.nvim_win_is_valid(state.input_winnr) then
            vim.api.nvim_set_current_win(state.input_winnr)
            local current_query = search_engine.current_query()
            vim.api.nvim_win_set_cursor(state.input_winnr, { 1, vim.fn.strchars(current_query) })
            vim.cmd('startinsert')
        end
    end)
end

-- Close the window
function M.close()
    -- Close floating input window first
    if state.input_winnr and vim.api.nvim_win_is_valid(state.input_winnr) then
        vim.api.nvim_win_close(state.input_winnr, true)
        state.input_winnr = nil
    end

    if state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
        -- Stop any running searches
        search_engine.stop()

        -- Clear all highlights before closing
        highlight.clear_all_highlights()

        -- Clear any autocmd groups associated with this sidebar
        M.clear_sidebar_autocmds()

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
    -- Backspace
    vim.keymap.set('i', '<BS>', function()
        if not state.search_mode then return '<BS>' end
        M.handle_char_input('\b')
        return '' -- do not insert/delete in buffer
    end, { buffer = bufnr, expr = true, silent = true })

    -- Space
    vim.keymap.set('i', '<Space>', function()
        if not state.search_mode then return ' ' end
        M.handle_char_input(' ')
        return ''
    end, { buffer = bufnr, expr = true, silent = true })

    -- Printable ASCII range
    for c = 32, 126 do
        local key = string.char(c)
        if key ~= ' ' then -- Space handled above
            vim.keymap.set('i', key, function()
                if not state.search_mode then return key end
                M.handle_char_input(key)
                return ''
            end, { buffer = bufnr, expr = true, silent = true })
        end
    end
end

-- Setup enhanced buffer keymaps for results window
function M.setup_buffer_keymaps(bufnr)
    local opts = { noremap = true, silent = true, buffer = bufnr }
    local keymaps = config.options.keymaps

    -- Core actions
    vim.keymap.set('n', keymaps.select or '<CR>', function()
        M.select_result()
    end, opts)

    -- Close with configurable key (resolve <leader> if needed)
    local close_key = keymaps.close or '<leader>q'
    if close_key:match('<leader>') then
        close_key = close_key:gsub('<leader>', vim.g.mapleader or '\\')
    end
    vim.keymap.set('n', close_key, function()
        require('yas').close()
    end, opts)

    -- Enhanced result opening modes
    vim.keymap.set('n', 'o', function()
        M.select_result('split')
    end, opts)

    vim.keymap.set('n', 'v', function()
        M.select_result('vsplit')  
    end, opts)

    vim.keymap.set('n', 't', function()
        M.select_result('tab')
    end, opts)

    -- Directory navigation (configurable)
    vim.keymap.set('n', keymaps.directory_next or '<C-n>', function()
        M.jump_to_next_file()
    end, opts)

    vim.keymap.set('n', keymaps.directory_prev or '<C-p>', function()
        M.jump_to_prev_file()
    end, opts)

    -- Smart fold toggle (configurable)
    vim.keymap.set('n', keymaps.fold_current or 'h', function()
        M.toggle_current_file()
    end, opts)

    -- Expand (opposite of fold)
    vim.keymap.set('n', 'l', function()
        M.expand_current_file()
    end, opts)

    -- Legacy za binding for fold users
    vim.keymap.set('n', keymaps.toggle_file or 'za', function()
        M.toggle_file()
    end, opts)

    -- Return to search input (configurable)
    vim.keymap.set('n', keymaps.back_to_insert or 'i', function()
        M.focus_input()
    end, opts)

    -- Clear search
    vim.keymap.set('n', keymaps.clear_search or '<C-c>', function()
        M.clear_search()
    end, opts)

    -- Legacy close binding (fallback)
    vim.keymap.set('n', 'q', function()
        require('yas').close()
    end, opts)
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


end

-- Start search input mode
function M.start_search()
    state.search_mode = true
    M.render_content()
    
    -- Create or update the floating input window
    M._create_input_window()

    -- Focus the input window and enter insert mode
    if state.input_winnr and vim.api.nvim_win_is_valid(state.input_winnr) then
        vim.api.nvim_set_current_win(state.input_winnr)
        vim.schedule(function()
            if state.input_winnr and vim.api.nvim_win_is_valid(state.input_winnr) then
                local current_query = search_engine.current_query()
                vim.api.nvim_win_set_cursor(state.input_winnr, { 1, vim.fn.strchars(current_query) })
                vim.cmd('startinsert')
            end
        end)
    end
end

-- Stop search input mode (but keep query visible)
function M.stop_search()
    state.search_mode = false
    
    -- Keep the floating input window visible but unfocused
    -- (Don't close it - user wants to see the query)
    
    -- Focus back to results window
    if state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
        vim.api.nvim_set_current_win(state.winnr)
    end
    
    M.render_content()
end

-- Handle character input during search
function M.handle_char_input(char)
    if not state.search_mode then return end

    local current_query = search_engine.current_query()

    if char == '\b' or char == '\127' then -- Backspace
        local chars = char_count(current_query)
        if chars > 0 then
            local new_query = vim.fn.strcharpart(current_query, 0, chars - 1)
            -- Defer buffer edits; insert-mode expr maps cannot change text immediately
            vim.schedule(function()
                M.render_content()
                M.perform_search_and_update(new_query)
            end)
        end
        return
    end

    if type(char) == 'string' and #char > 0 and char:match('[%w%s%p]') then
        local new_query = current_query .. char
        -- Defer buffer edits; insert-mode expr maps cannot change text immediately
        vim.schedule(function()
            M.render_content()
            M.perform_search_and_update(new_query)
        end)
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

-- Select current result with different open modes
function M.select_result(mode)
    if not state.winnr or not vim.api.nvim_win_is_valid(state.winnr) then
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(state.winnr)
    local line = cursor[1]
    local entry = state.line_index[line]
    if not entry then return end

    local function open_location(filepath, lnum, col, length, open_mode)
        local fname = vim.fn.fnamemodify(filepath, ':p')
        open_mode = open_mode or 'current'

        local target_win
        
        if open_mode == 'split' then
            -- Open in horizontal split
            vim.cmd('split')
            target_win = vim.api.nvim_get_current_win()
        elseif open_mode == 'vsplit' then
            -- Open in vertical split
            vim.cmd('vsplit')  
            target_win = vim.api.nvim_get_current_win()
        elseif open_mode == 'tab' then
            -- Open in new tab
            vim.cmd('tabnew')
            target_win = vim.api.nvim_get_current_win()
        else
            -- Default: use existing window or create split
            target_win = state.prev_winnr
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
        open_location(file_result.file, match.line_number, match.column, match.length, mode)
    elseif entry.type == 'file' then
        local file_result = state.results[entry.file_index]
        if not file_result then return end
        local first = file_result.matches[1]
        local line_number = first and first.line_number or 1
        local col = first and first.column or 0
        local length = first and first.length or 1
        open_location(file_result.file, line_number, col, length, mode)
    end
end

-- Jump to next file section
function M.jump_to_next_file()
    if not state.winnr or not vim.api.nvim_win_is_valid(state.winnr) then
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(state.winnr)
    local current_line = cursor[1]

    -- Find next file entry after current line
    for line_num = current_line + 1, vim.api.nvim_buf_line_count(state.bufnr) do
        local entry = state.line_index[line_num]
        if entry and entry.type == 'file' then
            vim.api.nvim_win_set_cursor(state.winnr, { line_num, 0 })
            M.update_selection_highlight()
            return
        end
    end

    -- If no file found after current line, wrap to beginning
    for line_num = 1, current_line - 1 do
        local entry = state.line_index[line_num]
        if entry and entry.type == 'file' then
            vim.api.nvim_win_set_cursor(state.winnr, { line_num, 0 })
            M.update_selection_highlight()
            return
        end
    end
end

-- Jump to previous file section
function M.jump_to_prev_file()
    if not state.winnr or not vim.api.nvim_win_is_valid(state.winnr) then
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(state.winnr)
    local current_line = cursor[1]

    -- Find previous file entry before current line
    for line_num = current_line - 1, 1, -1 do
        local entry = state.line_index[line_num]
        if entry and entry.type == 'file' then
            vim.api.nvim_win_set_cursor(state.winnr, { line_num, 0 })
            M.update_selection_highlight()
            return
        end
    end

    -- If no file found before current line, wrap to end
    for line_num = vim.api.nvim_buf_line_count(state.bufnr), current_line + 1, -1 do
        local entry = state.line_index[line_num]
        if entry and entry.type == 'file' then
            vim.api.nvim_win_set_cursor(state.winnr, { line_num, 0 })
            M.update_selection_highlight()
            return
        end
    end
end

-- Focus the input window
function M.focus_input()
    if state.input_winnr and vim.api.nvim_win_is_valid(state.input_winnr) then
        vim.api.nvim_set_current_win(state.input_winnr)
        -- Use schedule to ensure window focus happens before entering insert mode
        vim.schedule(function()
            if state.input_winnr and vim.api.nvim_win_is_valid(state.input_winnr) and 
               vim.api.nvim_get_current_win() == state.input_winnr then
                vim.cmd('startinsert!')
            end
        end)
    else
        -- If input window doesn't exist, start search mode  
        M.start_search()
    end
end

-- Focus the results window (switch from input to results, keep query visible)
function M.focus_results()
    if state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
        vim.api.nvim_set_current_win(state.winnr)
        
        -- Exit insert mode if we're in it
        if vim.fn.mode() == 'i' or vim.fn.mode() == 'I' then
            vim.cmd('stopinsert')
        end
        
        -- Keep input window visible but unfocused
        -- (Don't close it like the old behavior)
        
        -- Position cursor on first occurrence/match (prefer matches over file headers)
        local cursor = vim.api.nvim_win_get_cursor(state.winnr)
        local entry = state.line_index[cursor[1]]
        if not entry or (entry.type ~= 'match' and entry.type ~= 'file') then
            -- Find first match occurrence, fallback to first file if no matches
            local first_match_line = nil
            local first_file_line = nil
            
            for line_num, idx_entry in pairs(state.line_index) do
                if idx_entry.type == 'match' and not first_match_line then
                    first_match_line = line_num
                elseif idx_entry.type == 'file' and not first_file_line then
                    first_file_line = line_num
                end
            end
            
            -- Prefer first match over first file
            local target_line = first_match_line or first_file_line
            if target_line then
                vim.api.nvim_win_set_cursor(state.winnr, { target_line, 0 })
            end
        end
        M.update_selection_highlight()
    end
end

-- Collapse current file section
function M.collapse_current_file()
    if not state.winnr or not vim.api.nvim_win_is_valid(state.winnr) then
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(state.winnr)
    local line = cursor[1]
    local entry = state.line_index[line]

    -- If we're on a match, find its parent file
    if entry and entry.type == 'match' then
        -- Find the file entry for this match
        for check_line = line, 1, -1 do
            local check_entry = state.line_index[check_line]
            if check_entry and check_entry.type == 'file' and check_entry.file_index == entry.file_index then
                entry = check_entry
                line = check_line
                break
            end
        end
    end

    if entry and entry.type == 'file' then
        local file_result = state.results[entry.file_index]
        if file_result then
            state.collapsed_files[file_result.file] = true
            M.render_content()
            -- Keep cursor on the file line
            vim.api.nvim_win_set_cursor(state.winnr, { line, 0 })
        end
    end
end

-- Expand current file section
function M.expand_current_file()
    if not state.winnr or not vim.api.nvim_win_is_valid(state.winnr) then
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(state.winnr)
    local line = cursor[1]
    local entry = state.line_index[line]

    -- If we're on a match, find its parent file
    if entry and entry.type == 'match' then
        -- Find the file entry for this match
        for check_line = line, 1, -1 do
            local check_entry = state.line_index[check_line]
            if check_entry and check_entry.type == 'file' and check_entry.file_index == entry.file_index then
                entry = check_entry
                line = check_line
                break
            end
        end
    end

    if entry and entry.type == 'file' then
        local file_result = state.results[entry.file_index]
        if file_result then
            state.collapsed_files[file_result.file] = false
            M.render_content()
            -- Keep cursor on the file line
            vim.api.nvim_win_set_cursor(state.winnr, { line, 0 })
        end
    end
end

-- Smart toggle current file section (collapse if expanded, expand if collapsed)
function M.toggle_current_file()
    if not state.winnr or not vim.api.nvim_win_is_valid(state.winnr) then
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(state.winnr)
    local line = cursor[1]
    local entry = state.line_index[line]

    -- If we're on a match, find its parent file
    if entry and entry.type == 'match' then
        -- Find the file entry for this match
        for check_line = line, 1, -1 do
            local check_entry = state.line_index[check_line]
            if check_entry and check_entry.type == 'file' and check_entry.file_index == entry.file_index then
                entry = check_entry
                line = check_line
                break
            end
        end
    end

    if entry and entry.type == 'file' then
        local file_result = state.results[entry.file_index]
        if file_result then
            local filename = file_result.file
            -- Toggle: if collapsed, expand; if expanded, collapse
            local is_currently_collapsed = state.collapsed_files[filename]
            state.collapsed_files[filename] = not is_currently_collapsed
            M.render_content()
            -- Keep cursor on the file line
            vim.api.nvim_win_set_cursor(state.winnr, { line, 0 })
        end
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

    -- Clear the cursor highlight autocmd group for this buffer
    function M.clear_cursor_highlight_autocmd()
        if not state.bufnr then return end
        local name = 'yas-finder-cursor-' .. state.bufnr
        -- Reset sentinel so a new group can be created after reopen
        group = nil
        pcall(vim.api.nvim_del_augroup_by_name, name)
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
                vim.schedule(function()
                    M.render_content()
                    M._resize_input_window()
                end)
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
                vim.schedule(function()
                    M.render_content()
                    M._resize_input_window()
                end)
            end
        end,
    })
end

-- Clear resize-related autocmds
function M.clear_resize_autocmd()
    if state.resize_group then
        pcall(vim.api.nvim_del_augroup_by_id, state.resize_group)
        state.resize_group = nil
    end
end

-- Clear search-mode autocmd group tied to this buffer
function M.clear_search_autocmd()
    if not state.bufnr then return end
    local name = 'yas-search-' .. state.bufnr
    pcall(vim.api.nvim_del_augroup_by_name, name)
end

-- Clear all sidebar autocmd groups
function M.clear_sidebar_autocmds()
    M.clear_cursor_highlight_autocmd()
    M.clear_resize_autocmd()
    M.clear_search_autocmd()
end

-- Remove result
function M.remove_result()
    -- TODO: Implement result removal
    print('Remove result - TODO: implement')
end

-- Expose internal state for testing (development only)
if vim.g.yas_debug then
    M._get_state = function() return state end
end

return M
