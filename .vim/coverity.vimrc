" coverity.vimrc
" define commands for Coverity desktop analysis under vim

" Tested with vim 7.2 and 7.4 on linux.

" Run Coverity desktop analysis on current file.
"
" Invoke as ":Coverity".
"
" This command expects cov-run-desktop to be in the PATH.  It invokes
" that command using the current buffer's file name as an argument.
"
" cov-run-desktop, in turn, expects a coverity.conf file to be in the
" directory containing the current buffer's file, or in some ancestor
" directory.
"
" Then you can use :copen to see the error list, :cnext and :cprev
" to navigate, and :cclose to close the error list, among other
" commands.  Web search for "vim quickfix" for additional docs.
"
command Coverity call CoverityFunction()

" The function called by the command.
function! CoverityFunction()
  let filename = expand('%:p')
  if strlen(filename) == 0
    echo "Current buffer does not have a file name."
    return 0
  endif

  " Save current 'makeprg' and 'efm' values.
  let origmakeprg = &makeprg
  let origefm = &efm

  " Put the desired command as 'makeprg'.
  let &makeprg = "cov-run-desktop --disconnected --no-default-triage-filters --sort line --text-output-style=oneline \"" . filename . "\""

  " Error format to match "<file>:<line>: <message>".
  " The space after ":" is important to avoid matching "[STATUS]" lines
  " that happen to have a colon followed by a digit.
  let &efm = "%f:%l:%c:\\ %m"

  " Actually run the command, parsing its output as specified.
  make

  " Restore the variables to their original values.  This technique
  " for restoring variables does not seem completely safe to me, but
  " seems to be how the vim docs recommend to do it.
  let &makeprg = origmakeprg
  let &efm = origefm

  copen

endfunction

" EOF
