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

imap <C-f> <Right>
imap <C-a> <C-o>:call <SID>home()<CR>
imap <C-e> <End>
imap <C-d> <Del>
imap <C-h> <BS>
imap <C-k> <C-r>=<SID>kill_line()<CR>

" command line mode
cmap <C-p> <Up>
cmap <C-n> <Down>
cmap <C-b> <Left>
cmap <C-f> <Right>
cmap <C-a> <Home>
cmap <C-e> <End>
cnoremap <C-d> <Del>
cnoremap <C-h> <BS>
cnoremap <C-k> <C-f>D<C-c><C-c>:<Up>

