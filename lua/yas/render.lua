local M = {}

-- Helper functions
local function make_divider(width)
    return '  ' .. string.rep('─', math.max(0, (width or 0) - 2))
end

local function truncated_display(query, max_chars)
    return vim.fn.strcharpart(query or "", 0, max_chars or 32)
end

-- Render header section with title (no inline input - we use floating window)
function M.render_header(search_query, sidebar_width)
    local lines = {}
    local idx_map = {}

    -- Title
    table.insert(lines, '  YAS Finder')
    table.insert(idx_map, { type = 'header' })
    table.insert(lines, '  Search across files')
    table.insert(idx_map, { type = 'header' })

    -- Space for floating input window (this line will be covered by the floating window)
    table.insert(lines, '') -- Empty line where floating input appears
    table.insert(idx_map, { type = 'input_placeholder' })

    table.insert(lines, make_divider(sidebar_width))
    table.insert(idx_map, { type = 'divider' })
    table.insert(lines, '')
    table.insert(idx_map, { type = 'blank' })

    return lines, idx_map
end

-- Render help section with keybindings
function M.render_help()
    local lines = {}
    local idx_map = {}

    table.insert(lines, ' Keybindings')
    table.insert(idx_map, { type = 'help' })
    table.insert(lines, '   i     Start search')
    table.insert(idx_map, { type = 'help' })
    table.insert(lines, '   <CR>  Open result')
    table.insert(idx_map, { type = 'help' })
    table.insert(lines, '   za    Toggle file group')
    table.insert(idx_map, { type = 'help' })
    table.insert(lines, '   dd    Remove result (soon)')
    table.insert(idx_map, { type = 'help' })
    table.insert(lines, '   q     Close finder')
    table.insert(idx_map, { type = 'help' })
    table.insert(lines, '')
    table.insert(idx_map, { type = 'blank' })
    table.insert(lines, ' Start typing to search across your project')
    table.insert(idx_map, { type = 'help' })

    return lines, idx_map
end

-- Render individual matches for a file
function M.render_matches(file_result, file_index, sidebar_width, trim_match_preview_fn)
    local lines = {}
    local idx_map = {}

    for match_index, match in ipairs(file_result.matches) do
        -- Clean the line text but preserve original positioning info
        local original_line = match.text:gsub('[\r\n]', ' ')
        local leading_whitespace = string.match(original_line, '^%s*') or ''
        local whitespace_char_count = vim.fn.strchars(leading_whitespace)
        local preview = original_line:gsub('^%s*', ''):gsub('%s*$', '')

        -- Adjust column to account for removed leading whitespace
        local adjusted_column = math.max(0, (match.column or 0) - whitespace_char_count)

        local prefix = string.format('    %d: ', match.line_number)
        local trimmed_preview, highlight_start, highlight_len = trim_match_preview_fn(preview, sidebar_width, prefix,
            adjusted_column, match.length)
        table.insert(lines, prefix .. trimmed_preview)
        table.insert(idx_map, {
            type = 'match',
            file_index = file_index,
            match_index = match_index,
            prefix = prefix,
            highlight_start = highlight_start,
            highlight_length = highlight_len,
        })
    end
    table.insert(lines, '')
    table.insert(idx_map, { type = 'blank' })

    return lines, idx_map
end

-- Render search results section
function M.render_results(search_query, results, collapsed_files, sidebar_width, trim_match_preview_fn)
    local lines = {}
    local idx_map = {}

    if #results == 0 then
        table.insert(lines, ' No matches found')
        table.insert(idx_map, { type = 'empty' })
        return lines, idx_map
    end

    for file_index, file_result in ipairs(results) do
        local clean_filename = file_result.file:gsub('[\r\n]', '')
        local is_collapsed = collapsed_files[clean_filename] == true
        local icon = is_collapsed and '▸' or '▾'
        local header = string.format('%s %s (%d matches)', icon, clean_filename, #file_result.matches)
        table.insert(lines, header)
        table.insert(idx_map, {
            type = 'file',
            file_index = file_index,
            collapsed = is_collapsed,
            file = clean_filename,
        })

        if not is_collapsed then
            local match_lines, match_idx_map = M.render_matches(file_result, file_index, sidebar_width,
                trim_match_preview_fn)
            for _, line in ipairs(match_lines) do
                table.insert(lines, line)
            end
            for _, idx in ipairs(match_idx_map) do
                table.insert(idx_map, idx)
            end
        end
    end
    table.insert(lines, make_divider(sidebar_width))
    table.insert(idx_map, { type = 'divider' })

    return lines, idx_map
end

-- Main render function that combines all sections
function M.render_content(state, sidebar_width, trim_match_preview_fn)
    -- Get current query from search engine
    local search_engine = require('yas.search_engine')
    local current_query = search_engine.current_query()

    local lines, idx_map = M.render_header(current_query, sidebar_width)

    if current_query == '' then
        local help_lines, help_idx_map = M.render_help()
        for _, line in ipairs(help_lines) do
            table.insert(lines, line)
        end
        for _, idx in ipairs(help_idx_map) do
            table.insert(idx_map, idx)
        end
    else
        local result_lines, result_idx_map = M.render_results(
            current_query,
            state.results,
            state.collapsed_files,
            sidebar_width,
            trim_match_preview_fn
        )
        for _, line in ipairs(result_lines) do
            table.insert(lines, line)
        end
        for _, idx in ipairs(result_idx_map) do
            table.insert(idx_map, idx)
        end
    end

    return lines, idx_map
end

return M
