local M = {}

-- Create namespaces for different highlight types
M.ns_all = vim.api.nvim_create_namespace('yas_all')
M.ns_focus = vim.api.nvim_create_namespace('yas_focus')

-- Timer for throttling updates
local timer = vim.loop.new_timer()

-- Cache for active highlights to avoid unnecessary updates
local highlight_cache = {}

-- Current search query for highlighting new buffers
local current_query = ''

-- Utility function to sanitize UTF-8 text (removes invalid bytes)
local function sanitize_utf8(text)
    if not text then return '' end
    -- Replace invalid UTF-8 sequences with replacement character
    local ok, _ = pcall(vim.fn.strchars, text)
    if ok then 
        return text 
    else
        -- If the text contains invalid UTF-8, replace problematic bytes
        return text:gsub('[\128-\255]', '?')
    end
end

-- Initialize highlight groups
function M.setup_highlights()
    -- Define default highlight groups
    vim.api.nvim_set_hl(0, 'YasSecondary', {
        bg = '#3e4451',
        fg = '#ffffff',
        default = true
    })
    
    vim.api.nvim_set_hl(0, 'YasPrimary', {
        bg = '#e06c75',
        fg = '#ffffff',
        bold = true,
        default = true
    })
    
    -- Setup auto-highlighting for newly opened buffers
    M.setup_auto_highlight()
end

-- Highlight all matches in a buffer with secondary style
function M.highlight_all(bufnr, matches)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end
    
    -- Clear existing highlights
    vim.api.nvim_buf_clear_namespace(bufnr, M.ns_all, 0, -1)
    
    if not matches or #matches == 0 then
        highlight_cache[bufnr] = nil
        return
    end
    
    -- Check if highlights changed to avoid unnecessary updates
    -- Create a safe cache key without potentially invalid UTF-8 text
    local safe_matches = {}
    for i, match in ipairs(matches) do
        table.insert(safe_matches, {
            line_number = match.line_number,
            column = match.column,
            length = match.length
            -- Exclude 'text' field which may contain invalid UTF-8
        })
    end
    
    local cache_key_ok, cache_key = pcall(vim.fn.json_encode, safe_matches)
    if not cache_key_ok then
        -- Fallback to a simple hash if json encoding still fails
        cache_key = string.format('%s_%d', bufnr, #matches)
    end
    
    if highlight_cache[bufnr] == cache_key then
        return
    end
    highlight_cache[bufnr] = cache_key
    
    -- Add extmarks for all matches
    for _, match in ipairs(matches) do
        local line_num = match.line_number - 1  -- Convert to 0-based
        local col_start = match.column or 0
        local length = match.length or 1
        
        -- Ensure we don't go beyond line boundaries
        local line_text = vim.api.nvim_buf_get_lines(bufnr, line_num, line_num + 1, false)[1]
        if line_text then
            local line_len = vim.fn.strchars(line_text)
            if col_start >= line_len then
                col_start = math.max(0, line_len - 1)
            end
            if col_start + length > line_len then
                length = line_len - col_start
            end
            
            if length > 0 then
                vim.api.nvim_buf_set_extmark(bufnr, M.ns_all, line_num, col_start, {
                    end_row = line_num,
                    end_col = col_start + length,
                    hl_group = 'YasSecondary',
                    priority = 10
                })
            end
        end
    end
end

-- Highlight focused/current match with primary style
function M.highlight_focus(bufnr, line_num, col, length)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end
    
    -- Clear existing focus highlights
    vim.api.nvim_buf_clear_namespace(bufnr, M.ns_focus, 0, -1)
    
    if not line_num or not col or not length then
        return
    end
    
    local line_index = line_num - 1  -- Convert to 0-based
    local col_start = col or 0
    
    -- Ensure we don't go beyond line boundaries
    local line_text = vim.api.nvim_buf_get_lines(bufnr, line_index, line_index + 1, false)[1]
    if line_text then
        local line_len = vim.fn.strchars(line_text)
        if col_start >= line_len then
            col_start = math.max(0, line_len - 1)
        end
        if col_start + length > line_len then
            length = line_len - col_start
        end
        
        if length > 0 then
            vim.api.nvim_buf_set_extmark(bufnr, M.ns_focus, line_index, col_start, {
                end_row = line_index,
                end_col = col_start + length,
                hl_group = 'YasPrimary',
                priority = 100  -- Higher priority to overlay secondary highlights
            })
        end
    end
end

-- Throttled highlight update to avoid flickering during typing
function M.schedule_highlight_refresh(bufnr, matches, delay)
    delay = delay or 30  -- Default 30ms delay
    
    timer:stop()
    timer:start(delay, 0, function()
        vim.schedule(function()
            M.highlight_all(bufnr, matches)
        end)
    end)
end

-- Clear all highlights from a buffer
function M.clear_highlights(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end
    
    vim.api.nvim_buf_clear_namespace(bufnr, M.ns_all, 0, -1)
    vim.api.nvim_buf_clear_namespace(bufnr, M.ns_focus, 0, -1)
    highlight_cache[bufnr] = nil
end

-- Clear all highlights from all buffers
function M.clear_all_highlights()
    -- Clear the current query to stop auto-highlighting
    current_query = ''
    
    -- Get all loaded buffers
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            M.clear_highlights(bufnr)
        end
    end
    highlight_cache = {}
end

-- Find all occurrences of a pattern in a buffer
function M.highlight_all_occurrences_in_buffer(bufnr, query)
    if not vim.api.nvim_buf_is_valid(bufnr) or not query or query == '' then
        return
    end
    
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local matches = {}
    
    -- Escape special regex characters for literal search
    local escaped_query = vim.fn.escape(query, '.*[]^$\\')
    
    for line_num, line_text in ipairs(lines) do
        local col = 1
        while col <= #line_text do
            -- Find next occurrence (case insensitive by default)
            local start_pos, end_pos = string.find(line_text:lower(), escaped_query:lower(), col, true)
            if start_pos then
                -- Convert to 0-based indexing and character positions
                local char_start = vim.fn.strchars(string.sub(line_text, 1, start_pos - 1))
                local match_text = string.sub(line_text, start_pos, end_pos)
                local char_length = vim.fn.strchars(match_text)
                
                table.insert(matches, {
                    line_number = line_num,
                    column = char_start,
                    length = char_length,
                    text = sanitize_utf8(line_text)
                })
                
                col = end_pos + 1
            else
                break
            end
        end
    end
    
    -- Apply highlights with throttling
    M.schedule_highlight_refresh(bufnr, matches)
end

-- Convert search results to match format for highlighting (legacy function)
function M.convert_search_results_to_matches(search_results)
    local all_matches = {}
    
    for _, file_result in ipairs(search_results) do
        local bufnr = vim.fn.bufnr(file_result.file)
        if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
            all_matches[bufnr] = file_result.matches
        end
    end
    
    return all_matches
end

-- Highlight matches in all relevant buffers
function M.highlight_search_results(search_results, query)
    current_query = query or ''
    
    if not query or query == '' then
        -- Clear all highlights if no query
        M.clear_all_highlights()
        return
    end
    
    -- Get all loaded buffers that have files associated
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            local buf_name = vim.api.nvim_buf_get_name(bufnr)
            if buf_name ~= '' and not buf_name:match('^%w+://') then -- Skip special buffers
                M.highlight_all_occurrences_in_buffer(bufnr, query)
            end
        end
    end
end

-- Get file path from buffer number
local function get_file_path(bufnr)
    return vim.api.nvim_buf_get_name(bufnr)
end

-- Setup autocmd to highlight newly opened buffers
function M.setup_auto_highlight()
    local group = vim.api.nvim_create_augroup('yas_auto_highlight', { clear = true })
    
    vim.api.nvim_create_autocmd({'BufRead', 'BufEnter'}, {
        group = group,
        callback = function(args)
            local bufnr = args.buf
            if current_query ~= '' and vim.api.nvim_buf_is_valid(bufnr) then
                local buf_name = vim.api.nvim_buf_get_name(bufnr)
                -- Only highlight real files, not special buffers
                if buf_name ~= '' and not buf_name:match('^%w+://') then
                    vim.defer_fn(function()
                        M.highlight_all_occurrences_in_buffer(bufnr, current_query)
                    end, 100) -- Small delay to ensure buffer is ready
                end
            end
        end
    })
end

-- Jump to and highlight a specific match
function M.jump_to_match(file_path, line_num, col, length)
    -- Open or switch to the file
    local bufnr = vim.fn.bufnr(file_path)
    if bufnr == -1 then
        -- File not loaded, open it
        vim.cmd('edit ' .. vim.fn.fnameescape(file_path))
        bufnr = vim.fn.bufnr('%')
    else
        -- Switch to existing buffer
        vim.cmd('buffer ' .. bufnr)
    end
    
    -- Jump to the line and column
    vim.api.nvim_win_set_cursor(0, {line_num, col})
    
    -- Highlight all occurrences in the buffer if we have a current query
    if current_query ~= '' then
        M.highlight_all_occurrences_in_buffer(bufnr, current_query)
    end
    
    -- Highlight the focused match
    M.highlight_focus(bufnr, line_num, col, length)
    
    -- Center the cursor in the window
    vim.cmd('normal! zz')
end

return M
