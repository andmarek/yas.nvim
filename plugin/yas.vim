" yas.nvim - VSCode-like finder plugin for Neovim
" Maintainer: Andy
" Version: 0.1.0

if exists('g:loaded_yas') || &compatible
  finish
endif
let g:loaded_yas = 1

" Plugin commands
command! YasOpen lua require('yas').open()
command! YasClose lua require('yas').close()
command! YasToggle lua require('yas').toggle()
command! YasFocus lua require('yas').focus()

" Default keybindings
if get(g:, 'yas_default_mappings', 1)
  nnoremap <silent> <C-S-f> :YasToggle<CR>
endif
