" Find longest line in a file or range (stolen - and slightly modified -
" from <http://lug.fh-swf.de/vim/vim-textfilter/vim-textfilter.html>).

map ll :call FindLongestLine('a')<CR>
map ln :call FindLongestLine('n')<CR>
vmap ll :call FindLongestLine('v')<CR>

function! FindLongestLine(mode)
  if a:mode == 'v'
    let firstline = line("'<")
    let lastline  = line("'>")
  else
    let firstline = a:mode == 'n' ? line('.') : 1
    let lastline  = line('$')
  endif
  let linenumber = firstline
  let longline   = firstline
  let maxlength  = 0
  while linenumber <= lastline
    exe ':'.linenumber
    let vc = virtcol('$')
    if maxlength == vc
      let equline = equline + 1
    endif
    if maxlength < vc
      let maxlength = vc
      let longline  = linenumber
      let equline   = 0
    endif
    let linenumber = linenumber + 1
  endwhile
  exe ':'.longline
  let maxlength = maxlength - 1
  redraw
  echohl Search  " highlight prompt
  echo 'range '.firstline.'-'.lastline.': longest line has number '.longline.', length '.maxlength
        \ .' ('.equline.' line(s) of equal length below)'
  echohl None    " reset highlighting
endfunction
