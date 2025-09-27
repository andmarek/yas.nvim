# YAS.nvim - Yet Another Search Plugin

A VSCode-like finder plugin for Neovim with smooth Vim-native navigation.

## Features

-  **Real-time search** across all files in your project
-  **File organization** with smart fold/unfold
-  **Vim-native navigation** - j/k for results, Ctrl+n/p for directories
- **Fast search** Ripgrep for fast searching 

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'andy/yas.nvim',
  config = function()
    require('yas').setup({
      -- your configuration here
    })
  end
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'andy/yas.nvim',
  config = function()
    require('yas').setup()
  end
}
```

## Quick Start

```lua
-- Toggle finder and start searching immediately  
:YasToggle

-- Or use the API
lua require('yas').toggle()
```

## Smooth Workflow

1. **Search**: `:YasToggle` opens in insert mode - start typing immediately
2. **Navigate**: `<CR>` switches to results, use `j/k` to navigate matches
3. **Directories**: `<C-n>/<C-p>` to jump between files, `h` to fold/unfold
4. **Open**: `<CR>` opens the selected result  
5. **Return**: `i` goes back to search, `<leader>q` closes finder

## API Functions

```lua
require('yas').toggle()           -- Open/close finder
require('yas').insert()           -- Focus search input
require('yas').next_directory()   -- Jump to next file
require('yas').prev_directory()   -- Jump to previous file  
require('yas').fold_current()     -- Toggle fold current file
```

## Default Keybindings

### Input Pane (Search)
- `<CR>` - Switch to results (normal mode, first match)
- `<leader>q` - Close finder

### Results Pane (Navigation)
- `<CR>` - Open selected result
- `j/k` - Navigate between matches
- `<C-n>/<C-p>` - Jump between files  
- `h` - Toggle fold/unfold file
- `i` - Return to search input
- `<leader>q` - Close finder

## Configuration

```lua
require('yas').setup({
  -- Window settings
  width = 40,
  position = 'left', -- 'left' or 'right'
  
  -- Search settings
  ignore_case = true,
  max_results = 1000,
  
  -- File patterns to ignore
  ignore_patterns = {
    '%.git/',
    'node_modules/',
    '%.DS_Store',
    '%.pyc$',
    '%.o$',
    '%.class$',
  },
  
  -- Highlight groups
  highlights = {
    match = 'Search',
    file_name = 'Directory',
    line_number = 'LineNr',
    context = 'Comment',
  },
  
  -- Customizable keybindings
  keymaps = {
    close = '<leader>q',           -- Close finder
    select = '<CR>',               -- Open result  
    directory_next = '<C-n>',      -- Next file
    directory_prev = '<C-p>',      -- Previous file
    fold_current = 'h',            -- Toggle fold
    back_to_insert = 'i',          -- Return to search
    focus_results = '<CR>',        -- Input -> results
  }
})
```

## Requirements

- Neovim 0.7+
- ripgrep (optional, for faster search)
