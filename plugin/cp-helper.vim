let g:cph = {
    \ "port"     : 1327,
    \ "timeout"  : 4,
    \ "dir"      : "/home/dhruv/.local/cp_helper.vim",
    \ "sol_dir"  : "/home/dhruv/cp",
    \ "template" : "/home/dhruv/cp/templates/template.min.cpp",
    \ "sol_lang" : "cpp"
    \ }

function! Cphelper()
    lua require("cp-helper").run_server()
endfun

function! Runtest()
    lua require("cp-helper").run_test()
endfun

function! Open_problem(problem_name)
    if a:problem_name != ""
        execute "lua require('cp-helper').open_problem('". a:problem_name."')"
    else
        execute "lua require('cp-helper').open_problem()"
    endif
endfun

if &filetype=='startify' || &filetype==''
    nnoremap <localleader>p :call Cphelper()<CR>
    nnoremap <localleader>[ :call Open_problem(0)<CR>
    nnoremap <localleader>; :call Runtest()<CR>
    nnoremap <localleader>s :lua require('cp-helper').open_submit_page()<CR>
    nnoremap <localleader>q :lua require('cp-helper').open_problem_page()<CR>
endif

