local M = {}

-- Default configuration
M.defaults = {
    -- Window settings
    width = 40,
    position = 'left',

    -- Search settings
    ignore_case = true,
    max_results = 100,

    ignore_patterns = {
        '.git/',
        'node_modules/',
        '.DS_Store',
        '*.pyc',
        '*.o',
        '*.class',
    },

    -- Highlight groups
    highlights = {
        match = 'Search',
        file_name = 'Directory',
        line_number = 'LineNr',
        context = 'Comment',
    },

    -- Keybindings within the finder window
    keymaps = {
        close = 'q',
        select = '<CR>',
        toggle_file = 'za',
        remove_result = 'dd',
        clear_search = '<C-c>',
    }
}

M.options = {}

function M.setup(opts)
    M.options = vim.tbl_deep_extend('force', M.defaults, opts)
end

M.setup({})

return M
