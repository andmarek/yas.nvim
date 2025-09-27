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
        selection = 'Visual',
        title = 'Title',
        subtitle = 'Comment',
        prompt = 'Identifier',
        input = 'Normal',
        divider = 'LineNr',
        section = 'Include',
        folder_icon = 'Special',
        match_count = 'Number',
        help_text = 'Comment',
    },

    -- Keybindings within the finder window
    keymaps = {
        -- Core actions
        close = '<leader>q',
        select = '<CR>',
        
        -- Navigation
        directory_next = '<C-n>',
        directory_prev = '<C-p>',
        fold_current = 'h',
        back_to_insert = 'i',
        
        -- Legacy/additional bindings
        toggle_file = 'za',
        clear_search = '<C-c>',
        
        -- Input pane specific
        focus_results = '<CR>',  -- From input to results
    }
}

M.options = {}

function M.setup(opts)
    M.options = vim.tbl_deep_extend('force', M.defaults, opts)
end

M.setup({})

return M
