vim9script

# Name:        StylePicker
# Author:      Lifepillar <lifepillar@lifepillar.me>
# Maintainer:  Lifepillar <lifepillar@lifepillar.me>
# License:     MIT

import autoload '../autoload/stylepicker.vim' as stylepicker

command! -nargs=? -bar -complete=highlight StylePicker stylepicker.Open(<q-args>)
