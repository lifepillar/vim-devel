vim9script

# Name:         Test 314
# Author:       me

set background=dark

hi clear
g:colors_name = 'test314'


hi Comment guifg=#ff8ad8 guibg=#ffffff guisp=NONE gui=italic ctermfg=238 ctermbg=231 ctermul=NONE cterm=bold term=bold,italic

if empty(&t_Co)
  finish
endif

if str2nr(&t_Co) >= 256
  finish
endif

if str2nr(&t_Co) >= 8
  hi Comment ctermfg=Grey ctermbg=White ctermul=NONE cterm=bold,italic
  finish
endif

# vim: et ts=8 sw=2 sts=2
