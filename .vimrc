set encoding=utf-8
set number
set linebreak
set showbreak=+++ 
set textwidth=92
set showmatch
set visualbell
" set spell
 
set hlsearch
set smartcase
set ignorecase
set incsearch
 
set autoindent
set shiftwidth=4
set smartindent	
set smarttab
set softtabstop=4

set ruler

set undolevels=1000
set backspace=indent,eol,start
set mouse=a

let &t_SI = "\e[6 q"
let &t_EI = "\e[2 q"

highlight clear SpellBad
highlight SpellBad cterm=underline
highlight LineNr ctermfg=blue

