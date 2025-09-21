# YAS.nvim - Yet Another Search Plugin

A VSCode-like finder plugin for Neovim that provides a sidebar interface for searching text across files.

## Features

- 🔍 Real-time search across all files in your project
- 📁 Results organized by file with collapsible sections
- 🎯 Click to navigate directly to matches with highlighting
- ⚡ Fast search using ripgrep (with vim fallback)
- 🗑️ Remove individual search results
- ⚙️ Highly configurable

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

## Usage

### Commands

- `:YasOpen` - Open the finder sidebar
- `:YasClose` - Close the finder sidebar  
- `:YasToggle` - Toggle the finder sidebar

### Default Keybindings

- `<C-S-f>` - Toggle finder (global)

### Finder Keybindings

- `i` - Start search input
- `<CR>` - Navigate to selected result
- `za` - Toggle file expand/collapse
- `dd` - Remove result from list
- `q` - Close finder

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
  
  -- Keybindings within the finder window
  keymaps = {
    close = 'q',
    select = '<CR>',
    toggle_file = 'za',
    remove_result = 'dd',
    clear_search = '<C-c>',
  }
})
```

## Requirements

- Neovim 0.7+
- ripgrep (optional, for faster search)

## Development Status

This plugin is currently in early development. Core features implemented:

- [x] Basic plugin structure
- [x] Sidebar window management
- [x] Search functionality with ripgrep/vim fallback
- [x] Basic result display
- [ ] Result navigation and highlighting
- [ ] File collapsing/expanding
- [ ] Result removal
- [ ] Advanced highlighting and UI polish

## License

MIT
