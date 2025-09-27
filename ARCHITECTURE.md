## YAS.nvim Architecture and Window Guide

This document explains how the plugin is structured and how the `window.lua` UI works, with a quick Vim API glossary to orient readers who are new to Lua/Neovim.

### High-level Overview

- **Goal**: VS Code–like search sidebar that queries ripgrep and shows matches grouped by file.
- **User entry points**: Commands defined in `plugin/yas.vim` (`:YasOpen`, `:YasToggle`, etc.).
- **Core modules**:
  - `lua/yas/init.lua`: Public API (`open`, `close`, `toggle`, `focus`, `setup`). Orchestrates the window lifecycle.
  - `lua/yas/window.lua`: Sidebar UI. Creates a dedicated buffer/window, handles input, keymaps, rendering, highlights, and navigation.
  - `lua/yas/search.lua`: Ripgrep integration. Spawns `rg --json`, parses streamed output into structured results.
  - `lua/yas/config.lua`: Defaults and user options. Deep-merged via `setup()`.
  - `lua/yas/highlight.lua`: Applies match highlights in regular buffers and focused match highlight.

### Sequence Diagram (conceptual)

```
User ──:YasToggle──▶ yas.init.toggle() ──┬─▶ yas.init.open() ─▶ window.create_buffer()
                                         │
                                         └─▶ yas.init.close() ─▶ window.close()

window.create_buffer()
  ├─ create sidebar buf+win, set opts
  ├─ setup_search_autocmds(buf) → insert-mode mappings & InsertLeave
  ├─ setup_buffer_keymaps(buf)  → normal-mode UX + navigation
  ├─ ensure_cursor_highlight_autocmd()
  ├─ ensure_resize_autocmd()
  └─ render_content() and startinsert at search line

User types → window.handle_char_input / insert-mode keymaps
  └─ perform_search_and_update() [debounced]
       └─ search.perform_search(query, cb)
            └─ search.search_with_ripgrep(query, cb)
                └─ vim.fn.jobstart('rg --json ...', handlers)
                    └─ parse_ripgrep_output(lines) → results

Callback(results)
  ├─ update state.results
  ├─ render_content() (rebuilds sidebar lines, maintains index map)
  └─ highlight.highlight_search_results(results, query) in open buffers

Selecting a result → window.select_result()
  ├─ open file in prev window (or split)
  ├─ jump to line/column
  └─ highlight.highlight_focus(buf, lnum, col, len)
```

### Data Model

- `state` (in `window.lua`):
  - `bufnr`, `winnr`, `prev_winnr`: handle buffers/windows and returning focus.
  - `search_query`, `search_mode`: current text and whether we’re in insert-mode UX.
  - `results`: array of `{ file, matches = [{ line_number, text, column, length }] }`.
  - `line_index`: per-render index that maps each buffer line to a metadata record like `{ type = 'file'|'match'|..., file_index, match_index, ... }` for hit-testing and navigation.
  - `ns`, `ns_ui`: highlight namespaces for selection/UI accenting inside the sidebar.
  - `collapsed_files`: filename→boolean map for expand/collapse.
  - `search_timer`: libuv timer for debounced search (100ms).
  - `last_sidebar_width`: cache for responsive re-rendering.

### Window/UI Lifecycle

1) `window.create_buffer()`
   - Creates a scratch buffer (`buftype=nofile`, `bufhidden=wipe`), sets filetype `yas-finder`.
   - Splits the current tab left/right, fixes width, disables numbers/signcolumn/wrap.
   - Installs autocmds: resize handling; cursor highlight updates; insert-mode exit (`InsertLeave`) to stop search mode.
   - Sets buffer-local keymaps:
     - Normal mode: `q` close, `<CR>` select result/exit search, `za` toggle group, `i` enter search, printable keys start search flow.
     - Insert mode: character input is intercepted via expr mappings to update the search query via the search engine without editing buffer text directly.
   - Renders the initial content and positions cursor on the input line.

2) Rendering: `window.render_content()`
   - Rebuilds all display lines: header, input row (`> query...`), divider, help or results.
   - Populates `state.line_index` to map every buffer line to a semantic entry used by navigation and highlighting.
   - Applies UI highlights (`apply_result_highlights`) and selection highlight for the current cursor line (`update_selection_highlight`).

3) Typing/Search: `window.handle_char_input` and `setup_insert_mode_keymaps`
   - Update the search query via the search engine, re-render immediately for snappy UX, then trigger a debounced search operation.
   - Debounce timer fires → `search.perform_search` → ripgrep job → `parse_ripgrep_output` → callback with structured results → store in `state.results` → `render_content()` → apply highlights in open buffers via `highlight.highlight_search_results`.

4) Selecting a result: `window.select_result()`
   - Determines the selected entry from `state.line_index`.
   - Opens the file in the previous window (or a split), jumps to location, centers view, and calls `highlight.highlight_focus` to accent the match.

5) Expand/Collapse files: `window.toggle_file()`
   - Toggles filename flag in `state.collapsed_files` and re-renders.

### `window.lua` Key Functions

- `create_buffer()`: Set up the sidebar split and buffer, options, keymaps, autocmds; initial render.
- `render_content()`: Build lines + index map; apply UI and selection highlights; keep cursor on the input line in search mode.
- `perform_search_and_update()`: Debounced ripgrep search; safe `pcall` around backend; update results and highlight across buffers.
- `select_result()`: Open file and jump; apply focused highlight.
- `setup_search_autocmds()`, `setup_insert_mode_keymaps()`, `setup_buffer_keymaps()`: Wire input and navigation.
- `apply_result_highlights()`, `update_selection_highlight()`: Sidebar visuals.
- `ensure_resize_autocmd()`, `ensure_cursor_highlight_autocmd()`: Responsiveness and selection tracking.

### Search Backend (`search.lua`)

- Spawns ripgrep via `vim.fn.jobstart` with flags:
  - `--json`, `--with-filename`, `--line-number`, optional `--ignore-case`, `--glob !pattern` for ignores, and `--max-count <N>` per file.
- Streams `stdout` lines; filters empties; decodes JSON objects with `vim.fn.json_decode` and collects only `type = 'match'` rows.
- Computes character columns safely from byte offsets (`vim.str_utfindex`) to handle multibyte text.
- Aggregates results into the structure consumed by the UI and sorts by file and line.

### Highlights (`highlight.lua`)

- Maintains two namespaces: all matches (`YasSecondary`) and focused match (`YasPrimary`).
- `highlight_search_results`: when a query is active, iterates loaded buffers and highlights literal occurrences of the query.
- `highlight_focus`: draws a high-priority highlight over the specific selected match.
- Auto-highlights new buffers for the current query via a small autocmd.

### Configuration (`config.lua`)

- Defaults merged with user options via `vim.tbl_deep_extend('force', defaults, user_opts)`.
- Key sections: window width/position, search flags, ignore patterns, highlight groups, keymaps.

### Commands and Usage (`plugin/yas.vim`)

- Commands: `:YasOpen`, `:YasClose`, `:YasToggle`, `:YasFocus`.
- Default mapping: `<C-S-f>` toggles the sidebar (can be disabled with `g:yas_default_mappings = 0`).
- Recommended setup:

```lua
require('yas').setup({
  width = 40,
  position = 'left',
  ignore_case = true,
  ignore_patterns = { '.git/', 'node_modules/' },
})
```

### Vim API Glossary (used by this plugin)

- `vim.api.nvim_create_buf(listed, scratch)`: create a buffer. We use scratch (`nofile`) buffers for the sidebar.
- `vim.api.nvim_create_autocmd(event, opts)`: attach callbacks to editor events like `InsertLeave`, `CursorMoved`, `WinResized`.
- `vim.api.nvim_create_augroup(name, { clear })`: group autocmds so they can be managed together.
- `vim.api.nvim_buf_set_lines(bufnr, start, end_, strict, lines)`: replace buffer contents.
- `vim.api.nvim_buf_set_keymap(bufnr, mode, lhs, rhs, opts)`: buffer-local mappings (here we use callback in opts; rhs is empty string).
- `vim.keymap.set(mode, lhs, rhs, { buffer, expr, silent })`: preferred modern API for keymaps; supports inline Lua callbacks.
- `vim.api.nvim_win_set_buf(win, buf)`, `vim.api.nvim_win_set_width(win, width)`, `vim.api.nvim_win_is_valid(win)`: window management APIs.
- `vim.api.nvim_buf_add_highlight(buf, ns, group, line, col_start, col_end)`: add a highlight to a line range.
- `vim.api.nvim_buf_set_extmark(buf, ns, row, col, opts)`: richer decorations with ranges and priority (used for focused highlight).
- `vim.fn.jobstart(cmdlist, { on_stdout, on_stderr, on_exit, stdout_buffered })`: spawn external processes (ripgrep).
- `vim.fn.json_decode(text)`: decode JSON; `pcall` wrapped for safety.
- `vim.str_utfindex(line, byte_index)`: convert UTF-8 byte offset to character index.
- `vim.fn.strchars(text)`: number of characters (codepoints) in a string.
- `vim.schedule(fn)`, `vim.defer_fn(fn, ms)`: schedule work in the main loop (avoid “textlock” issues during redraws).
- `vim.loop.new_timer()`: libuv timer for debouncing.

### Extension Points

- Replace or wrap `search.perform_search` for alternative backends.
- Customize rendering/highlights by editing `apply_result_highlights` and config highlight groups.
- Add actions: implement `remove_result()` or file-level operations via the existing `line_index` model.

### Notes on Multibyte Safety

- The UI truncates and positions using character counts, not bytes, to keep cursor placement correct for Unicode text. Key helpers: `strchars`, `strcharpart`, and `str_utfindex`.


