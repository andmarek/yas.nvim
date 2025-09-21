local config = require('yas.config')

local M = {}

local DEFAULTS = {
    MAX_MATCHES_PER_FILE = 10,
    FIND_COMMAND = 'find . -type f',
}

-- Perform search in files
function M.perform_search(query, callback)
    if not query or query == '' then
        callback({})
        return
    end

    if not callback or type(callback) ~= 'function' then
        vim.notify('Search callback is not a function', vim.log.levels.ERROR)
        return
    end

    local opts = config.options
    local results = {}

    local search_ok, search_err = pcall(function()
        M.search_with_ripgrep(query, callback)
    end)

    if not search_ok then
        vim.notify('Search execution error: ' .. tostring(search_err), vim.log.levels.ERROR)
        callback({})
    end
end

-- Search using ripgrep
function M.search_with_ripgrep(query, callback)
    local opts = config.options
    local cmd = { 'rg', '--json', '--no-heading', '--with-filename', '--line-number' }

    -- Add ignore patterns
    for _, pattern in ipairs(opts.ignore_patterns) do
        table.insert(cmd, '--glob')
        table.insert(cmd, '!' .. pattern)
    end

    -- Add case insensitivity
    if opts.ignore_case then
        table.insert(cmd, '--ignore-case')
    end

    -- Limit results for performance (valid ripgrep flag)
    table.insert(cmd, '--max-count')
    table.insert(cmd, DEFAULTS.MAX_MATCHES_PER_FILE)

    table.insert(cmd, query)
    table.insert(cmd, '.')

    local job_ok, job_id = pcall(vim.fn.jobstart, cmd, {
        stdout_buffered = true,
        on_stdout = function(_, data)
            if data and #data > 0 then
                -- Filter out empty lines
                local filtered_data = {}
                for _, line in ipairs(data) do
                    if line and line ~= '' then
                        table.insert(filtered_data, line)
                    end
                end

                if #filtered_data > 0 then
                    local parse_ok, results = pcall(M.parse_ripgrep_output, filtered_data)
                    if parse_ok then
                        callback(results or {})
                    else
                        vim.notify('Error parsing search results: ' .. tostring(results), vim.log.levels.ERROR)
                    end
                else
                    callback({})
                end
            else
                callback({})
            end
        end,
        on_stderr = function(_, data)
            if data and #data > 0 then
                -- Filter out empty strings and join
                local filtered_data = {}
                for _, line in ipairs(data) do
                    if line and line ~= '' then
                        table.insert(filtered_data, line)
                    end
                end

                if #filtered_data > 0 then
                    local error_msg = table.concat(filtered_data, '\n')
                    vim.notify('Ripgrep error: ' .. error_msg, vim.log.levels.ERROR)
                    vim.notify('Command: ' .. table.concat(cmd, ' '), vim.log.levels.ERROR)
                end
            end
        end,
        on_exit = function(_, code)
            if code ~= 0 and code ~= 1 then -- ripgrep returns 1 when no matches found
                vim.notify('Ripgrep exited with code: ' .. code, vim.log.levels.WARN)
            end
        end,
    })

    if not job_ok then
        vim.notify('Failed to start ripgrep job: ' .. tostring(job_id), vim.log.levels.ERROR)
        callback({})
    end
end

-- Parse ripgrep JSON output
function M.parse_ripgrep_output(data)
    local results_map = {}

    for _, line in ipairs(data) do
        if line and line ~= '' then
            local ok, json_data = pcall(vim.fn.json_decode, line)
            if ok and json_data and type(json_data) == 'table' and json_data.type == 'match' then
                -- Safely extract data with error checking
                local data_ok, file_path, line_number, line_text = pcall(function()
                    return json_data.data.path.text,
                        json_data.data.line_number,
                        json_data.data.lines.text
                end)

                if data_ok and file_path and line_number and line_text then
                    if not results_map[file_path] then
                        results_map[file_path] = {
                            file = file_path,
                            matches = {}
                        }
                    end

                    local column = 0
                    if json_data.data.submatches and json_data.data.submatches[1] then
                        column = json_data.data.submatches[1].start or 0
                    end

                    table.insert(results_map[file_path].matches, {
                        line_number = line_number,
                        text = line_text,
                        column = column,
                    })
                end
            elseif not ok then
                -- Only notify on actual JSON parsing errors, not empty lines
                if line:match('^{') then -- Only for lines that look like JSON
                    vim.notify('JSON parse error: ' .. tostring(json_data), vim.log.levels.DEBUG)
                end
            end
        end
    end

    -- Convert map to array
    local results = {}
    for _, file_result in pairs(results_map) do
        -- Sort matches by line number
        table.sort(file_result.matches, function(a, b) return a.line_number < b.line_number end)
        table.insert(results, file_result)
    end

    -- Sort files alphabetically
    table.sort(results, function(a, b) return a.file < b.file end)

    return results
end

-- Search within a single file
function M.search_in_file(filepath, query, ignore_case)
    local matches = {}

    local file = io.open(filepath, 'r')
    if not file then
        return matches
    end

    local line_number = 0
    local search_query = ignore_case and query:lower() or query

    for line in file:lines() do
        line_number = line_number + 1
        local search_line = ignore_case and line:lower() or line

        local start_pos = search_line:find(search_query, 1, true)
        if start_pos then
            table.insert(matches, {
                line_number = line_number,
                text = line,
                column = start_pos - 1,
            })
        end
    end

    file:close()
    return matches
end

return M
