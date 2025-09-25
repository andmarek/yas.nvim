local config = require('yas.config')

local M = {}

-- Internal state for search engine
local state = {
    current_query = '',
    last_results = {},
    search_timer = nil,
    running_jobs = {},
}

local DEFAULTS = {
    MAX_MATCHES_PER_FILE = 10,
    DEBOUNCE_MS = 100,
}

-- Helper functions
local function safe_strchars(text)
    local ok, len = pcall(vim.fn.strchars, text or '')
    if ok then return len end
    return (text and #text) or 0
end

local function safe_utfindex(text, byte_index)
    local ok, idx = pcall(vim.str_utfindex, text or '', byte_index or 0)
    if ok then return idx end
    return byte_index or 0
end

-- Stop any running search operations
local function stop_internal()
    -- Cancel debounce timer
    if state.search_timer then
        if not state.search_timer:is_closing() then
            state.search_timer:stop()
            state.search_timer:close()
        end
        state.search_timer = nil
    end
    
    -- Cancel any running jobs
    for job_id in pairs(state.running_jobs) do
        pcall(vim.fn.jobstop, job_id)
        state.running_jobs[job_id] = nil
    end
end

-- Parse ripgrep JSON output
local function parse_ripgrep_output(data, query)
    local results_map = {}
    query = query or ''

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
                    local length = safe_strchars(query)
                    if json_data.data.submatches and json_data.data.submatches[1] then
                        local submatch = json_data.data.submatches[1]
                        -- submatch.start is 0-based byte offset, convert to 0-based character offset
                        column = safe_utfindex(line_text, submatch.start or 0)
                        if submatch.match and submatch.match.text then
                            length = safe_strchars(submatch.match.text)
                        end
                    end

                    table.insert(results_map[file_path].matches, {
                        line_number = line_number,
                        text = line_text,
                        column = column,
                        length = length,
                    })
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

-- Execute ripgrep search
local function search_with_ripgrep(query, callback)
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

    -- Limit results for performance
    table.insert(cmd, '--max-count')
    table.insert(cmd, DEFAULTS.MAX_MATCHES_PER_FILE)

    table.insert(cmd, query)
    table.insert(cmd, '.')

    local actual_job_id = nil
    
    local job_ok, job_id = pcall(vim.fn.jobstart, cmd, {
        stdout_buffered = true,
        on_stdout = function(job_id_param, data)
            -- Remove this job from running jobs using the parameter
            if actual_job_id then
                state.running_jobs[actual_job_id] = nil
            end
            
            if data and #data > 0 then
                -- Filter out empty lines
                local filtered_data = {}
                for _, line in ipairs(data) do
                    if line and line ~= '' then
                        table.insert(filtered_data, line)
                    end
                end

                if #filtered_data > 0 then
                    local parse_ok, results = pcall(parse_ripgrep_output, filtered_data, query)
                    if parse_ok then
                        callback(results or {})
                    else
                        vim.notify('Error parsing search results: ' .. tostring(results), vim.log.levels.ERROR)
                        callback({})
                    end
                else
                    callback({})
                end
            else
                callback({})
            end
        end,
        on_stderr = function(job_id_param, data)
            if data and #data > 0 then
                -- Filter out empty strings
                local filtered_data = {}
                for _, line in ipairs(data) do
                    if line and line ~= '' then
                        table.insert(filtered_data, line)
                    end
                end

                if #filtered_data > 0 then
                    local error_msg = table.concat(filtered_data, '\n')
                    vim.notify('Ripgrep error: ' .. error_msg, vim.log.levels.ERROR)
                end
            end
        end,
        on_exit = function(job_id_param, code)
            -- Remove this job from running jobs using the parameter  
            if actual_job_id then
                state.running_jobs[actual_job_id] = nil
            end
            
            if code ~= 0 and code ~= 1 then -- ripgrep returns 1 when no matches found
                vim.notify('Ripgrep exited with code: ' .. code, vim.log.levels.WARN)
            end
        end,
    })

    if job_ok and type(job_id) == 'number' then
        actual_job_id = job_id
        state.running_jobs[job_id] = true
    else
        vim.notify('Failed to start ripgrep job: ' .. tostring(job_id), vim.log.levels.ERROR)
        callback({})
    end
end

-- Public API

---Start (or restart) a debounced search
---@param query string The search query
---@param on_done function Callback when results are ready: function(results)
function M.request(query, on_done)
    if type(on_done) ~= 'function' then
        vim.notify('Search callback must be a function', vim.log.levels.ERROR)
        return
    end
    
    -- Stop any existing search
    stop_internal()
    
    -- Update current query
    state.current_query = query or ''
    
    -- Handle empty query
    if state.current_query == '' then
        state.last_results = {}
        on_done({})
        return
    end
    
    -- Start debounced search
    state.search_timer = vim.loop.new_timer()
    state.search_timer:start(DEFAULTS.DEBOUNCE_MS, 0, vim.schedule_wrap(function()
        -- Perform the actual search
        local search_ok, search_err = pcall(function()
            search_with_ripgrep(state.current_query, function(results)
                state.last_results = results or {}
                on_done(state.last_results)
            end)
        end)
        
        if not search_ok then
            vim.notify('Search error: ' .. tostring(search_err), vim.log.levels.ERROR)
            state.last_results = {}
            on_done({})
        end
        
        -- Clean up timer
        if state.search_timer and not state.search_timer:is_closing() then
            state.search_timer:close()
            state.search_timer = nil
        end
    end))
end

---Stop any running search jobs and timers
function M.stop()
    stop_internal()
end

---Get the last completed search results
---@return table The last search results (may be empty)
function M.last_results()
    return state.last_results
end

---Get the current search query
---@return string Current query
function M.current_query()
    return state.current_query
end

---Check if a search is currently running
---@return boolean True if search is running
function M.is_running()
    return state.search_timer ~= nil or next(state.running_jobs) ~= nil
end

-- Expose internal state for testing (development only)
if vim.g.yas_debug then
    M._get_state = function() return state end
end

return M
