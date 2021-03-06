" MIT License. Copyright (c) 2013-2016 Bailey Ling et al.
" vim: et ts=2 sts=2 sw=2

scriptencoding utf-8

let s:has_fugitive = exists('*fugitive#head')
let s:has_lawrencium = exists('*lawrencium#statusline')
let s:has_vcscommand = get(g:, 'airline#extensions#branch#use_vcscommand', 0) && exists('*VCSCommandGetStatusLine')

if !s:has_fugitive && !s:has_lawrencium && !s:has_vcscommand
  finish
endif

let s:has_async = airline#util#async
let s:git_dirs = {}

let s:head_format = get(g:, 'airline#extensions#branch#format', 0)
if s:head_format == 1
  function! s:format_name(name)
    return fnamemodify(a:name, ':t')
  endfunction
elseif s:head_format == 2
  function! s:format_name(name)
    return pathshorten(a:name)
  endfunction
elseif type(s:head_format) == type('')
  function! s:format_name(name)
    return call(s:head_format, [a:name])
  endfunction
else
  function! s:format_name(name)
    return a:name
  endfunction
endif

function! s:get_git_branch(path)
  if !s:has_fugitive
    return ''
  endif

  let name = fugitive#head(7)
  if empty(name)
    if has_key(s:git_dirs, a:path)
      return s:git_dirs[a:path]
    endif

    let dir = fugitive#extract_git_dir(a:path)
    if empty(dir)
      let name = ''
    else
      try
        let line = join(readfile(dir . '/HEAD'))
        if strpart(line, 0, 16) == 'ref: refs/heads/'
          let name = strpart(line, 16)
        else
          " raw commit hash
          let name = strpart(line, 0, 7)
        endif
      catch
        let name = ''
      endtry
    endif
  endif

  let s:git_dirs[a:path] = name
  return name
endfunction

" 'untracked' - dictionary with files as keys. A file has a not exists symbol
"               set as its value if it is untracked.
"               untracked_mark is taken as regex!
let s:vcs_config = {
\  'git': {
\    'exe': 'git',
\    'cmd': 'git status --porcelain -- ',
\    'untracked_mark': '??',
\    'get_branch': 's:get_git_branch',
\    'untracked': {},
\  },
\  'mercurial': {
\    'exe': 'hg',
\    'cmd': 'hg status -u -- ',
\    'untracked_mark': '?',
\    'get_branch': 's:get_hg_branch',
\    'untracked': {},
\  },
\}

function! s:get_untracked(file, config)
  " Assigns the notexists symbol to 'file's entry in the untracked cache if
  " 'file' is indeed untracked by current VCS.
  " 'config' is this script's configuration of the VCS.
  if empty(a:file) || !executable(a:config['exe'])
    return
  endif

  if s:has_async
    call s:get_vcs_untracked_async(a:config, a:file)
  else
    let output = system(a:config['cmd'] . shellescape(a:file))
    if output =~? ('^' . a:config['untracked_mark'])
      let a:config['untracked'][a:file] = get(g:, 'airline#extensions#branch#notexists', g:airline_symbols.notexists)
    else
      let a:config['untracked'][a:file] = ''
    endif
  endif
endfunction

function! s:get_hg_branch(path)
  if s:has_lawrencium
    let stl=lawrencium#statusline()
    if !empty(stl) && s:has_async
      call s:get_mq_async('hg qtop', expand('%:p'))
    endif
    if exists("s:mq") && !empty(s:mq)
      if stl is# 'default'
        " Shorten default a bit
        let stl='def'
      endif
      let stl.=' ['.s:mq.']'
    endif
    return stl
  endif
  return ''
endfunction

if s:has_async
  let s:jobs = {}

  function! s:on_stdout(channel, msg) dict abort
    let self.buf .= a:msg
  endfunction

  function! s:on_exit(channel) dict abort
    if self.buf =~? ('^' . self.config['untracked_mark'])
      let self.config['untracked'][self.file] = get(g:, 'airline#extensions#branch#notexists', g:airline_symbols.notexists)
    else
      let self.config['untracked'][self.file] = ''
    endif
    if has_key(s:jobs, self.file)
      call remove(s:jobs, self.file)
    endif
  endfunction

  function! s:get_vcs_untracked_async(config, file)
    if g:airline#util#is_windows && &shell =~ 'cmd'
      let cmd = a:config['cmd'] . shellescape(a:file)
    else
      let cmd = ['sh', '-c', a:config['cmd'] . shellescape(a:file)]
    endif
    let cmdstring = split(a:cmd)[0]

    let options = {'config': a:config, 'buf': '', 'file': a:file}
    if has_key(s:jobs, a:file)
      if job_status(get(s:jobs, a:file)) == 'run'
        return
      elseif has_key(s:jobs, a:file)
        call remove(s:jobs, a:file)
      endif
    endif
    let id = job_start(cmd, {
          \ 'err_io':   'out',
          \ 'out_cb':   function('s:on_stdout', options),
          \ 'close_cb': function('s:on_exit', options)})
    let s:jobs[a:file] = id
  endfu

  function! s:on_exit_mq(channel) dict abort
    if !empty(self.buf)
      if self.buf is# 'no patches applied' ||
        \ self.buf =~# "unknown command 'qtop'"
        let self.buf = ''
      elseif exists("s:mq") && s:mq isnot# self.buf
        " make sure, statusline is updated
        unlet! b:airline_head
      endif
      let s:mq = self.buf
    endif
    if has_key(s:jobs, self.file)
      call remove(s:jobs, self.file)
    endif
  endfunction

  function! s:get_mq_async(cmd, file)
    if g:airline#util#is_windows && &shell =~ 'cmd'
      let cmd = a:cmd. shellescape(a:file)
    else
      let cmd = ['sh', '-c', a:cmd]
    endif

    let options = {'cmd': a:cmd, 'buf': '', 'file': a:file}
    if has_key(s:jobs, a:file)
      if job_status(get(s:jobs, a:file)) == 'run'
        return
      elseif has_key(s:jobs, a:file)
        call remove(s:jobs, a:file)
      endif
    endif
    let id = job_start(cmd, {
          \ 'err_io':   'out',
          \ 'out_cb':   function('s:on_stdout', options),
          \ 'close_cb': function('s:on_exit_mq', options)})
    let s:jobs[a:file] = id
  endfu
endif

function! airline#extensions#branch#head()
  if exists('b:airline_head') && !empty(b:airline_head)
    return b:airline_head
  endif

  let b:airline_head = ''
  let l:vcs_priority = get(g:, "airline#extensions#branch#vcs_priority", ["git", "mercurial"])
  let found_fugitive_head = 0
  let l:heads = {}

  for vcs in l:vcs_priority
    let l:path = exists("*fnamemodify") ? fnamemodify(resolve(@%), ":p:h") : expand("%:p:h")
    let l:head = {s:vcs_config[vcs].get_branch}(l:path)
    if !empty(l:head)
      let l:heads[vcs] = l:head
    endif
  endfor

  let l:file = expand("%:p")
  " Do not get untracked flag if we are modifying a directory.
  let l:is_file_and_not_dir = !isdirectory(l:file)
  for vcs in keys(l:heads)
    if !empty(b:airline_head)
      let b:airline_head .= ' | '
    endif
  endfor

  if !empty(l:hg_head)
    let l:heads.mercurial = (!empty(l:git_head) ? "hg:" : '') . s:format_name(l:hg_head)
    if l:is_file_and_not_dir
      call s:get_hg_untracked(l:file)
      let l:heads.mercurial.= get(s:untracked_hg, l:file, '')
    endif
  endif

  if empty(l:heads)
    if s:has_vcscommand
      call VCSCommandEnableBufferSetup()
      if exists('b:VCSCommandBufferInfo')
        let b:airline_head = s:format_name(get(b:VCSCommandBufferInfo, 0, ''))
      endif
    endif
  endif

  if exists("g:airline#extensions#branch#displayed_head_limit")
    let w:displayed_head_limit = g:airline#extensions#branch#displayed_head_limit
    if len(b:airline_head) > w:displayed_head_limit - 1
      let b:airline_head = b:airline_head[0:(w:displayed_head_limit - 1)].(&encoding ==? 'utf-8' ?  '…' : '.')
    endif
  endif

  if has_key(l:heads, 'git') && !s:check_in_path()
    let b:airline_head = ''
  endif
  let minwidth = empty(get(b:, 'airline_hunks', '')) ? 14 : 7
  let b:airline_head = airline#util#shorten(b:airline_head, 120, minwidth)
  return b:airline_head
endfunction

function! airline#extensions#branch#get_head()
  let head = airline#extensions#branch#head()
  let empty_message = get(g:, 'airline#extensions#branch#empty_message', '')
  let symbol = get(g:, 'airline#extensions#branch#symbol', g:airline_symbols.branch)
  return empty(head)
        \ ? empty_message
        \ : printf('%s%s', empty(symbol) ? '' : symbol.(g:airline_symbols.space), head)
endfunction

function! s:check_in_path()
  if !exists('b:airline_branch_path')
    let root = get(b:, 'git_dir', get(b:, 'mercurial_dir', ''))
    let bufferpath = resolve(fnamemodify(expand('%'), ':p'))

    if !filereadable(root) "not a file
      " if .git is a directory, it's the old submodule format
      if match(root, '\.git$') >= 0
        let root = expand(fnamemodify(root, ':h'))
      else
        " else it's the newer format, and we need to guesstimate
        let pattern = '\.git\(\\\|\/\)modules\(\\\|\/\)'
        if match(root, pattern) >= 0
          let root = substitute(root, pattern, '', '')
        endif
      endif
    endif

    let b:airline_file_in_root = stridx(bufferpath, root) > -1
  endif
  return b:airline_file_in_root
endfunction

function! s:reset_untracked_cache(shellcmdpost)
  " shellcmdpost - whether function was called as a result of ShellCmdPost hook
  if !s:has_async
    if a:shellcmdpost
      " Clear cache only if there was no error or the script uses an
      " asynchronous interface. Otherwise, cache clearing would overwrite
      " v:shell_error with a system() call inside get_*_untracked.
      if v:shell_error
        return
      endif
    endif
  endif
  for vcs in ["git", "mercurial"]
    let s:vcs_config[vcs]['untracked'] = {}
  endfor
endfunction

function! airline#extensions#branch#init(ext)
  call airline#parts#define_function('branch', 'airline#extensions#branch#get_head')

  autocmd BufReadPost * unlet! b:airline_file_in_root
  autocmd CursorHold,ShellCmdPost,CmdwinLeave * unlet! b:airline_head
  autocmd User AirlineBeforeRefresh unlet! b:airline_head
  autocmd BufWritePost * call s:reset_untracked_cache(0)
  autocmd ShellCmdPost * call s:reset_untracked_cache(1)
endfunction
