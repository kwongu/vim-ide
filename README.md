# Vim IDE
colorscheme : jellybeans

## Download
git clone --depth 1 --recurse-submodules https://github.com/kwongu/vim-ide.git ${HOME}/.vim-ide

## Installation
cd ${HOME}/.vim-ide <br/>
./install.sh

`install.sh` also installs the tools the IDE needs, skipping whatever is
already there: vim, cscope, GNU Global (gtags) and **Universal Ctags**
(tagbar's symbol list comes from ctags, and Exuberant Ctags 5.8 misses
C11 anonymous structs and newer kinds). On macOS it uses
`brew install universal-ctags` (unlinking the old `ctags` formula first,
since both provide `bin/ctags`); on Linux it uses the distribution's
Universal Ctags when present, otherwise it builds it into `${HOME}/.local`.
Ubuntu without build tools: `sudo apt-get install -y universal-ctags`.

If `nvim` is installed, `install.sh` also sets up Neovim: it downloads
vim-plug, writes `~/.config/nvim/init.vim` (which just sources this
`.vimrc`) when there is none, installs the plugins with `:PlugInstall` and
builds the treesitter parsers. Existing files are left alone, so re-running
it is safe.

## Setup vim env
echo '' >> ${HOME}/.profile <br/>
echo '### Setup vim env - start ###' >> ${HOME}/.profile <br/>
echo 'alias vim="${HOME}/.local/bin/vim"' >> ${HOME}/.profile <br/>
echo 'alias vi="${HOME}/.local/bin/vim"' >> ${HOME}/.profile <br/>
echo '### Setup vim env - end ###' >> ${HOME}/.profile <br/>
echo '' >> ${HOME}/.profile <br/>
 
## Feature

* Git wrapper: works with Git without leaving Vim IDE.

* Auto pairs: Provides several pairs of bracket maps. Ex) [] or () ...

* Auto comment: comments the ranged lines or uncomments

* Statusbar at the bottom: displays useful information.

* Marker: highlights several words in different colors simultaneously

* Source tab at the top: displays all opened source via tab interface.

* BufExplorer at the top: displays all opened source via file lists 

* Global source code tagging system: finds the locations of symbols such as functions, macros, structs and classes in your source code and moves there easily.

* Grep: finds the locations of symbols such as functions, macros, structs and classes in your source code and displays all searched source at the down

* Auto completion: opens a popup menu to complete using tab. In a buffer over
  `g:vimide_acp_max_lines` lines (5000; `0` = no limit) the popup no longer
  opens by itself while typing - `<Tab>`/`^N` still complete

* File system explorer: browses directory hierarchies, and performs file system operations

* Source code browser: provides an overview of the structure of the source code. Moving the cursor onto a symbol in the tagbar window - with j/k, the arrows or a single mouse click - takes the edit window to that symbol while the focus stays in tagbar (set g:tagbar_follow_cursor = 0 to turn it off).

* Git status check: uses signs to indicate added, modified and removed lines based on data of an underlying version control system.

* Smooth scrolling: moves smoothly the screen when exploring source code.

* `./install.sh` checks what it needs before it installs anything, and checks *versions*, not just presence. Asking `command -v git` lets git 2.25.1 through, and diffview wants 2.31 - which is how `<leader>v` came to do nothing at all with no error to read. `tools/deps.sh --check` runs the same pass on its own and `--list` says what each tool is for:

```
  tool       now        need     state
  git        2.25.1     2.31+    OLD (must)
  global     -          6.6+     MISS (must)
  ctags      0.0.0      5.9+     ok (Universal Ctags)
```

  It fills gaps the way the machine allows: `brew` on macOS; `apt` on Debian/Ubuntu **only if sudo needs no password**, and otherwise into `$HOME/.local` alone, because the dev server is shared by 800+ people and an unattended `sudo` there is not mine to run; anywhere else it just prints the command to type. Git has a home-directory route (extracting the git-core PPA `.deb`, with a wrapper for `GIT_EXEC_PATH` - the Debian build hardcodes `/usr/lib/git-core` and would otherwise drive the old helpers). Universal Ctags built from a snapshot calls itself `0.0.0`, so ctags is judged by what it says it *is*, not by the number. tmux (3.2 or newer, for `extended-keys` - it is what lets `Ctrl+'` reach nvim inside tmux) has one too: Ubuntu 20.04's apt only has 3.0a, so without sudo, or when apt's version is too old, it builds the **latest tmux release** from the official tarball into `$HOME/.local/tmux-<version>` and puts a small wrapper at `~/.local/bin/tmux`, with libevent built statically beside it when the machine has no libevent headers (the dev server has none), so nothing extra is needed at run time. On macOS it is `brew install`/`brew upgrade tmux`. `VIMIDE_TMUX_VERSION=3.5a` pins a version instead of the latest. A tmux server that is already running stays the old version, and a new client cannot attach to it (`server version is too old for client` - with exit status 0, so `has-session` cannot tell). The wrapper checks for exactly that message on the socket you picked (default, `-L` or `-S`) and hands the call to the old client while the old server lives, so `tmux -2 a` keeps working; once you close that server (`tmux kill-server`), the next `tmux` starts the new one. The repository's `.tmux.conf` sets `extended-keys on` (not `always`, which sends extended keys to the shell too and breaks bash input) with `-q`, so an old tmux reads it without errors. `VIMIDE_DEPS=0 ./install.sh` skips installing, `VIMIDE_DEPS_SUDO=0` never tries sudo.

* Magit-style git UI (nvim only): `Neogit` opens the whole staging/commit/push workflow in a tab (`<leader>s`), with `diffview.nvim` for side-by-side diffs and 3-way merges (`<leader>v`) - both for the repository of the file or tree row in front of you, not nvim's working directory (see "Which repository" below) - and `gitsigns.nvim` for the gutter of the buffer you are editing - `<leader>ha` stages the hunk under the cursor (or, from visual mode, just the lines you selected), `<leader>hr` reverts it, `<leader>hu` unstages, `<leader>hv` previews it, `<leader>ht` toggles the blame of the current line, and `]h`/`[h` walk the hunks. That is partial staging without leaving the file, which is the half of Magit a status window cannot give you. The gutter is gitsigns' in nvim and `vim-signify`'s in real vim 8.1 (the dev server); running both draws the same column twice, so nvim turns signify off (`g:vimide_signify_in_nvim = 1` puts it back). Line blame is **off by default**: it runs `git blame` on the file every time the cursor rests, and this setup lives on 60k-file kernel trees, some of them over SMB - `<leader>ht` turns it on when you want it, `g:gitsigns_blame_on = 1` from the start.
  Measured, because it gets asked: the git stack is not what costs you time.
  Opening 20 files in the kernel tree takes 419 ms with everything on, 406 ms
  with gitsigns off (13 ms, 3%), and 31 ms with no config at all - so the git
  plugins are 3% of a cost that is mostly everything else. Startup is
  identical with and without them: neogit and diffview only load when you run
  their commands, and gitsigns attaches to a buffer asynchronously, off the
  path that opens the file. When this setup did feel slow it was never these -
  it was startup errors and an over-long message parking vim on `Press ENTER`.

  Inside the diff, `Ctrl+n` and `Ctrl+p` step through the changes - the same
  thing `]c` and `[c` do, on the keys the relation list already uses for
  next/previous, so the hand does not have to switch. They are bound on
  diffview's buffers only, so outside the diff those keys still walk the
  relation list; in the file panel they move to the next and previous file's
  diff. `<leader>v` inside a diffview tab closes that view; anywhere else it
  goes to the tab already showing that repository's working-tree diff
  (diffview refreshes it on the way in), or opens one, so two repositories
  can each have a diff tab of their own. When the starting point is a file,
  the diff opens with that file selected. Views opened some other way - a
  commit range (`:DiffviewOpen HEAD~1..HEAD`), `--cached`, a path filter
  (`-- x.c`), Neogit's `d` popup - are left alone even for the same
  repository: they show something else, and while one was open
  `<leader>v` used to jump there, so the working-tree diff could only be had
  by closing it first. It used to mean "close whatever view is open", but
  `:DiffviewClose` only closes the view of the current tab, so pressed from
  any other tab it closed nothing. Inside the view, `q`
  closes too - diffview binds `q` only in its option and help panels, so in
  the file panel and the diff windows it did nothing at all (it started
  recording a macro), while every other panel in this setup closes with `q`.
  Diffview needs git 2.31 or newer: on the dev server (2.25.1) `:DiffviewOpen`
  used to print `Not a repo (or any parent)` and do nothing, which reads as
  "this is not a repository" when the real answer is "this git is too old", so
  `<leader>v` now says that instead. Neogit and gitsigns work on the old git.

  The file panel is 35 columns, which cuts off a kernel path long before the
  file name, so `w` in it widens it a step at a time and then snaps back -
  the same key and the same feel as `w` in the F9 tree and the relation
  panel. The steps are percentages of the screen (`g:diffview_wide_steps`,
  `[25, 40]`); a step that would not make the panel wider than it is is
  skipped (25% of a 120-column screen is 30 columns, narrower than 35), so
  `w` only ever widens. "Than it is" means its real width: after one `w`, a
  panel then widened by hand to 120 columns used to be cut to the next
  step's 80; now no step is wider, so that press is the snap-back, as after
  the last step (with no `w` before it, the press leaves the panel alone).
  Only the diff windows pay for it, in equal shares (81 and 82 columns become
  74 and 74), and nothing else in the tab moves: a `:vertical help`, a
  `:vsplit` or a terminal beside them, neo-tree and the relation column keep
  their width through every step, and the snap-back gives the diff windows
  the widths they had before the first `w` (if diffview rebuilt them in
  between, e.g. on a move to a conflict file, they share what comes back
  equally). Left alone, nvim takes the columns from the window next to the
  panel only, and a 200-column screen ends up with diff windows of 36 and
  82; `wincmd =` evened out heights too (a `:help` split sized to 10 lines
  above a diff became 23), and `horizontal wincmd =` evened out every window
  in the tab (a `:vertical help` sized to 30 columns became 49, and 54 after
  the snap-back) - the panel and the side columns only escaped because they
  are fixed-width. The relation panel's `w` avoids `wincmd =` for the same
  reason. (diffview itself still evens out the whole tab when it rebuilds
  the layout or reopens the panel with `<leader>b`; it did that before, and
  `w` does not undo it.) Each diff window keeps at least 20
  columns (5 lines in the history panel), the floor the relation panel's `w`
  leaves the edit area. It is measured, not computed: the panel is widened,
  the diff windows beside it are measured, and the panel gives back what
  they lack. The old limit was the screen width minus 20, which counted
  neither the tab line, status lines and command line nor other side panels
  in the tab - with neo-tree and the relation column beside the diff, the
  second `w` left two diff windows of 2 columns each, and on a 24-line
  screen the history panel's first `w` left 2 lines. In
  `:DiffviewFileHistory` the panel lies along the bottom, so there `w` grows
  its height (`g:diffview_wide_height_steps`, `[50, 75]`, the steps the
  relation panel uses in its bottom layout: 25% would be smaller than the
  panel's 16 lines on a 50-line screen); there only the row of diff windows
  gives up height - they sit side by side and lose it together - while a
  split you made above a diff window and anything below the panel keep
  their height, so such a split can also stop the panel from growing
  (before, only the panel was resized and nvim took the lines from below it
  first: a 6-line window there went to 1, 22 and 13 lines on successive
  presses, and an 8-line split above a diff window ended at 5). The
  width you chose stays while you
  move between files (`Tab`, `Ctrl+n`), refresh (`R`), switch tabs or hide
  and show the panel (`<leader>b`), until `w` brings it back or the view is
  closed, and each diffview tab keeps its own. That last part needed work:
  diffview sets the panel back to the configured 35 columns every time it
  opens it - `<leader>b`, or a switch between a two-way and a three-way
  (conflict) file - reading the size from its config each time, so while a
  panel is widened its own config reader hands back the wider size; other
  views and diffview's global config are untouched. That size is fitted to
  the screen of the moment: an 80-column panel widened on a 200-column
  screen and reopened after the terminal shrank to 110 used to come back at
  80 and squeeze the diff windows to 8 and 20 columns; now it comes back as
  wide as leaves each diff window 20 columns (68 there), and at 80 again once
  the screen is wide again. Inside the diff windows `w` is still the word
  motion.

  The same `Ctrl+n` / `Ctrl+p` walk the hunks in Neogit's commit view (`Enter`
  on a commit in the log or the status screen) and in the "Staged Changes"
  diff Neogit shows beside the message while you commit (`c c`). Both are
  plain unified diffs, where `]c` means nothing. The cursor lands on the hunk
  header (`@@ -12,7 +12,7 @@ func`) - the one line that says where the change
  is, the line the hunk reads down from, and where Neogit's own `{` `}` stop
  too. The walk crosses from file to file, stays put at the last and the
  first hunk (no wrap and no message, as in the diff), takes a count
  (`3 Ctrl+n`), and from the middle of a hunk `Ctrl+p` goes to that hunk's
  header, as `[c` does. If the hunk runs past the bottom of the window its
  header is scrolled to the top; if it fits, the screen stays where it is.
  Files folded away with `Tab` are skipped, the way Magit's `n`/`p` skip a
  collapsed section. Lines of the commit message never count, even when they
  look like a hunk header - kernel commit messages carry Coccinelle rules
  (`@@` lines) and quoted diffs. `{` and `}` are still there; they also stop
  on the file header lines and always scroll. Neogit's `d` popup opens
  diffview, not a Neogit buffer, so there `Ctrl+n`/`Ctrl+p` are diffview's.
  In the status screen they stay Neogit's next/previous section, and
  everywhere else they still walk the relation list. The code is
  `~/.vim/plugin/gitviewkeys.lua`.

  Which repository. `<leader>s` and `<leader>v` used to open the repository
  of nvim's working directory, so with a file of another repository in front
  of you - the kernel inside an SDK, a project nested in another, a
  submodule - you got the wrong status screen and had to `:cd` first. Now
  they start from what you are looking at:
  - in neo-tree (F9, the F11 float, the RelationView tree - the filesystem,
    buffers and git_status sources alike) the row under the cursor: a
    directory row is that directory, a file row that file. A row whose path
    is gone (a deleted file in git_status) uses the nearest directory that
    still exists; a row with no path (hint lines, a terminal in the buffers
    list) uses the tree's root.
  - in an edit window, the file being edited. A new file not saved yet uses
    its nearest existing directory, an unnamed buffer nvim's working
    directory, as before. Git's own message and todo files -
    `COMMIT_EDITMSG`, `MERGE_MSG`, `TAG_EDITMSG`, `git-rebase-todo`, which
    is what Neogit's commit editor (`c c`) shows - count as the work tree of
    the `.git` they sit in (a `git worktree add` checkout and a submodule
    included), so from the commit message `<leader>s` goes back to the
    status screen and `<leader>v` opens the diff, as `:Neogit` did before.
  - in any other window - quickfix, aerial, tagbar, help, a terminal, the
    RelationView panel and preview, the DirDiff tree, telescope - the file in
    this tab's edit window, because what those windows show is a list, not a
    file. With no edit window, the working directory.
  - in a Neogit buffer, that buffer's repository: the window's own
    directory, which Neogit sets on the status window and its log, refs and
    commit views inherit (`<leader>s` in the status screen refreshes it).
    Neogit's own idea of the current repository is only the fallback, since
    it moves the moment another repository's status opens. In a diffview
    tab, that view's repository.

  From there git is asked for the top level (`git -C <dir> rev-parse
  --show-toplevel`) - the question Neogit and diffview ask themselves, so the
  answer cannot disagree with them - and the innermost work tree wins: a
  repository nested inside another (not a submodule), a submodule and a
  `git worktree add` checkout each open as themselves. Symlinks are followed
  to the real file first: git resolves a symlinked directory by itself, but
  asked from the directory a symlinked file sits in, it answers with the
  repository of the link. Outside a work tree, or inside `.git/` (other than
  the message files above), you get one line naming the path and nothing
  opens - handed to Neogit, that path would get an `Initialize repository in
  ...?` prompt, one `y` away from a stray `git init`. If git does not answer
  within 10 seconds - a stalled SMB or network mount - the line says that
  instead of blaming the path.

  Neogit keeps a single status screen. Its buffer is always named
  `NeogitStatus`, and every git command it runs goes to the last repository
  it opened - so a second status screen would take over the first one's
  buffer, and staging from the older screen would stage in the newer
  repository. `<leader>s` for another repository therefore closes the open
  status screen first (the way `q` does, which keeps its folds for the next
  time) and opens the new one; for the same repository it goes to that tab
  and refreshes. If the status screen's tab also holds other windows - a
  file you `:vsplit` beside it - only the status window is closed: `q` there
  is a `:tabclose`, which took those windows with it, the one you pressed
  the key in included (a modified buffer was left hidden). The same goes
  for the old repository's other Neogit views - log, reflog, refs, stash,
  commit view, the git command history, a popup
  left open in one of them: they are closed too, because their commands also
  run in the last repository opened. Left behind, `Enter` on a commit in the
  old log ran `git show` in the new repository and stopped at `Failed to
  parse line` and a Press ENTER, and in a worktree that shares commits with
  the new repository, `b` and `X` there would quietly check out or reset the
  new one. Neogit's own diffs from its `d` popup - `d s`, `d u`, `d d` on
  the staged or unstaged changes - are closed for the same reason: that view
  reads its file list and contents from Neogit's last repository, so
  entering its tab refilled it with the new repository's files, while its
  `-` still staged in the old one (it put the new repository's file into the
  old repository's index). Diffviews that hold their own repository stay:
  `<leader>v`, `:DiffviewOpen`, `:DiffviewFileHistory`, and Neogit's `d w`,
  `d r`, commit and stash diffs all run git in the top level they were
  opened with, whichever repository Neogit moves to. Before, switching
  repositories took a `:cd`; now one key on a tree
  row does it, so those leftovers would be the common case. The one thing
  that stops the switch is a message you are writing through Neogit for the
  old repository (a commit, merge or tag message, a rebase todo): nothing is
  closed, one line says so, and you finish or abort it first. Which
  repository each of those open screens belongs to is decided without
  asking git: Neogit already knows it for the status screen it opened, the
  other views inherit that screen's directory, and otherwise the path
  decides (the same directory is the same repository, a directory outside
  it is another one, and inside it a `.git` on the way up means a nested
  repository). git is asked about the repository you are opening only.
  Before, it asked git about every open screen, so a status screen of a
  repository on a stalled mount made `<leader>s` for a healthy one freeze
  for 10 seconds with no message (20 with a message being written there).

  Both open their tab from the edit window. diffview and Neogit build the
  new tab as a copy of the current window (`:tab split`, `:tab sb`), window
  options included, so pressed in a side window they carried that window
  along. From the RelationView panel its `winfixbuf` came too: the second
  `<leader>v` failed with E1513 and a Press ENTER and left a diff tab
  showing the panel's list, and Neogit's status screen took the panel's
  line highlight, where `Enter` on a file then opened nothing. From the tree
  the diff windows came up without line numbers. Now a side window first
  hands over to this tab's edit window (as the F11 float already did) and
  the tab opens from there. Coming back to this tab you are in the edit
  window - on purpose: Neogit's `Enter` and diffview's `gf` open the file in
  whatever window that tab was left in, and in the panel they could not. In
  a tab with no edit window (help only, say) they open where you are, with
  `winfixbuf` off for that moment, and inside a diffview tab - all of its
  windows are diffview's, and they pass nothing on - nothing moves, as
  before.

  diffview has
  no such limit, hence one tab per repository there. diffview runs the
  `-C <dir>` it is given through `expand()`, which
  honours `'wildignore'` - and this setup's `*/tmp/*` turns any path with a
  `tmp` directory in it (Yocto's `build/tmp`) into an empty string, which
  would open the working directory's repository instead. The call clears
  `'wildignore'` for that moment and backslash-escapes the path (spaces, `$`,
  brackets, quotes). The code is `~/.vim/plugin/gitrepo.lua`.

* Symbol outline (nvim only): `aerial.nvim` lists the current file's symbols in a side window (F10 or `<leader>o`, and only when you press it), built on treesitter so it needs no language server. `:Tagbar` stays as it was.

* Automatic symbol index (nvim only): both indexes maintain themselves. `vim-gutentags` keeps the ctags `tags` file current and `~/.vim/plugin/autoindex.lua` does the same for GTAGS, so RelationView, `:Gtags` and `<leader>fs` are always in sync without pressing F2. **Starting nvim refreshes the index of the project in front of you in the background** - an incremental `gtags -i` when it exists (2s on a 69k-file kernel tree), a full build when it does not (26s there) - and saving a file updates that one file in milliseconds. `:GtagsIndex` rebuilds, `:GtagsIndexRefresh` updates incrementally, `:GtagsIndexUpdate` does the current file and `:GtagsIndexStatus` says what is running. **`Ctrl+]`, `:tag` and `g]` are answered from GTAGS** through nvim's `'tagfunc'`, so a jump works the moment a file is saved (8 ms on a 69k-file kernel tree) and needs no ctags file at all; when gtags has nothing to say, the normal tags-file lookup still runs, and an LSP client that sets its own `'tagfunc'` per buffer still wins there. Which files get indexed is decided in one place - `~/.local/bin/indexfiles.sh`: a project's own `.indexfiles`, else `git ls-files` (tracked and new files, honouring `.gitignore`), else `cscope.files` (what F2 writes), else a find over the source extensions. Drop an `.indexfiles` in a project root to index exactly the files you care about. `cscope.files` ranks below git on purpose: an F2 run that is interrupted leaves a partial list behind, and rebuilding from it drops every symbol outside it. For the same reason a rebuild that would cover less than half of what the current index covers asks first (`:GtagsIndex`) or is skipped (automatic), and every build reports how many files it indexed.
* Where the index lives: `GTAGS`, `GRTAGS` and `GPATH` go into a hidden **`.tags/` directory in the project root**, so nothing visible is dropped into the source tree, and a database still sitting at a project root (what F2 used to write) is moved there the first time the project is opened. GNU global only looks inside such a directory when `GTAGSOBJDIR` names it, so `.vimrc` exports `GTAGSOBJDIR=.tags` once - one value that works in every project, in every subdirectory, and still finds an old root-level database. In a terminal: `eval "$(gtagsenv.sh)"`, or put `export GTAGSOBJDIR=.tags` in `~/.zshenv`. The directory is added to `.git/info/exclude` (local, never committed) so it stays out of `git status`. `let g:autoindex_dbdir = ''` puts the database back in the project root.
* Which directory is the project: the nearest directory above the file that already has an index (`.tags/GTAGS`, or an old root-level `GTAGS`); failing that, the nearest one holding `.git`, `.repo`, `.project` or `.root`. `.repo` is there for SDKs checked out with `repo`: their root has `.repo` but no `.git` (each sub-project such as `kernel/common` has its own `.git`), so without it the first launch in a new SDK walked past the SDK and stopped at whatever `.git` lay above. On the dev server that was an empty `git init` in the directory holding several SDKs - about 5 million files, a 35-second `find` from a cold cache - and every first launch started listing and indexing all of it. Nearest wins, so inside a sub-project with its own `.git` nothing changes, and an SDK that already has an index is found by the first rule.
* Trees larger than `g:autoindex_ctags_max_files` (5000) get their **ctags file built by `autoindex.lua` instead of gutentags**, once per project in the background (0.9 GB / 47 s for a 69k-file kernel tree) and never on save - gutentags rewrites the entire tags file whenever a file in the project is saved, which costs seconds at that size. It is refreshed when older than `g:autoindex_ctags_max_age` days (7), rebuilt by `:CtagsIndex`, and switched off with `g:autoindex_ctags = 0`. `g:autoindex_ctags_args` chooses the flags: the default `--fields=+n --excmd=number` trades search patterns for line numbers (~30% smaller); drop `--excmd=number` to keep patterns, which survive edits made outside nvim. `:GtagsIndex`, `:GtagsIndexUpdate` and `:GtagsIndexStatus` drive gtags by hand; `:GtagsIndex`, `:GtagsIndexUpdate` and `:GtagsIndexStatus` drive it by hand.

* Modern file tree (nvim only): `neo-tree.nvim` (F9, or `<leader>t`) shows git status inline and creates/deletes/renames with `a`/`d`/`r`. F11 opens the same tree as a float.

* Project files (nvim only): `<leader>fo` finds and opens a file from what is indexed (a telescope picker; `^d` or `Esc` `d` drops it - or every `<Tab>`-marked one - from the list and the picker stays open), and files go in from the tree (`+`). Two modes: **auto** - the whole project, as before - and **preset**, where only the files and directories you picked are indexed. Adding a file brings the headers it includes and the files defining the symbols it uses along with it, and the index follows immediately; presets are named, reusable across checkouts, shipped with vim-ide itself so every machine has them, and one can be made the startup default. See "Project files and presets" below.
* Relation window (nvim only): Source Insight style panel across the bottom of the screen, with the context preview in a column of its own down the right side, showing the definition and an expandable multi-depth caller tree of the symbol under the cursor in real time. The tree can be expanded per node or all at once, and exported as an HTML call graph. It uses the same GTAGS database created with F2. It opens automatically on startup; toggle with F12 (it was F3, which now opens `\fo`).


## Usage (shortcut)

This section describes mapping keys for Vim IDE.

```
F1: Shortcut help - every key vim-ide has, in one telescope list you can
     search: this list, the key tables of the other sections, every mapping
     that is set right now and vim-ide's commands, with a preview of the
     README text or the line that set the mapping (nvim, `:VimIdeKeys`). It
     is gathered from this README and the live mappings each time it opens,
     so a key shows up as soon as it is mapped or written down here - see
     "Shortcut help (F1)" below. It works in insert and visual mode too,
     and inside every telescope list, where that list's own keys come
     first. In vim 8.1 it shows this list in a read-only tab
\K: Show a man page for the keyword under the cursor. This was F1; vim's own
     `K` does it too, but `K` resizes windows here (Shift+k, below)
F2: Source files under the current path are indexed; `cscope.files` is written to the project root and the GPATH/GRTAGS/GTAGS database into `<root>/.tags/` (`:call Deltags()` removes both). With automatic indexing this is rarely needed.
F3: Find an indexed file and open it, the same as `\fo` (nvim only). RelationView moved to F12
F4: Mark the keyword under the cursor, the keyword is highlighted in different colors
F5: Clear all marks
The quickfix list and the relation panel both say whether a file is in the
index and let you change it on the spot - `+` adds the file on the cursor
line (or every file in the visual selection), `-` drops it, `=` says where it
stands, and a file that is in the list carries a red `●` at the end of its
line. This is the same set of keys NERDTree, neo-tree, netrw and BufExplorer
already had, for the same reason: the files a `:Gtags` or `Ctrl+g` result
just put in front of you are exactly the ones worth indexing, and walking
back down a tree to find them again is doing the work twice. In the relation
panel the keys are `i+` `i-` `i=`, because `+` and `-` there already expand
and collapse the tree (`g:projectfiles_relationview_prefix` moves them). One
file usually appears on several lines in these lists, so a selection hands
each file over once. Switches: `g:projectfiles_quickfix`,
`g:projectfiles_relationview`.

The marks follow the list wherever it is changed: `+` in the location list
updates the quickfix window beside it, `:ProjectFilesAdd` from the edit window
updates both lists, the relation panel and every open neo-tree (F9, F11, the
RelationView tree) without reopening anything - projectfiles fires
`User ProjectFilesChanged` and each view repaints. The notice says what really
changed (`색인 추가: 9개 (1개는 이미 들어 있었음)`), `=` over a visual selection
says how many of the selected files are in, and a removal asks first only when
the preset entries it deletes plus the files it excludes from a directory entry
that stays reach 20 (`g:projectfiles_confirm_drop`) - `-` on a whole directory
entry is one entry and does not ask. Removing the last file turns the project to
`none` - not indexed - rather than back to "everything"; the preset is backed
up first. Paths inside `.tags`, `.git`, `.repo` and the other always-pruned
directories are refused, since they could never produce a file.

The quickfix list shows paths from the project root, not from `/`
(`g:vimide_qf_path`, `:VimIdeQfPath root|pwd|abs`). A `:Gtags` or `Ctrl+g`
result used to spend sixty columns on the same prefix on every line, pushing
the filename and the code itself off the right edge; now it reads
`kernel/common/drivers/char/tcc_ecid.c|80 col 5| ...`. The root is the one the
relation panel uses - the outermost directory with an index - so the same file
is named the same way in both lists. A file outside that root keeps its
absolute path, since shortening it to `../../..` reads worse. nvim only:
`'quickfixtextfunc'` arrived in vim 8.2.

`vim +Restore` picks up where you left off, in real vim too. The session
plugin is nvim-only (vim does not read `.vim/plugin/*.lua`), so vim had
nothing writing a session at all - `+Restore` could only ever open whatever
nvim had last saved, which is why it looked broken. vim now writes its own
file on exit (`<session>-vim.vim`, beside nvim's) and reads that first,
falling back to nvim's when it has none. Kept apart on purpose: nvim's
session carries a sidecar with the panel state that vim cannot produce, so
sharing one file would pair a layout with the wrong panels. A layout with no
file in any window is never written over an existing session - that is how
the kernel tree's session ended up as 44 buffers and no windows.

Ctrl+g and Ctrl+/ ask in a float instead of on the command line. `Ctrl+g`
shows both fields at once - what to look for and where - so you can see the
path you are about to search before you commit to it; the old flow put the
two questions on the bottom line one after the other, and it was easy to lose
track of which one was on screen. `Ctrl+/` asks for the text only, since a
lookup covers every indexed file. `Tab` moves between fields, `Enter`
searches, `Esc` gives up, and the labels are inline virtual text so
backspacing cannot eat them. Results land where they always did: the relation
panel when it is open, quickfix otherwise. `g:vimide_grep_float = 0` and
`g:vimide_lookup_float = 0` put the command line back.

\' (Leader, then '), Ctrl+' or Ctrl+M twice: Named bookmarks of this SDK and the marks you set, in a telescope picker - filter by name or mark, by
path or by the text of the line, and `<CR>` jumps there in the edit window
(`:VimIdeMarks`; `<Esc>` then `d` deletes one and the picker stays open; `Ctrl+s` shows every SDK's bookmarks). `:marks` prints a table once
and leaves you to find the row with your eyes; twenty marks in, that is the
job. Automatic marks are left out - `'`, `"`, `^`, `.` and especially `0`-`9`,
which vim fills with recently closed files and which here means the index's
own `.tags/files` and `.tags/preset` turn up (measured: six of the first ten
rows). `g:vimide_marks_auto = 1` shows them anyway, and marks pointing at a
directory are dropped since selecting one opens a tree, not a file. This used
to be `Ctrl+m`, but in a terminal that is the same byte as `<CR>` (0x0D,
verified here), so the picker opened on every Enter in the edit window. `'` is
vim's own jump-to-mark key; `<Leader>m` belongs to vim-mark. On a terminal that
reports Ctrl+M separately (the kitty keyboard protocol, CSI u) you can have it
back with `let g:vimide_marks_key = '<C-m>'`; `g:vimide_marks_key = ''` removes
the binding. `Ctrl+'` is bound too, but most terminals never send it as its own
key - they send a plain `'`, or nothing. It arrives only when the terminal
reports modified keys (CSI u: in iTerm2 turn on *Report modifiers using CSI u*;
inside tmux also `extended-keys`). Where it does not, the binding costs nothing:
the `'` that arrives is vim's own jump-to-mark key. `:JumpKeyTest` shows what
your terminal sends when you press it.
Named bookmarks live in the same list. Its first row, right below the prompt
and selected when it opens, is `＋ 등록` ("add"): press Enter on it to bookmark
where you are. Opened with the cursor on a symbol, the row already reads
`＋ 등록: <symbol>`; opened on blank space, type a name in the prompt and the
row follows what you type. (The prompt is deliberately not pre-filled with the
symbol - that would filter the list down to it just when you opened the picker
to jump somewhere.) Bookmarks show as `★ name`, this SDK's only (see below), the
most recent first, and are kept in `stdpath('data')/vim-ide/bookmarks.json` (name,
file, line and that line's text) - vim's marks are only 26 and cannot be named.
When edits move the line, the jump finds the saved text again nearby (then the
name as a word, searching both ways, case-sensitive, then the saved line) and
stores the new line only when it really found one. Blank lines and lines of
bare punctuation such as `}` are not searched by text - they are everywhere, and
the nearest copy is usually the wrong place. Text is cut at 200 *characters*,
not bytes, so a long line of Korean does not split a character. The same line
with the same name is refreshed, a different name on the same line is a second
bookmark (an earlier version renamed silently); a bookmark whose file is gone
reports that instead of opening an empty buffer. What you type stays with the
add row, so typing and Enter always registers: to jump to an entry the typing
filtered, move onto it first. Move with the arrows (or `Ctrl+n`/`Ctrl+p`), or
`Esc` then `j`/`k`, and Enter jumps in the edit window; `Esc` then `d` removes a
bookmark or a mark and leaves the picker open: the list is read again in place,
what you typed stays, and the selection lands on the row that took the deleted
one's place, so `d` `d` `d` clears three in a row (it used to close the picker
after every delete). A `d` pressed before the new list is in is ignored, so a
quick `dd` removes one, not two. With the add row selected, the preview shows the spot that
would be saved. The file is never rewritten when it cannot be read (bad JSON,
no permission), writes from several nvim at once take turns through a lock
file, and a symlinked or restricted `bookmarks.json` keeps its link and mode.

Each SDK has its own list of named bookmarks. The picker shows only the `★`
rows of the SDK that the edit window's file is in (opened from a tree or a
panel: the last edit window's file; no file at all: the current directory), so
opening it in another SDK does not show the last one's. The SDK is the top
directory holding `.repo` (an SDK checked out with repo - also when only
`kernel/common` or `u-boot` inside it is indexed, or when one index above holds
several such SDKs), else the outermost indexed project root holding the file -
the root RelationView and the quickfix list shorten paths against, so
`kernel/common` with its own index inside it is still that SDK - else the
outermost directory marked by `.git`, `.project` or `.root`. None of this
depends on where nvim was started, and home and `/` never count. A `.repo`
checkout inside an SDK found by its index or marker (and an indexed directory
inside one found by a marker) is an SDK of its own: its bookmarks show there,
not in the outer one. Opened on a file in no SDK (`~/.vimrc`), it shows the
bookmarks saved outside any SDK. Paths are compared with symlinks resolved too.
Saving is unchanged: a bookmark belongs to the SDK of its file. The results
title starts with the `Ctrl+s` hint and then names the SDK
(`^s 모든 SDK   SDK  /home/B130111/work1/sdk`), with the path shortened to fit
the window, so the hint is never cut off. `Ctrl+s` in the picker switches
between this SDK's bookmarks and every SDK's (this SDK's first) for that one
list - not `Ctrl+a`, which is the tmux prefix in vim-ide's `.tmux.conf` and
never reaches nvim inside tmux; `let g:vimide_bookmarks_scope = 'all'` makes
every SDK the default. The SDK of the file you open it from is looked up each
time the picker opens, so an index built meanwhile counts at once. What it
learns about the other bookmarks' and marks' directories - their SDK, their
symlink-resolved path, and whether each directory on the way up holds `.repo`,
an index or `.git`/`.project`/`.root` - is remembered for the session: no git
call per row, a directory shared by many bookmarks is looked at once, and a slow
or unreachable mount is touched once per session, not on every open.
Symlinks are resolved once per SDK root, not per bookmark, and a directory under
an SDK root already found is only checked up to that root. This is forgotten
when this nvim builds an index, when what is found for the file you open from
differs from what was remembered, and when the picker has not been opened for 5
minutes (so an index another nvim built for another SDK shows up then); using
it every few minutes keeps it. The first open of a session walks every
bookmark's directory, wherever it is opened from, since a row's label is
compared with every bookmark's SDK (below). Measured on a Mac with 300
bookmarks in 300 directories of 5 SDKs (found by index, `.repo` and `.git`):
the first open makes about 1230 stats and 6-7 realpaths (one per SDK root - a
realpath of such a path costs about ten stats there) and takes 30-40 ms; later
opens make 15-72 stats and 1-2 realpaths and take 9-12 ms - the original
picker made 91 stats and 1 realpath on every open, 31-45 ms the first time and
13-14 ms later. The count grows with the number of distinct
directories and their depth, not with the number of bookmarks in one
directory.

Marks are not per SDK. `A`-`Z` always show, and so do `a`-`z` of every file,
not only the current one - an `ma` set in a file of another SDK is there too,
also after nvim is restarted, and the current file's come first. A file that
still has a buffer in this nvim gives that buffer's marks - a loaded buffer, one
read at least once, or one holding `a`-`z` marks, listed or not, also after
`:bd` (the buffer keeps its marks and nvim writes them to shada at exit, so the
list shows what will be written, not the older shada). Only for a file with no
such buffer - not opened yet since the restart, or only added with `:badd` -
are they read from the shada file, since nvim attaches a file's `a`-`z` only
when it reads that file. The picker reads buffer options with `getbufvar()`:
reading them with `vim.bo[b]` on a buffer closed with `:bd` makes nvim 0.12
drop that file's marks from shada at exit. The shada file is
the one nvim uses (`'shadafile'`, else the `n` item of `'shada'`, else
`stdpath('state')/shada/main.shada`); it is only read, and read again only
when its size or time changes (0.7 ms for a 37 KB shada of 100 files, 9 ms for
1 MB; each marked file is read once, up to its lowest mark, for the line's
text). Nothing is read when `'shada'` is empty or has `'0`, and an unreadable,
locked or half-written shada leaves just the loaded buffers' marks, without a
message. A mark whose file is gone is left out. Choosing one opens its file in
the edit window at the mark; if the mark is not there once the file is open
(another nvim deleted it meanwhile), it says `마크 'c' 가 그 파일에 없습니다`
instead of going to the old line. `d` removes an `a`-`z` mark in its own buffer
(also a buffer closed with `:bd`, without reading it again) and an `A`-`Z`
mark globally; an `a`-`z` read from shada is removed by loading its file into a
buffer (no window changes; the buffer is added to the buffer list, because nvim
does not write the marks of a loaded buffer that is not listed at exit and
that drops the file's other marks too) and deleting it there, so nvim writes
the change to shada when it exits; the notice is
`마크 'c' 를 지웠습니다 (파일을 버퍼로 읽음)`. If the mark is gone by then, the
buffer it loaded is wiped again and the notice is
`마크 'c' 를 지우지 못했습니다: 그 파일에 없습니다`. Notices are kept short (50
cells or less) so that an 80-column terminal does not stop at Press ENTER; a
longer one (a long bookmark name) is shortened on screen and kept whole in
`:messages` (fitmsg.lua).

A `★` row shows its path relative to the SDK root
(`kernel/common/sound/soc/telechips/tcc_i2s.c`), a mark its absolute path
(`/home/B130111/work1/sdk/.../file.c`), so you can tell which SDK it belongs
to; with every SDK listed, other SDKs' bookmarks are absolute as well.
Absolute paths are shown with the SDK root's symlinks resolved (`/tmp/x` and
`/private/tmp/x` are one place; below the root the path is shown as stored, and
a path in no SDK has its directory resolved), while the stored path is left as
it is. The rows
form a table: kind and name, path, line and the line's text start at the same
screen column on every row. Widths are display cells (`strdisplaywidth` - a
Korean character takes two), padded with spaces rather than tabs, since a tab
stop misaligns the rows as soon as a column crosses it. A name longer than a
quarter of the list is cut at its end. The path column goes before the text
column (the preview shows the line anyway), and a path that still does not fit
is cut with `…` at directory boundaries, never inside a directory name. A
relative path keeps its beginning and its end and loses the directories in
the middle (`subcore/build/…/git/src/tsnd_arpc.c`), so both where it lives and
the file name stay; only when even the first directory and the file name do
not fit is it cut at the start (`…/src/tsnd_arpc.c`). An absolute path shortens its SDK root last,
since the root is what tells the SDK: first the whole root stays and only the
part below it is cut
(`/home/B130111/work1/tsnd/dev/tsnd_2.1/Android14_IVI_1.1.0/…/telechips/tcc_i2s.c`);
if even the root and `…/` and the file name do not fit, home is written as `~`
with the rest of the root whole (`~/work1/tsnd/dev/tsnd_2.1/Android14_IVI_1.1.0/…/tcc_i2s.c`);
only then is the root itself shortened, dropping middle directories first and
keeping the one above the SDK's name and the first one under home longest
(`~/work1/…/tsnd_2.1/Android14_IVI_1.1.0/…/tcc_i2s.c`). When another SDK
with the same name is known - the SDK of any bookmark, listed or not (other
SDKs' bookmarks hidden by the scope count too), of any mark including those read
from shada, or the SDK you opened it from - the directories where their paths
part (`work1` and `work2`, `tsnd_2.0` and `tsnd_2.1`) are kept, and they are
what is kept longest: for a root outside home (`/private/tmp/...`,
`/Volumes/<share>/...`) the directories before the first parting one go first
(`/private/…/work2/…/tsnd_2.0/Android14_IVI_1.1.0`). So a row reads the same
whatever else is listed, and deleting its twin does not change it while the
picker is open. `Ctrl+s` measures the columns again for the other scope, so a
row may be cut a little differently there, but the parting directories stay. To keep the root whole,
the name column gives up cells down to 10 (names are cut at their end) when
that is enough - else to fit the root with home as `~`, else to fit the
shortest root that still has the parting directories and the SDK's whole
name. Only when even that does not fit is the SDK's name cut in its middle,
then left out while the parting directories stay
(`~/work2/…/tsnd_2.0/…/tcc_i2s.c`), then only the first of them stays
(`…/work2/…/tcc_i2s.c`); in a path column of about 20 cells or less that goes
too. A path in no SDK is
shown whole, then with home as `~`, then with its first directory and its end
(`~/notes/…/a/b.md`).
The preview shows the place either way. The columns are measured again after
`d` and `Ctrl+s`, but within one open (and one scope) they never get narrower,
so deleting the row with the longest name or root does not reshape the
others. The preview is a little narrower here than in other lists
(0.4 of the width) to leave the table room. Typing filters by name or mark,
the whole path and the text.

Ctrl+M twice opens it too. In a terminal Ctrl+M *is* Enter, so this is Enter
twice - and it is done without waiting: a `<CR><CR>` mapping would make every
single Enter hang for `timeoutlen` (0.8 s) and slow down the Enter of the
quickfix list and the trees as well. Instead the first Enter moves at once, as
it always did, and a second Enter in the same window within
`g:vimide_marks_double_ms` (400) puts the cursor back and opens the list. A
counted `3<CR>` just moves; windows with their own Enter (quickfix, the relation
panel, the trees, telescope) and the command-line window are untouched. The
price is that pressing Enter rapidly to walk down now opens the list on the
second press - use `j`, or `let g:vimide_marks_double = 0`.

Ctrl+h (or `,ch`): Find and replace the symbol under the cursor in this file.
`Ctrl+h` puts up a float, `,ch` asks on the command line - both fill `Old`
with the word under the cursor and let you edit it, and on blank space `Old`
starts empty and the cursor starts there, so you can type what to look for.
Then Enter offers **ALL**, one by one (`Yes`/`No`), or cancel.
Nothing in the edit window changes while you type: nvim previews `:s` live
(`inccommand`) by default, which hides the very text you are replacing, so
this turns it off for the duration and puts it back
(`g:vimide_replace_preview = 1` keeps the preview). One-by-one hands over to vim's own `:s///gc`
prompt - `y` replaces, `n` skips, `a` takes the rest, `q` stops - and the
whole thing is a single `:s`, so one `u` undoes it. `Esc` cancels anywhere.
Word boundaries are on (`g:vimide_replace_word`), so renaming `old_name`
leaves `old_names` alone. `Ctrl+h` used to be "go to the window on the left";
`<C-w>h` still is, and `g:vimide_replace_ctrl_h = 0` gives the old key back
(`,ch` keeps working either way)
\C: Turn the automatic colouring on and off (`:VimIdeAutoColor`, `g:vimide_auto_color`). This covers only what a shortcut paints by itself - the jump colour of `<C-]>`/`<C-t>`, the colour `\\c` and `<C-/>` (`:LookupReferences`) put on what they searched for, and the shading of the symbol under the cursor. What you paint by hand, `<F4>` and `<F8>`, is never touched: switching the automatic colouring off strips only the colours it put there itself
F6: Toggle MiniBufExplorer, source file explorer on the top side
F7: Search any symbol the index knows, the same as `\fs` (nvim only). It used to fold a function body; `zf` still does that, as do `za`/`zo`/`zc`
F8: Stick a yellow mark on the symbol under the cursor, and take it off by pressing it again there (nvim only). It used to unfold (`zo`, which is still there)
F9: Toggle neo-tree on the left (F11 used to be this one; aerial closes with it, since both want the left). Inside the tree, `w` widens it a step at a time and then snaps back to its normal width, the same key and the same feel as `w` in the relation panel - the steps are percentages of the screen (`g:neotree_wide_steps`, `[25, 40]`), and the other sidebars keep their width; the edit window pays for it. Diffview's file panel takes `w` the same way (`g:diffview_wide_steps`, see the Magit-style git UI above)
F10: Toggle the symbol outline of the current file on the left - aerial in
     nvim (see "The symbol outline" below), tagbar in vim or with
     `g:vimide_outline = 'tagbar'`. It closes neo-tree (F9, F11) and NERDTree
     first, since they share the left; `<leader>o` toggles aerial alone
     (the cursor or a mouse click on a symbol jumps to it in the edit window)
F11: Toggle neo-tree as a float (F9 used to be this one)
F12: Toggle RelationView, the Source Insight style relation window (nvim only;
     it was F3). Deleting the gtags files is now `:call Deltags()`
\z (or \lz): In the RelationView column - neo-tree, the relation list or the
     context view - give the window you are in the column's whole height; the
     other two drop to one line each (their status lines stay, so you can see
     what is there). Press it again and every height goes back to what it was
     before. Pressed in another of the three, it restores and then zooms that
     one. Only heights are touched - `w` (width) works alongside - and windows
     outside the column keep theirs: a quickfix window opened while zoomed
     gets its full height instead of the zoomed window swallowing it. With
     `g:relationview_position = 'bottom'` the list at the bottom takes the
     screen height the same way. `:RelationViewZoom` is the command. A window
     that already runs the full height (the F9 tree, the `T` context with
     nothing below it) says so. It works in every tab that has the panel, and
     `w` in the bottom layout (which also drives the height) unzooms first
Every telescope list (\ff \fg \fi \fo \fx, the bookmarks ...) reads top down:
     the prompt is at the top and the first item - the best match, the newest
     commit in \fi - right under it. Moving past either end stops there; it
     used to wrap round to the other end (`sorting_strategy = 'ascending'`,
     `scroll_strategy = 'limit'` in the telescope setup of `.vimrc`). \fb lists
     the most recently used buffer first, and in \fb, \fi and the bookmarks
     equal matches keep that order while you type (telescope's default
     tiebreak moves the shorter line up). Enter, the open keys (`^x ^v ^t`),
     the arrows, `^n`/`^p`, `j`/`k`, `<Tab>` and `^q`/`M-q` wait until the
     list has caught up with what was typed (at most 5 s), so a name typed
     and entered in one burst opens that name. With nothing typed they act at
     once, even while a slow first list is still loading, and a resumed picker
     (`:Telescope resume`) counts as caught up. In `\fx`, where Enter removes,
     a second Enter that arrives while the list is being rebuilt is dropped,
     not queued - see "Found by random QA" below
Ctrl+n, Ctrl+p: Next/previous item of the list in front of you - the
     RelationView caller list when the panel holds one (previewed in the
     context window; the edit window does not move), the quickfix list
     otherwise
Ctrl+Enter: Take the edit window to the RelationView item you walked to
Ctrl+c: Unpin the relation panel (otherwise the CONFIG lookup, as before)
Ctrl+] / double click on a PARAMETER or a LOCAL VARIABLE goes to its
declaration in the enclosing function - in the edit window, and inside the
context window when that is where you are reading - and the symbol it lands
on is coloured sky blue until you move off it. Those are in no index, so
this used to end in "E426: tag not found".
On a member access (`msg->cmd`, `ctx.id`, `asrc->pair[i].hw.max_channel`)
the jump follows the type of the BASE variable through every link of the
chain - array subscripts included - and goes to that member's declaration in
the struct, so a local or a parameter that happens to carry the same name
cannot steal it. When a type along the way is not in the index, the file
defining it is pulled into the project files first and the chain is walked
again.
Chains work all the way down - `asrc->pair[i].hw.max_channel` lands on
`max_channel` - including the kernel's favourite shape, structs nested
anonymously inside each other (`struct { struct { u32 max_channel; } hw; }
pair[N];`), where there is no type name anywhere to look up. The landing
line is the one carrying the member's name, not the `struct {` the
declaration happens to start on.
gf / Ctrl+]: on an `#include` line, open that header (resolved next to the
     including file, then through the GTAGS path index, then 'path')
\fo / F3: Find a file among the indexed ones and open it (^d or Esc d drops
     it, <Tab> marks several; the picker stays open)
\fx: Remove entries (Enter, ^d or Esc d; <Tab> for several; stays open)
\fm: Choose the preset    \fS: Save it    \fR: Reindex
     (\fp / \fd, the add pickers, are off - slow on a big tree. Add from the
     tree with +, or :ProjectFilesAdd / :ProjectFilesAddDir)
\ff / \fg / \fi: Find files / live grep / git commits in the git repository
     that holds the current file - or, in neo-tree, the path under the cursor.
     No repository: under that file's directory (or that path). See "Searching
     from the repository" below.
Ctrl-W H/J/K/L/r/R/x/T: Move edit windows the usual way, but only among the edit windows - the tree, the outline, the relation panel and the quickfix list stay put (nvim only, see [Moving windows](#moving-windows-inside-the-edit-area-nvim-only))
Ctrl+]: Open the definition in the EDIT window, the same as `g]` and `f]`;
     Ctrl+t back
Ctrl+] Ctrl+]: open that definition in the context window and focus it
     instead. The mouse is paired with the keys: Ctrl+left-click is the single
     press (edit window), a double click is the double press (context window).
     Which action the single press does is `g:vimide_jump_target` (`'edit'` by
     default, `'ctx'` for the old behaviour; the double press always does the
     other one). Binding both costs a little: after `Ctrl+]` vim waits
     `'timeoutlen'` (1000 ms by default) to see whether a second `Ctrl+]`
     follows. That wait is `g:vimide_map_timeoutlen`, 800 ms here; `let g:vimide_ctx_jump_seq = 0` drops the two-key binding
     and the wait with it, and the double click still goes to the context
     window. The same wait now applies to every leader sequence (`\fr`, `\lt`),
     so raise it to 400-600 if your hand feels rushed - this setup used to wait
     forever (`notimeout`), which is what made a single `Ctrl+]` do nothing
Ctrl+9, Ctrl+0: Next/previous quickfix item, always. These two keys only
     reach nvim from a terminal that speaks CSI u (the kitty keyboard
     protocol): iTerm2 3.5+, kitty, WezTerm, Ghostty, foot. ]q / [q do the
     same everywhere, so use those if your terminal stays silent.
Shift+h, Shift+l, Shift+k, Shift+j:  Resize between split windows
Ctrl+l, Ctrl+k, Ctrl+j:  Move to the split window on the right / above / below.
     Ctrl+h is no longer "left": it is find and replace (above), and
     `<C-w>h` goes to the window on the left (`g:vimide_replace_ctrl_h = 0`
     gives Ctrl+h back)
,e or ,r : Go to the tab on the left/right
,w: Save and close the current file. *Well~ we call it buffer in Vim*
,pa: Toggle paste option. This is useful if you want to cut or copy some text from one window and paste it in Vim. Don't forget to toggle paste again once you finish pastin
,ch or ,h: Find and replace options. This is useful if you want to find some text under the cursor and replace it to some text.

<leader>c<space>: Toggle comment, comments the ranged lines or uncomments
<leader>g: Find the global by entering keyword, and disaplys the results via quickfix window
<leader>e: Find the egrep by entering keyword, and disaplys the results via quickfix window
<leader>f: Find the files by entering keyword, and disaplys the results via quickfix window
<leader><leader>g: Find the global under the cursor, and disaplys the results via quickfix window
<leader><leader>f: Find the symbols under the cursor, and disaplys the results via quickfix window
<leader><leader>c: Find the callers under the cursor, and disaplys the results via quickfix window
<leader><leader>f: Find the files under the cursor, and disaplys the results via quickfix window
<leader><leader>i: Find the includes under the cursor, and disaplys the results via quickfix window
<leader><leader>d: Find the functions under the cursor, and disaplys the results via quickfix window
<leader><leader>e: Find the egrep under the cursor, and disaplys the results via quickfix window
<leader><leader>a: Find the assignments under the cursor, and disaplys the results via quickfix window

<leader>s: Neogit - Magit style git status in a new tab, for the repo of the file / tree node under the cursor (s stage, u unstage, c commit, P push, ? help)
<leader>ha / <leader>hr: stage / revert the hunk under the cursor, or the selected lines in visual mode (gitsigns, nvim only)
<leader>hu / <leader>hv: unstage that hunk / show it in a float
<leader>ht: toggle the blame of the current line (off by default - it runs git blame on every cursor rest)
]h / [h: next / previous hunk (]c and [c stay vim's own diff-mode motions)
<leader>v: Diffview - side by side diff of the working tree of the repo of the file / tree node under the cursor (in a diffview tab: close it)
w (Diffview file panel): widen the panel a step at a time, then back to its normal width; in the :DiffviewFileHistory panel at the bottom, its height (each diffview tab keeps its own). Only the diff windows give way; your own splits in that tab keep their size
Ctrl+n / Ctrl+p (Neogit commit view, staged diff while committing): next / previous hunk header across files, stays put at the ends
<leader>o: Toggle the aerial symbol outline of the current file
<leader>t: Toggle the neo-tree file tree, same as F9 (a add, d delete, r rename)
<leader>fs: Search every symbol in the project through the ctags index
:GtagsIndex / :GtagsIndexUpdate / :GtagsIndexStatus: GTAGS index by hand
:GutentagsUpdate!: rebuild the ctags index of this project by hand

Ctrl+g: Grep. In nvim a floating "찾기 (grep)" box opens with two fields:
        the text to find, filled with the word under the cursor (or, in visual
        mode, the selected text; on blank space it starts empty), and the
        directory to search, starting at the one holding the current file. Tab
        moves between the fields, Ctrl+x Ctrl+f completes the path, Enter
        runs, Esc drops it.
        The hits go to the RelationView list while the panel is up, and to the
        quickfix window otherwise. Uses ripgrep when it is on $PATH.
        Inside neo-tree (F9, F11 or the RelationView tree) the same box opens
        with the directory taken from the cursor instead - see "Searching from
        the tree" below.
        It works in the side windows too - quickfix and location lists, the
        RelationView list, the context view, aerial, the DirDiff tree: the
        directory is that of the file the window points at (the quickfix entry
        or list entry under the cursor, the file the context view shows,
        aerial's source), falling back to the edit window's file, and when
        the cursor sits on an icon or a marker the text starts as the first
        identifier on the line. Only help and terminal windows refuse.
        (Real vim, and nvim with g:vimide_grep_float = 0, ask the two
        questions on the command line instead: the text, then the directory.
        :VimIdeGrep <text> greps that text the same way - no box, the
        directory asked on the command line. g:relationview_grep_ask_dir = 0
        skips that directory question in both. :Grep is still grep.vim's own
        prompt.)
Ctrl+f: Inside neo-tree only: find files by name under the cursor's directory
        (see "Searching from the tree"). Everywhere else it is vim's own
        page-down.
Ctrl+n: Go to the next item in the list, and put the cursor in the window that
        shows it (the RelationView preview, or the edit window)
Ctrl+p: The same, backwards
        (Ctrl+0 / Ctrl+9 step the same list but only peek - the cursor stays)
```

To perform cscope searching, use `cs find` command below.

`:cs find {querytype} {name}`,

Where `{querytype}` corresponds to the actual cscope line interface numbers as well as default nvi commands:

```
0 or s: Find this symbol
1 or g: Find this definition
2 or d: Find functions called by this function
3 or c: Find functions calling this function
4 or t: Find this text string
6 or e: Find this egrep pattern
7 or f: Find this file
8 or i: Find files #including this file
9 or a: Find places where this symbol is assigned a value
```

## Keys in a telescope list

Every list (`\ff`, `\fg`, `\fb`, `\fo`, `\fs`, the bookmarks, F1 ...) is a
telescope picker, and they all take these keys. The prompt starts in insert
mode; `Esc` goes to normal mode, where `j` / `k` move. The open, move and
quickfix keys wait until the list has caught up with what was typed (see
"Every telescope list" in the key list above).

| in the prompt | |
|---|---|
| `Enter` | open the entry under the cursor - a file opens in the last edit window |
| `Ctrl+x` / `Ctrl+v` / `Ctrl+t` | open it in a split / a vertical split / a new tab |
| `Tab` / `Shift+Tab` | mark the entry (several can be marked) and move down / up |
| `Ctrl+q` | send every listed entry to the quickfix list and open it |
| `Alt+q` | send the marked entries to the quickfix list and open it |
| `Ctrl+n` / `Ctrl+p` | next / previous entry (also `Down` / `Up`; `j` / `k` in normal mode) |
| `Ctrl+u` / `Ctrl+d` | scroll the preview up / down; in `\fo`, `\fx` and the bookmarks `Ctrl+d` drops the entry instead (next row) |
| `d` | in normal mode (`Esc` first) in `\fo`, `\fx` and the bookmarks: drop the entry, or every marked one; the list stays open. `Ctrl+d` does it in insert mode |
| `Ctrl+s` | in the bookmarks: this SDK's named bookmarks only / every SDK's, for this list (`g:vimide_bookmarks_scope` sets which one it opens with; not `Ctrl+a`, the tmux prefix in vim-ide's `.tmux.conf`) |
| `Ctrl+/` / `?` | telescope's own list of this picker's keys (`?` in normal mode) |
| `Esc` / `Ctrl+c` | `Esc`: insert to normal mode, and in normal mode close the list; `Ctrl+c` closes from insert mode |
| `F1` | the shortcut help, with this prompt's own keys first |

## Shortcut help (F1)

F1 opens one telescope list of every key vim-ide has (`:VimIdeKeys`,
`.vim/plugin/keyhelp.lua`). None of it is written down a second time: every
time it opens, the list is gathered from

- this README: the key list at the top of "Usage (shortcut)" - a line that
  starts at column 0 with `Key: description` is an entry and indented lines
  continue it; `A / B`, `A, B`, `A or B` and `A (or B)` name several keys -
  the key tables of the other sections (rows like ``| `key` | meaning |`` in
  a table whose first header cell is empty or reads "in the ..."; a count in
  front of a key, as in `1<C-r>`, is shown but read as the key), and blocks
  elsewhere with three or more `Key: description` lines (the relation panel's
  keys). A table of another kind is not a list of keys, but when a key's text
  points to its section by name in italics - the DirDiff tree's `f` says "see
  *Views* below" - that table and the list right after it are searched as
  part of the key's text and shown in its preview, so `최신`, `고아` or
  `right-newer` find `f`;
- the mappings that are set right now, in every mode - and when F1 is pressed
  in a tree, the relation panel, quickfix, a telescope list or another special
  window, that window's own mappings, listed first and labelled `이 창 ·` with
  the window's filetype (or its buffer name, or a float's title), and joined
  with that window's key table here, so neo-tree's `J` reads "first / last
  sibling" and a telescope list's `Ctrl+v` reads as in "Keys in a telescope
  list" (F1 in DirDiff's view menu closes the menu first, so the tree's keys
  are listed). In a file buffer,
  the mappings set for that buffer only (an ftplugin, LSP) are listed and
  matched too - but one that shares no mode with the global mapping of the
  same key is a different mapping and gets a row of its own (delimitMate's
  insert-mode `Ctrl+h` is a backspace, not find and replace);
- the commands: vim-ide's, the plugins', nvim's, and the ones defined for the
  buffer F1 was pressed in (`:GutentagsUpdate`).

Typing searches the whole text of a README entry, not only the first sentence
shown in the list, and a key that appears in that text brings the entry up -
`w` finds the F9 entry (its tree widens with `w`), `i+` the relation panel's
entry. Vim notation works as well as the README's, in either case: `<C-]>`,
`Ctrl+]` and `ctrl+]` all put the `Ctrl+]` row first, and `Shift+Tab`,
`Ctrl+r` or `Space` find the rows written `<S-Tab>`, `<C-r>`, `<Space>` (the
DirDiff tables, a window's own mappings). Of two keys that differ only in
case, the one written the way you typed it comes first: `]q` puts `]q`
(`:cnext`) above `]Q`, and `f` in the DirDiff tree puts `f` above `F`. Among
rows whose key matches, the window F1 was pressed in comes first.

A key that is documented here and also mapped is one row: the README text
wins, the mode column shows the modes it is mapped in, and the preview adds
the real right-hand side and the file and line that set it - so a line here
that has gone stale is seen next to what the key really does. An empty mode
column means there is no global mapping: a key that only works inside a tree
or a panel, or one this README promises and nothing maps. Only the "Usage"
list is matched against the global mappings; a table elsewhere is usually
about the keys of one window (neo-tree's `K`, the DirDiff tree's `<C-n>`), so
it is matched only for leader keys, F keys, `Ctrl-W`, `,` keys and
commands - and for the keys DirDiff takes over in its edit windows
(`<C-r>`, `<C-l>`, `<C-S-r>`, `<C-S-l>`, `\d`, `q`), which are global mappings
that act only in a DirDiff comparison's two windows: their rows in "in the edit windows" show the
mapping (and only that one - not the same key's mapping in other modes), and
every preview of those mappings says what the key does outside a DirDiff
comparison: the mapping DirDiff wrapped, with the file and line that set it
(`Ctrl+l`: `:wincmd l`), or nvim's default (`<C-r>`: redo). Mappings and
commands this README does not mention are listed too, with their description
or right-hand side: vim-ide's own first, then the plugins', then nvim's
defaults (`let g:vimide_keyhelp_others = 0` leaves out the plugins' and nvim's
mappings and commands; the mappings and commands of the buffer F1 was pressed
in stay - an ftplugin's `[[`, delimitMate's, LSP's).

The parsed README, and the files the previews and the read-only tabs show,
are kept only while the file's modification time (to the nanosecond), size
and inode stay the same, and the mappings and commands are read again every
time, so a new key - mapped, or written down here - is in the next F1 without
restarting. `:VimIdeKeys!` re-reads the files anyway. Measured here, with
this 3,700-line README and about 770 rows: the list is on screen in about
40 ms, 70-80 ms the first time in a session (telescope loading), and reading
the README again after it changed costs about 20 ms of that. Filtering the
whole text of every row as you type takes under a millisecond a key. The
`:help` tag of an nvim default mapping is checked against a table read once
from `$VIMRUNTIME/doc/tags` (5 ms for all of them), not by searching every
help tag per row.

| | |
|---|---|
| `<CR>` | a README row: open the README at that place in a read-only tab (`q` closes it). A mapping: open the file that set it, at that line, the same way; nvim's own defaults (`gcc`, `]q`, `[d`, `<C-W>d` ...) open their `:help`. A command: put `:Command ` on the command line |
| `<C-y>` | copy the key in vim notation (`<F12>`, `<C-]>`, `\fo`) to the unnamed register; also to `+` / `*` when 'clipboard' has `unnamedplus` / `unnamed`. The list stays open, and its prompt title says what was copied for two seconds (in insert mode the message line is redrawn as `-- INSERT --` at once) |
| `<C-q>` / `<M-q>` | the listed / the marked rows go to the quickfix list: the README line of each, or the line that set the mapping or command. A row with no such line (nvim's Lua defaults, a mapping set from Lua or typed on the command line, a Lua plugin's command) goes in as text only - not a place to jump to |
| `<C-x>` / `<C-v>` / `<C-t>` | nothing here - a row is not a file to split open |

F1 works in normal, visual and insert mode, and in every telescope list -
including this one - where it closes that list and opens this one with the
list's own keys first. Closing the list without choosing a row (`Esc`,
`Ctrl+c`) goes back to where F1 was pressed, with the cursor where it was:
in insert mode at the same place if that is where you were - in Replace or
Virtual Replace (`gR`) mode if it was one of those, after an `i_CTRL-O` too,
and also inside the `Ctrl+g` / `Ctrl+/` / `Ctrl+h` forms - and with the same
selection if F1 was pressed in visual mode. The window you were in before
stays the previous window (`Ctrl-W p`), so cancelling one of those forms
afterwards still lands in the edit window it was opened from. Those forms
float above everything else, so while the list is open they are hidden (nvim
0.10 and later; before that the list is raised above them), and they come back
when it closes. DirDiff's view menus
(`f` in the tree, `\d` in a compare window) do not come back: F1 there closes
the menu and opens the list from the window the menu was opened from, so
closing the list, or opening a row from it, goes to that window.
`q` in a read-only README or definition tab goes back to the tab and window F1
was pressed in. Terminal mode leaves F1 to the program running there.
The fugitive windows and, in nvim, tagbar no longer take F1 for their own
help: theirs is `g?` and `?`. BufExplorer (F6) and vim's tagbar keep F1 - it
is their only help key, their header says so, and vim's F1 page does not
list their keys. In the command-line window (`q:`) F1 only says it cannot
open there - close that window with `:q` first (`Ctrl+c` in normal mode is
taken by another vim-ide key there). A mapping typed on the command line is
labelled 명령줄; one set from Lua with no file nvim can name is labelled Lua.

If the README cannot be read (`g:vimide_keyhelp_readme` names a file that is
not there), the list says so in its prompt title and holds only the mappings
and commands.

In vim 8.1 (no telescope, no Lua) F1 shows the "Usage (shortcut)" section of
this README in a read-only tab; `q` closes it and goes back to the tab and
window F1 was pressed in. The man page F1 used to show is `\K` now.

## Theme

Three, picked with `g:vimide_theme` (or `:VimIdeTheme <name>` while running):

| | |
|---|---|
| `si` *(default)* | Source Insight's colours - white background, black body, navy bold keywords, green comments, maroon strings on the pale yellow wash SI puts behind them, and SI's underline on declarations (`.vim/after/queries/{c,cpp}/highlights.scm` finds them; references stay plain). `.vim/colors/sourceinsight.vim` carries two palettes: `screen` (default) matches a real SI install's screen - navy bold for the `struct` keyword, a function's own name, `#if`/`#ifdef`/`#endif` and their conditions; green for `#include` and `#define`, and green bold for every type name in use - `int`, `void`, `char`, `uint32_t`, `size_t`, `bool`, and the project's own struct, enum and typedef names - along with the modifiers in front of them (`static`, `extern`, `inline`, `const`, `volatile`), while the name at its own definition is navy bold, bold green for a call, red for the kernel's annotation macros (`__iomem`, `__user`, `__init`); a thin red (`#ff5f5f`) for constant macros, `#ifdef` conditions, `NULL` and numbers; maroon on the pale yellow wash for strings; purple comments - and `g:sourceinsight_palette = 'factory'` switches to SI 4.0's shipped style set instead - seven inks, green plain keywords with navy bold control keywords, purple comments, navy strings, red numbers, navy bold declarations with the underline only on parameters. The palette is one table at the top of the file, and the treesitter (`@...`) groups are mapped to it |
| `light` | PaperColor (light) - the closest ready-made light theme, though its keywords are pink and its comments grey |
| `dark` | jellybeans, what this configuration used before |

```vim
let g:vimide_theme = 'dark'      " in a file read before ~/.vimrc
:VimIdeTheme si                  " or just switch now
```

Source Insight draws the *name* in a function, struct or enum definition
larger than the body text (140%) with a faint shadow. Neovim has no
per-highlight font size - `nvim_set_hl` rejects `scale` and `font`, in a GUI
as much as in a terminal - so the same "read this first" weight is carried by
attributes instead, and how much of it you want is an option:

```vim
let g:sourceinsight_declaration_emphasis = 'strong'   " bold + underline + a
                                                      " faint grey wash
"                                          'bold'     " default: bold + underline
"                                          'off'      " no emphasis
```

The symbol windows follow the same palette as SI's own list panes: white
ground, black symbol names, navy bold section titles, grey paths, a pale
blue bar on the row under the cursor. The telescope pickers
(`\fs`, `\fo`) are themed to match, including the navy bold on the
characters your search actually matched.

The cursor is a case of its own. Neovim colours the terminal cursor from the
highlight group named in `'guicursor'`, and the default value names none for
normal mode - so the terminal's own cursor colour is used, which on a white
background is often invisible. The theme wires the group in and the cursor
becomes a black block (nvim then emits `OSC 12`, which iTerm2 and friends
honour); `let g:sourceinsight_cursor = '#0087ff'` for something more vivid.

The relation window follows whichever theme is on - its panel is a list, not
code, so paths and tree glyphs stay grey rather than comment-green, and the
sky blue box on a jump landing is the same in all three.

### 24-bit colour, and why the cursor can be invisible over SSH

`termguicolors` is what makes the exact hexes above reachable, and it is
turned on when the terminal advertises 24-bit colour in `$COLORTERM`. It is
also what makes the cursor colour work at all: nvim sends the cursor colour
to the terminal as `OSC 12`, and it only sends it when `termguicolors` is on.

```
termguicolors=on   ->  OSC 12;#000000 sent, cursor turns black
termguicolors=off  ->  nothing sent, the terminal's own cursor colour stays
```

`ssh` forwards `TERM` but not `COLORTERM`, so a session that is fine locally
comes up with 24-bit colour off on the remote machine - 256-colour
approximations instead of the palette, and an invisible cursor on white.
`:VimIdeColorCheck` prints what is actually on and how to fix it:

```
termguicolors : off
$COLORTERM    : (비어 있음)
접속          : SSH (/dev/pts/3)
커서색 전송   : 아니오 - termguicolors 가 꺼져 있어 커서색을 못 바꾼다
```

Any one of these turns it on, on the machine you are editing on:

```vim
let g:vimide_truecolor = 1       " in a file read before ~/.vimrc
```
```sh
export COLORTERM=truecolor       # in the remote ~/.bashrc
```
```
# or forward it: ~/.ssh/config on the client
Host myserver
    SendEnv COLORTERM
# and on the server, /etc/ssh/sshd_config
AcceptEnv COLORTERM
```

Set it only where the terminal really does 24-bit colour; forcing it on a
terminal that does not will make the colours worse, not better.

## Project files and presets (nvim only)

`~/.vim/plugin/projectfiles.lua` decides WHICH files are indexed. There is no
window of its own: everything runs through telescope pickers.

```
\fo  find an indexed file and open it   (^d / Esc d drop it, <Tab> several)
\fx  pick entries to drop               (Enter / ^d / Esc d, <Tab> several)
\fm  choose the preset                  (auto included, ^d deletes mine)
\fS  save the current entries as a preset
\fR  reindex now
\fs  find any symbol in the index      (<F12> or ^g sends it to the relation window)
\fw  the same, for the symbol under the cursor
```

(`<leader>` is `\` in this setup.) Every one of them is a telescope picker
with a preview, multi-select where it makes sense, and the same commands
behind it.

Dropping from `\fo` (also `F3`) or `\fx` leaves the picker open: the marked
entries (`<Tab>`), or the one under the cursor when none are marked, go out in
one commit - one reindex, one line of message - and the list is read again in
place with what you typed kept and the selection on the row that moved up into
the gap. `<Esc>` `d` does the same in normal mode; `<Esc>` twice closes it.
Until the list has caught up with the prompt - just after a removal, or while
what you just typed is still being filtered - `d` and `^d` are ignored and
`<CR>` waits and then acts: in that moment the selection is still the entry
just removed or one the new filter hides, so a quick `dd` removed it twice
("목록에 없습니다"), `<CR>` opened the file that had just gone, and typing a
letter and `^d` together removed an entry that was no longer shown. A removal
that is cancelled (the confirm prompt) or finds nothing leaves the list, the
selection and the `<Tab>` marks as they were. The
selection is found again by name, not by position, so dropping a directory
entry (which takes the file entries under it along) does not push it down.
`d` is taken in these pickers, so `<Esc>dd` no longer clears the prompt - use
`<Esc>cc` for that (telescope keeps `Ctrl+u` for scrolling the preview).
`\fp` and `\fd` (pick files / directories to add) are off: both walk the whole
project to build their list, which is slow on a big tree. The keys now only say
so - left unmapped, `\f` (`:Gtags -P <word>`, which waits for Enter) would fire
after the timeout and type the `p` into its command line. The tree's `+` (and
`V` then `+` for a range) is the way in; the commands still open the pickers
when you want them: `:ProjectFilesFind`, `:ProjectFilesAdd`, `:ProjectFilesAddDir`,
`:ProjectFilesRemove`, `:ProjectFilesPreset`, `:ProjectFilesSave`,
`:ProjectFilesReindex` (each takes an optional argument to skip the picker),
plus `:ProjectFilesPresetShare` (below).

**Saving keeps the index current.** Writing a file the list already knows
updates the database for that one file (`global --single-update`, a few
milliseconds, in the background), so a function added or removed is
searchable the moment `:w` returns - no re-index and nothing to wait for. A
file the list does not know yet is the only case that needs more: if it was
created under a *directory* entry of the preset, it goes into the list without
expanding the preset again and only that file is indexed (0.04 s on this
kernel index; expanding first used to add 0.36 s). That happens once, a second
after the last save, and takes every new file saved in that second together:
`:wa`, or `foo.c` and then `foo.h`, is one list write and one index request
per project. Before, only the last save's path was looked at, so the first
new file stayed out of the list, GTAGS and ctags until the next `\fR` or
start. Created anywhere else, nothing runs at all -
expanding the list could not have brought it in, so there is no point paying
for a `find`. `g:projectfiles_index_new_on_save = 0` switches that second
half off; the per-file update is autoindex's and stays.

**A new SDK checkout starts from an old preset.** `\fM`
(`:ProjectFilesImport`) lists every preset you have next to the number that
matters when you move trees - how many of its entries actually exist *here*:

```
  qnx_hypervisor_ivi_sdk_d5      246항목 중  145개가 이 트리에 있음  (58%)
  kernel_common                  102항목 중  102개가 이 트리에 있음  (100%)
```

A preset is a list of project-relative paths, so it applies to any checkout
of the same tree and the index is rebuilt from the new root. What `\fm` does
not tell you is that count, and the entries that are not in the new tree drop
out silently - measured: 101 of 246 on a sibling checkout, which leaves you
wondering why the index came out small. After you pick, it asks whether to
share the preset (both projects read the same file, so an edit in one shows
up in the other) or copy it under a new name (`..._d5` and `..._d5_A14` are
the same list that grew apart). Verified on a throwaway tree: importing
`kernel_common` into a fresh project wrote its `.tags/preset`, expanded the
list to the 14 entries that existed there, and indexed those 14 files.

`\fs` (`:ProjectSymbols [name]`) is the symbol half of the same idea: every
definition the database holds - `global -x -d` answers with all 31k of them in
about ten milliseconds on this kernel index - goes into one telescope picker,
tagged with what it is (`func`, `struct`, `macro`, `enum`, `typedef`, `var`)
so the struct and the function that share a name are told apart at a glance.
`<CR>` jumps to the definition in the edit window (the jumplist is kept, so
`C-o` comes back, and the landed symbol gets the same sky blue marker `C-]`
leaves); `<F3>` (or `^g`) hands the symbol to the relation window instead,
which is where the next question - who calls this? - is answered. On an index
too large to list at once (over `g:projectfiles_symbol_db_max_mb`, 40 MB of
GTAGS) it asks `global` for the prefix you typed instead of for everything. `\fw` opens it on the word
under the cursor, and `:ProjectSymbols <Tab>` completes symbol names straight
out of the index. The list is built once per database and rebuilt after a
re-index.

Two modes:

* **auto** (no preset): the whole project, exactly as before -
  `.indexfiles`, `git ls-files`, `cscope.files`, then a find.
* **preset**: only the entries of a named preset. An entry is a file or a
  directory (a directory brings everything indexable under it). The list is
  written to `<root>/.tags/files`, which `indexfiles.sh` reads before
  anything else, so **gtags and ctags both index exactly what the picker
  shows** - and a smaller index means faster searches and a shorter
  RelationView tree.

**A file brings what it needs.** Adding one file also adds the headers it
`#include`s (resolved next to the file, then through the index) and the
files that define the symbols it uses - one level deep, at most
`g:projectfiles_expand_max` symbols (40), off with
`g:projectfiles_expand = 0`. Adding `src/main.c` in a small project pulls in
`inc/util.h` and `src/util.c` by itself.

With the preview open, `Ctrl+]` never sends the edit window anywhere: if
gtags has no definition the ctags snapshot answers instead (6 ms even on a
kernel-sized tags file), shown in the preview with the panel switching to
that symbol - and the search for the file that actually defines it runs in
the BACKGROUND afterwards, so the jump lands in about 100 ms instead of
waiting ~1.7 s for a `git grep` over the whole tree. When that search
finishes and the file joins the project, the panel fills in its callers. Only with no
preview window does the edit window take the jump itself.

A symbol the index does not know about is not a dead end: `Ctrl+]` and
`:Gtags` (so `\c`) fall back to searching the project's sources for whatever
defines it, add that file to the project files, index it, and take the jump
again - `:ProjectFilesAddSymbol` does the same on demand. Side trees - `tools/`,
`samples/`, `scripts/`, `Documentation/`, selftests - are skipped when
looking for a definition (they carry their own copies of kernel headers);
`:ProjectFilesPrune` drops such entries from a preset that already has them. Adding a file
brings the headers it includes and the files defining the symbols it uses
along with it, so this rarely has to trigger. The preset is written out
before the indexer builds its file list, so even the very first index of a
project obeys it.

Dropping the last entry switches the project to `none` rather than leaving
an empty list behind; the index that was there is left as it is and nothing
is rebuilt (see "none means none" below).

Adding, dropping or switching reindexes immediately (an incremental
`gtags -i`, which also drops what left the list), and saving a file that is
NOT in the preset does not sneak it into the index. Which preset a project
uses is remembered in `<root>/.tags/preset` and applied again when nvim
starts; `g:projectfiles_preset` names the one to fall back on for a project
that has none yet. Adding a path while in auto mode starts a preset for you.

### Which files count

Three places decide, and they are kept in step - `indexfiles.sh` for the
generated lists, `projectfiles.lua` for presets, `autoindex.lua` for
deciding whether a save is worth an index update. If they drift, auto
mode and preset mode index different files.

**Everything, minus what is not worth having.** An allowlist of extensions
means every new kind of file is missing from the index until someone
notices and adds it, so it is the other way round: every file goes in, and
a denylist takes out the build output and binaries - `.o .so .ko .a`,
archives, images, media, `.pyc`, `tags`, `GTAGS`, and the like. Those
would be tens of thousands of entries nobody ever opens.

Files with no extension are in, which is how `Makefile`, `Kconfig`,
`INSTALL` and a bare script get there. So are names with spaces and
non-ASCII names - `git ls-files` is run with `core.quotepath=off`, without
which a Korean filename comes back as `"\355\225\234…"` and cannot be
opened or indexed.

Pruning directories does far more than any extension list. Measured on
the QNX+Android SDK tree: "every file" was 222,616 of which **221,151
were under `android/out/`** alone - Android build output. So `out` is
pruned by default, and the same tree comes back as 1,465 files. `build`
is *not* pruned: here `android/build/bazel` holds real sources.

```
.git .svn .hg .tags node_modules __pycache__ .repo .ccache out
```

The prune list is also handed to git as `--exclude`, because `--others`
has to walk a tree to know what is untracked and filtering afterwards is
too late. On that tree: 489,302 files in 2,978 ms plain, 63,211 in 617 ms
with `--exclude=out`, 1,491 in 62 ms adding `.repo`. A `:(exclude)`
pathspec made no difference - it filters after the walk. End to end the
list went from 6,314 ms to 1,051 ms.

For the kernels the two modes are close - `kernel/common` 82,272 files
against 79,343, samsung-kernel 56,181 against 53,717 - so "everything"
costs about 4% there and finds the scripts, configs and docs that were
missing.

```vim
let g:projectfiles_all_files = 0              " back to the allowlist below
let g:projectfiles_exclude_exts_extra = 'log bak'
let g:projectfiles_prune_dirs = '.git out build'
```
```sh
INDEXFILES_ALL=0                              # the same, for the script
INDEXFILES_EXCLUDE_EXTS_EXTRA='log'
```

The allowlist is still there for `all_files = 0`:

```
sources     c cc cpp cxx h hh hpp hxx s S java kt kts rs aidl
scripts     py pl sh bash zsh ksh awk lua vim tcl
build       mk mak cmake gradle pro bp bb bbappend bbclass inc
device tree dts dtsi
config      xml json yaml yml toml ini cfg conf properties env rc reg
text        md txt rst
link/misc   ld lds def map te pc
by name     Makefile makefile GNUmakefile Kconfig Kbuild BUILD
            WORKSPACE Dockerfile README LICENSE NOTICE
```

What gtags reads for *symbols* is a smaller set - C, C++, Java, assembler.
The rest (`.py`, `.xml`, `.json`, `.bp`, `.bb`, `Makefile`, and `.dts`
before them) are in the list so `\fo` finds and opens them, and ctags
(`gutentags`, `:CtagsIndex`) does read Python, Java and Make. Measured:
a `.java` file's class and methods come back from `global`; a `.py` file's
do not.

```vim
let g:projectfiles_exts  = 'c h cpp java'      " extensions
let g:projectfiles_names = 'Makefile Kconfig'  " matched by name
```
```sh
INDEXFILES_EXTS='java' INDEXFILES_NAMES=''     # the same, for the script
```

### Whose list am I editing

Every add and remove says where it landed, and the pickers say it in
their title:

```
추가: sound/soc/x.c  →  ~/work2/…/d5_qnx_hyp/.tags [qnx_hypervisor_ivi_sdk_d5]
```

That is the project's database directory and the preset in use. It is
there because the answer is not always obvious: a path decides its own
project, and a subdirectory with its own `.tags` is its own project.

Which is why the project is anchored to the directory nvim was started
in. If the cwd is a project and the path is inside it, that project wins -
so working in an outer tree keeps `\fo`, `\fx`, `:ProjectFilesAdd` and the tree on the
outer tree's list even where a subdirectory has an index of its own.
Without it, adding `child/src/c.c` from the parent went into
`child/.tags`. NERDTree's marks follow the tree's own root for the same
reason.

```vim
let g:projectfiles_anchor_cwd = 0   " let each path pick its own project
```

$HOME and `/` never anchor - a directory with no project marker would
otherwise swallow everything under it.

### A project inside a project

A directory under the tree that has its own `.tags` is a separate project,
and its files are left out of this one's list. Put them in both and the
same file lands in two indexes - and a list built from the outer tree
looks like it is overwriting the inner project's preset. That is not
hypothetical: a preset saved from an outer tree turned out to hold 638
paths that only exist in an inner one.

This applies to the lists that are *generated* - auto mode's `git
ls-files` and `find`, and `cscope.files`. What you put in a preset by hand
is kept, nested or not: an explicit choice outranks the rule, the same
reason `.indexfiles` is left alone. Adding such a path says which nested
project it belongs to and adds it anyway.
`let g:projectfiles_nested_presets = 1` filters preset entries too.

It is re-checked every time a list is built (a `find` bounded by
`g:projectfiles_nested_depth`, default 6, and a two-second cache so one
build does not repeat it), so a nested `.tags` that appears later takes
effect from then on. `INDEXFILES_NESTED_DEPTH=0` or
`let g:projectfiles_nested_depth = 0` turns it off entirely.

Getting this wrong the first way round emptied a project's index: the
preset's paths all lay inside a nested project, so filtering them left no
files, an empty `.tags/files` reads as "index nothing", and a 22-file
index became 0. `materialize()` now refuses to write an empty list when
the preset has entries - it says the paths did not expand here and leaves
both the list and the index alone.

When a path you name belongs to a *different* project than the one you are
looking at, that is now said out loud - a path decides its own project so
that the tree window works, but the switch used to be silent, which is how
a preset ends up full of another tree's paths without anyone noticing.

### Reclaiming the index's own space

`gtags -i` puts changed files back into the database but never gives the old
space back, and nothing was rebuilding from scratch - the coverage guard that
refuses to shrink an index (autoindex.lua) also refuses the rebuild that
would compact it. So the databases grow forever.

Measured on `kernel/common`, which had been incrementally updated for weeks:

| | list | files in db | GTAGS | GRTAGS |
|---|---|---|---|---|
| before | 273 | 205 | 707 MB | 551 MB |
| after `:GtagsCompact` | 273 | 205 | **656 KB** | **2.1 MB** |

Same files, same answers - `global -d device_create` still lands on
`drivers/base/core.c:4418`. It took 0.3 seconds. For scale, the outer project
holds 1091 files in 2.3 MB of GTAGS, about 2 KB per file; `kernel/common` was
carrying 3.4 MB per file. Every `global` query there was searching 1.25 GB of
mostly-dead index.

A rebuild now happens by itself, whichever comes first:

```vim
let g:autoindex_compact_every = 200      " incremental updates (0 = never)
let g:autoindex_compact_bytes = 262144   " bytes of db per file (0 = never)
```

256 KB per file is a hundred times the healthy rate, so it only fires on real
bloat. The rebuild goes into a temporary directory and is moved in when it is
complete, so queries keep being answered from the old database while it runs -
and the incremental update that triggered it finishes first, because `build()`
takes the same lock that update was holding. `:GtagsCompact` does it now.

### Lookup References

Source Insight's Lookup References: find text, but only inside the files the
index covers. With a preset, that is exactly the code you chose to care about,
which is what makes it different from a tree-wide grep.

`global -g` already does it - it greps the indexed files - and
`--result=ctags-mod` hands back `path\tline\ttext`, which is the format the
panel already parses. So there is no second search tool to keep in step with
the list, and nothing to leave running. 131 hits over 1091 indexed files came
back in 0.068 s.

| | |
|---|---|
| `\fr` | the word under the cursor |
| `\fF` | type a phrase |
| `:LookupReferences [text]` | plain text |
| `:LookupReferences! [regex]` | the bang makes it a regular expression |

Where the list lands depends on what is open. With the relation window up it
goes there, grouped by file (`group_refs` falls back to grouping by path when
a hit has no enclosing function, which is exactly the Source Insight shape),
and `<CR>` jumps. The cursor starts on the first hit, so the context view
shows it straight away - it used to stay on whatever row the previous list
had it on, often a header, and the context view kept showing the old file.
(With the context view closed it waits on the section line instead, so the
first `Ctrl+n` goes to the first hit.) Resting on the word you searched for
keeps the list (the pin only lets go when you rest on a different symbol);
`p` or `:RelationViewUnpin` brings that symbol's relation tree back.
With the panel closed it goes to the quickfix list instead. Both lists carry
absolute paths, so they resolve wherever the cwd happens to be: started in a
directory that holds several checkouts (above every index root), the panel
used to read `global`'s root-relative paths against the cwd and the context
view stayed empty. The Definition section is dropped for a text search - it
is a string, not a symbol, and `(no definition)` was just noise. The text
list is not cached as the symbol's tree either: resting on that symbol later
shows its Definition and Callers again, not the old hits.

`Ctrl+/` works from the side windows as well (quickfix, the RelationView list,
the context view, aerial, neo-tree). The index it searches is the one over the
file that window points at - the entry under the cursor, the file the context
view shows - not the current directory: a list window is not a file, and
falling back to the cwd searched the wrong index (or none) whenever nvim was
started somewhere else.

### Borrowing a nested project's list

Sometimes the files you want are the ones a nested project already picked -
you are working in the outer tree, but the list lives in
`kernel/common/.tags`. `:ProjectFilesAbsorb` copies those in, rebased on
the current root, so `child/.tags/files` holding `src/b.c` becomes
`child/src/b.c` here.

What comes across is the nested project's *index list*, file by file, so
re-expanding it here cannot change what it contains.

A nested project with no list used to come across as one directory entry -
"that tree, whole". That is now off by default, because of what it did on
the tsnd SDK. `maincore/bootable/bootloader/u-boot/.tags` was an empty
directory - no `GTAGS`, no `preset`, no `files`, the shell of an aborted
run - and an empty `.tags` reads exactly like auto mode. That one entry
expanded to the whole u-boot tree: the list went from 6 files to **19,581**,
and gtags indexed 19,200 of them. With it skipped, the same absorb takes 257
files from `kernel/common` and the list is 263. If you do want a whole
nested tree, `:ProjectFilesAdd` on that directory says so out loud.

Why this matters more than it sounds: the SDK root and `kernel/common`
*share one preset by name*, and a preset holds paths relative to a root. Of
its 102 entries, 98 began `drivers/`, `sound/` or `include/` - written while
working inside `kernel/common` - and 4 began `kernel/` or `maincore/`.
So the root materialised 6 files and `kernel/common` materialised 257, out
of the same list. Absorbing rebases the 257 onto the root, and both roots
keep working: each materialises the entries that exist under it.

Running it twice is a no-op - entries already present are skipped.

```vim
let g:projectfiles_absorb = 1        " do it when a project is first opened
let g:projectfiles_absorb_hint = 0   " not even the notice
let g:projectfiles_absorb_whole = 1  " take listless nested trees too
```

`.vimrc` turns `absorb` on. Fuzzy find at SDK level is slow enough to be
unusable, so the list gets built in a subdirectory where it is fast - and
then it has to reach the root by itself, or it never does.

### none, auto, or a preset

One file says what a project does: `<root>/.tags/preset`.

| file | mode | what happens |
|---|---|---|
| (missing) | not decided yet | nothing. No index, no dialog, no ctags |
| `none` | none | nothing, but the project is registered |
| `auto` | auto | the whole project (`git ls-files` / `find`) |
| `<name>` | preset | only what that preset lists |

`<F2>` and `\fm` do the same thing: pick the mode. `:ProjectFilesPreset
none|auto|<name>` sets it without the picker. Until a mode is picked, opening
a file in that directory starts nothing - that includes gutentags, whose
`generate_on_missing` would otherwise kick off a full ctags build of whatever
tree you happened to open a file in. Older `.tags/preset` files hold an empty
line where `auto` is written now; those still read as auto.

The old behaviour was to ask, with a `vim.ui.select` on the first index of an
unknown project. Being asked is better than being surprised, but not being
touched at all is better than both, and `\fm` was always one key away.
`:Maketags` still runs what `<F2>` used to (`mktags.sh` over the current
directory) for the times you want exactly that.

Dropping the last entry of a preset, or deleting the preset you were using,
now leaves the project in `none` rather than falling back to `auto` - "there
is nothing in my list" should not turn into "index all 220,000 files".

### Which mode, decided once per project

The mode lives in one line of `<root>/.tags/preset`: empty means auto, a
name means that preset. When that file does not exist yet, nobody has
chosen - and what used to happen is that the whole tree started indexing
quietly, which on a kernel is minutes of work you did not ask for. So it
asks:

```
색인 모드 — ~/work1/_opensource/samsung-kernel
1: auto — 프로젝트 전체 (git ls-files / find)
2: preset 'default' — 151 entries
3: preset 'kernel-audio_d3_under' — 219 entries
4: 새 preset 만들기 …
5: 이번에는 색인하지 않기
```

Indexing waits for the answer, and the answer is written down, so a
project you have already decided on never asks again - it just indexes in
the mode you chose. Cancelling (`q`) records nothing and asks next time.
`:ProjectFilesMode` reopens the dialog whenever you want to change it.

All three places that can start a first index go through this - startup,
opening a file in an unindexed project, and saving in one. It never asks
when there is nobody to ask (`--headless`), and
`let g:projectfiles_ask_mode = 0` restores the old silent behaviour.

A preset is a list of project-relative paths, so choosing one whose paths
are not in *this* checkout would index nothing at all. That case is called
out rather than left to be discovered later.

### Editing the list from NERDTree

`.vim/plugin/projectfiles_tree.vim`. On a node in the tree:

| | |
|---|---|
| `+` | put this file or directory in the index, and reindex |
| `-` | take it out |
| `=` | say whether it is in, and which mode this project is in |
| `m` | the usual NERDTree menu, with an `(i)ndex` submenu holding the same three plus "mode" and "index now" |

In preset mode the tree marks what is in the index, so you can see the
shape of a preset while you build it (`[●]` a file that is in, `[·]` a
directory with indexed files under it; auto mode marks nothing, since
everything is in):

```
▾ [·]src/
    [●]a.c
    [●]b.c
    a.c            <- after '-' on it
▸ docs/            <- nothing indexable under it
```

The marks belong to the project you are *in*, not to the one the tree
happens to be pointing at. Open the tree inside a subdirectory that has
its own `.tags` and you still see the current directory's list, rebased -
`nested/other.c` from the outer preset is marked, while the inner
preset's `deep/d.c` is not. Otherwise one screen would be showing two
different indexes at once. `:cd` re-decides it on the next render.

The marks are red (`#cc0000`, the red this theme already uses for
`ErrorMsg` and `DiffDelete`) and bold. They started out linked to `Special`,
which in `sourceinsight` on a light background is plain black - the mark was
there and you could not see it. `g:projectfiles_mark_hl` points them at a
different group, `g:projectfiles_mark_color` just changes the colour.

While we are here: the **orange, italic** names in neo-tree are not ours -
that is `NeoTreeGitUntracked` (`#ff8700`), a file git is not tracking, and
`NeoTreeGitConflict` shares it. Modified files are teal (`#007373`,
`NeoTreeGitModified`).

The same three keys work in **neo-tree**
(`.vim/plugin/projectfiles_neotree.lua`), visual range included. Both trees
read `g:projectfiles_tree_add_key` and friends, so a key changed in one
place changes both, and both call the same entry points
(`_G.projectfiles_add` / `_remove` / `_status`) - so a range is one commit
there too. neo-tree shows the same marks: `[●]` for a file in the list, `[·]` for a directory with listed files under it, and nothing in auto mode. A visual range goes to `_G.projectfiles_add_many` / `_remove_many`, so each project gets one preset write, one list update and one reindex.

Select lines with `v`, `V` or `<C-v>` and `+` / `-` act on the whole
range - though `<C-v>` only started working in the F6 buffer list and in
netrw once the check stopped reading `mode() == 'v' or mode() == 'V'`.
Blockwise visual answers `mode()` with a literal CTRL-V (`"\22"`), which
matched neither, so the range quietly collapsed to the cursor line: you
selected six buffers, pressed `+`, and one went in. Measured over a
four-line selection, the old check returned `4..4` for `<C-v>` where `v` and
`V` both returned `1..4`. NERDTree was never affected - it reads the `'<`
and `'>` marks, which all three modes set. That is one commit, not one per line: adding a path rewrites the
preset, re-expands the list (a `find` per directory entry) and reindexes,
so doing it fifty times over would be fifty of those. A six-line range
takes 79 ms where the same six done one at a time take 200 ms, and it
reports once - `추가 3개 (항목 0 -> 3)` - instead of once per line. The
tree root line is skipped if the selection catches it, since indexing the
root would make the preset the whole project.

The line *above* the root was the one nobody checked. NERDTree's third line
is `.. (up a dir)`, and `getPath()` answers it with the parent directory -
outside this tree entirely. `drop_root` could not catch that, because the
parent is not the root of anything it knows; worse, `tree_apply` takes the
project to commit to from the first path in the list, and with `..` first
that is a different project. So `V G +` down the whole tree used to hand
over the project's parent as well. The tree is the only place that knows
where its own root is, so the rule lives there now: a path must be the root
or under it, and in a *range* the root itself drops out too. Measured on a
nine-node tree, `V G +` hands over exactly the nine nodes under the root and
says `색인 추가: 9개`; `+` alone on the root row still means the root.

One thing they all share is *which* project they act on, and that used to
depend on the window you were standing in. `cur_root()` looked at the
current buffer's name and, finding none, went straight to the cwd - and a
tree window, a telescope prompt and a quickfix window all have nameless
buffers. So `+` on a node added to the project in the tree while `\fo`
pressed in that same window listed the cwd's project instead: the entry
was there on disk, in `.tags/files`, of the project you were looking at,
and the picker was reading a different one. It now asks the tree for its
root first, then a real file buffer in the tab, then the most recently
used one, and only then the cwd.

Every change reindexes by itself - from the tree, from `\fo` / `\fx`,
from the commands. It used to go through `:GtagsIndexRefresh!`,
which works out the project from the *current buffer* and falls back to
the cwd; called from the tree window or a telescope prompt that buffer has
no name, so the refresh went to whatever project the cwd happened to be
in, or nowhere. autoindex now takes the root directly
(`_G.autoindex_refresh`), and projectfiles hands it the project whose list
it just changed.

`:'<,'>ProjectFilesIndexAdd` and `:'<,'>ProjectFilesIndexRemove` are the
same thing as commands. The visual marks and the cursor survive the
redraw, so `gv` reselects and a second range command still works.

Adding to a project in auto mode starts a preset named after the
directory; removing the last entry goes back to auto. The marks use
NERDTree's own flag API (`NERDTreePathNotifier` + `flagSet`) in their own
scope, so they sit next to nerdtree-git-plugin's rather than fighting it,
and the lookup is a cached set so it costs nothing per node.

```vim
let g:projectfiles_tree = 0            " turn the whole thing off
let g:projectfiles_tree_marks = 0      " keep the keys, drop the marks
let g:projectfiles_tree_add_key = '+'  " and _remove_key / _info_key
```

### One keystroke can drop hundreds of entries

`-` on a directory takes out the files under it too. That is the rule you
want - you put `src/` in with one key, you take it out with one key - and
it is what `remove_path` has always done:

```lua
-- removing a directory drops the files under it too
if e.path == rel or e.path:sub(1, #rel + 1) == rel .. '/' then
```

What was not intended is how quiet it was. A single `-` on
`arch/arm64/boot/dts/telechips` removed 487 entries from a preset and said
only `제거: arch/arm64/boot/dts/telechips`. The write itself is an in-place
truncate, so there was nothing left to compare against and nothing to undo -
the loss was found days later by counting entries against a copy in git.

Four things now stand in the way of that:

| | |
|---|---|
| the count | `제거: <path> (항목 487개)` - the message says how much went |
| a question | asks first when the preset entries deleted plus the files excluded from a directory entry that stays reach `g:projectfiles_confirm_drop` (20). `-` on a whole directory entry deletes one entry and does not ask, however many files it held; the root entry `.` asks by the files it drops. A visual range does not ask per line: it reports the total once at the end; headless says it (WARN) and continues |
| a copy | every write keeps the previous file under `<presets>/.backup/<name>.<stamp>.json`, newest 20 (`g:projectfiles_backups`) |
| a way back | `:ProjectFilesRestore` lists those with their entry counts and the delta against now; `:ProjectFilesRestore 20260909-004155` takes one straight away |

The copy is taken on the path that used to lose the most, too: dropping the
last entry deletes my copy of the preset and switches the project to none,
and that delete now backs up first. It also writes the name to
`.tags/preset.last`, because the restore needs a name and none mode has
none - so `:ProjectFilesRestore` still works right after the list went
empty, and turns the preset back on when it restores.

Two smaller things that came out of the same reading. Entries are
normalised and deduplicated on write: `grep -rl … .` answers with `./` on
the front, `add_for_symbol` stored that verbatim, and a `./x` entry could
not be matched by `x` - so it could not be removed and a second copy of it
could be added. Taking one file out of a directory entry
used to rewrite the entry as the files that remain (21 doubled entries under
`sound/soc/telechips_dpcm/` came from that); it now keeps the entry and
records the path under `"exclude"` - see "Dropping one file out of a
directory" below.

### What the list costs to build

Opening nvim in a preset project builds `<root>/.tags/files` before the
first keystroke, and on the dev server that was **9.2 of the 9.6 seconds**
nvim took to start. Two separate things were wrong.

The larger one was not this code at all: an orphaned recursive `ugrep` over
`$HOME`, left behind by a tooling session, had read **727 GB** and was
sitting in uninterruptible I/O. It was evicting the page cache as fast as
anything could fill it, so every `find` here ran cold. Killing it took the
machine's load from 14.8 to 0.9 and this startup from 9,216 ms to 674 ms.
Worth remembering when "vim got slow" and nothing in vim changed: measure
the machine first.

What remained was real, and it was the shape of the walk. `expand_entry()`
ran one `find` per directory entry, and the preset for the QNX SDK has 17 of
them. Forking a shell costs in proportion to the size of the parent, and a
loaded nvim is not small:

| | |
|---|---|
| `find` × 17, one per entry | 118 ms |
| `find` × 1, all 17 roots at once | **26 ms** |
| files found | 1,992 either way |

`find` takes as many starting points as you give it, so directory entries
are now expanded together in one call (split into batches if the command
line would get near `ARG_MAX`). File entries still go through
`expand_entry()` one at a time - there is nothing to batch there - and which
entries are directories is decided by `fs_stat`, not by the `kind` written
in the preset, because the preset records what was true when it was saved.

Two smaller ones. `rel_to()` called `fnamemodify(':p')` on every path, 1,452
crossings of the eval bridge to normalise paths that `find` had already
handed over normalised; it now skips that when the path is plainly absolute
already. And `materialize()` ran twice on every start - once while the
plugin is sourced, once 200 ms later on `VimEnter` - so the second one is
skipped when the project and preset have not changed since the first. The
`VimEnter` pass still exists for the case it was written for: the real
project only being known once the session is up.

Sourcing the plugin in that project went **153 ms → 88 ms**, and the file it
writes is byte-for-byte the same 1,452 lines.

### Adding and dropping is incremental

`+` and `-` (tree, `\fo` / `\fx`, quickfix, buffer list, the `:ProjectFiles*` commands) change only what changed. Adding a file costs one `stat` and the binary check. Adding a directory runs one `find` over that directory. Dropping a path removes it, and everything under it, from the list without touching the disk. The list is then written once, and only if its content changed. It is written next to `.tags/files` and renamed into place, so the indexer never reads a half-written list.

Before, every `+`/`-` expanded the whole preset twice: a `find` over every directory entry plus a `stat` of every listed file, once in projectfiles and once more when autoindex asked for the list. Measured on a 6,500-file preset, one `+` took 13,000-43,000 `stat` calls and 0.23-0.42 s. With 100 µs added to each `stat` to imitate the Linux server it took 1.7-4.7 s. Now it takes 40-46 `stat` calls and 14-30 ms either way. A 50-line range into a 6,000-entry preset went from 0.7 s (4.6 s on slow stat) to 40-90 ms. The preset is written once per range, not once per line.

The whole list is still re-expanded by `:ProjectFilesReindex` (`\fR`, now in the background too - see "`\fR` no longer freezes the screen" below), by a preset or mode switch, and once per session in the background (see below). One thing is given up: a file that appears under a directory entry while nvim is running (`git pull`, a build) is no longer picked up by the next unrelated `+`. `\fR` picks it up, and so do saving it, `+` on it, and the next start.

`+` on a file that a directory entry already covers no longer adds a redundant file entry; it says `이미 있습니다`. If the file is new and not in the list yet, it goes into the list and the preset stays as it is.

### Dropping one file out of a directory

`-` on a path under a directory entry keeps the directory entry. The path is recorded in the preset's new `"exclude"` list:

```json
{
  "name": "kernel",
  "entries": [
    {"kind": "dir", "path": "include"}
  ],
  "exclude": [
    "include/linux/foo.h"
  ]
}
```

It used to rewrite the directory as one file entry per remaining file. One `-` turned `include/` (6,000 headers) into 6,001 entries and a 350 KB preset, and made every later `+`/`-` three times as slow. It also meant that files created later in that directory were never added on save.

The closest rule wins, walking up from the file:

- `+` on an excluded path takes the exclusion away (`다시 넣음`).
- With `include/linux` excluded, `+` on `include/linux/bar.h` adds just that file.
- `+` on `include/linux` or `include` takes away every exclusion under it.
- `-` on the directory entry itself drops it together with its exclusions.
- A second `-` on an excluded path answers `목록에 없습니다`.

Exclusions follow renames, and `:ProjectFilesRestore` brings them back with the rest of the preset. `"exclude"` is written only when it is not empty, so presets without exclusions are byte-for-byte what they were. An older vim-ide checkout ignores the key and indexes the excluded files again; nothing breaks, and its next save of that preset drops the key. Presets that already split into file entries are left as they are.

### Starting nvim does not re-read the list

The plugin no longer expands the preset while it loads. If `<root>/.tags/files` exists it is used as it is. Once the screen is up, one background check expands the preset again: `find` runs in a child process, the per-file `stat` runs on the main loop in 8 ms slices, and the list (and the index, told which files changed) is rewritten only when something differs.

`<root>/.tags/files.key` records what the list was built from: the preset's contents and the settings that decide what is listed. A file that was in a list built that way, and whose inode has not changed since (ctime older than the list, minus a minute), skips the 1 KB binary check. Only new files are opened.

Measured on a 6,500-file preset:

| | before | after |
|---|---|---|
| sourcing projectfiles.lua | 0.6-1.1 s | 3 ms |
| first screen | 0.84-1.29 s | 0.21-0.25 s |
| first screen, 100 µs per stat | 2.6-2.7 s | 0.25-0.27 s |
| longest freeze in the first seconds | 0.49-0.89 s | 50-60 ms |
| files opened per start | 6,506 | 6 |

The list is still built before the screen when it is missing (gutentags reads it at the first `BufReadPost`). It is also rebuilt then when it belongs to a different preset (the mode was switched elsewhere). A list built from an older version of the same preset, for example after a `git pull` changed a shared preset, is used and corrected in the background.

### Messages: one line per action

Every `ProjectFiles` command (`:ProjectFilesAdd`, `AddDir` and `Remove` with an argument, and the rest), every tree key and every picker action prints one line. Two lines inside an Ex command raised `Press ENTER`, and while that prompt is up nvim runs no scheduled callback. The `gtags -i` that follows a change waited for the key: 3-16 s measured.

The separate `색인 대상: …` line is gone, because every result line already ends in `→ <root>/.tags [preset]`. When the path belongs to another project than the one you are looking at, `(보고 있던 곳: …)` is added to the same line. The mode dialog redraws before it reports.

### `:ProjectFilesAdd <file>`

The related files (headers, files defining the symbols it uses) are worked out first and added together with the file in one commit: one preset write and one refresh, reported as `추가: x (+연관 파일 N개, 항목 a -> b)`. In preset mode the index is not asked: it is built from the list, so it can only name files already in it. Headers next to the file are still found. In auto mode, all `global -P` / `global -d` queries run in one child process instead of one nvim fork each (up to 60 before). Files already in the list, including those under a directory entry, are not added again as file entries.

### none means none

Dropping the last entry, or the last ones that exist in this checkout, switches the project to `none` and no longer starts a refresh. That refresh found no list and indexed the whole project through `git ls-files` (50 → 6,500 files while in none mode); gutentags did the same for ctags. The existing index is left as it is. `:ProjectFilesReindex` in none or unset mode says so instead of indexing. This replaces the older sentence "Dropping the last entry puts the project back in auto mode".

### Smaller changes

- New Lua entry points: `_G.projectfiles_add_many(paths)` and `_G.projectfiles_remove_many(paths)`. They take absolute paths from any number of projects, group them by project and commit once per project. `_G.projectfiles_add` / `_G.projectfiles_remove` with a list now do the same; before, every path went to the first path's project. Ranges, `<Tab>` selections and quickfix use this.
- The index refresh after a change is told which files entered and left the list: `_G.autoindex_refresh(root, true, why, { added = {...}, removed = {...} })`.
- Saving a new file under a directory entry adds that one file to the list without re-expanding. Before this took 0.36 s on the kernel index, and longer as the list grows. This also works for a root (`.`) entry and respects exclusions. Paths under pruned directories (`.git`, `out`, …) are never added this way.
- `+` checks whether a path is inside a nested project by looking for `.tags` on the way up: at most `g:projectfiles_nested_depth` `lstat`s instead of the whole-tree `find`. The first `+` after anything changed the root directory used to wait for that `find`: 0.2 s to 8 s. `+` on the nested project's directory itself now says so too. The startup scan for nested projects is skipped in unset and none projects; it used to create `<root>/.tags`, even in `$HOME`.
- `=` answers from the same set as the tree marks: 20 presses on a 6,000-entry preset took 83 ms and now take 4-17 ms. It also names `none` and `미설정`.
- `\fM` counts how many entries exist in this tree by reading each parent directory once instead of a `stat` per entry.
- Preset JSON and `.tags/preset` are read once and remembered until the file changes. One `+` used to parse the same preset 4-9 times.

### Keeping the index in step with + and -

A change to the list now reaches GTAGS by the shortest route, and is never lost.

**Adding is immediate.** autoindex keeps a copy of the list the database was last built from, `.tags/files.indexed`. Its first line records the state of GPATH, which only changes when files enter or leave the database. When a `+` only adds a few files (up to `g:autoindex_fast_add_max`, 8), those files go in one at a time with `global --single-update`, which takes tens of milliseconds whatever the size of the list. No `gtags -i` follows. `Ctrl+]` pressed right after `+` waits for that, up to `g:autoindex_tagfunc_wait_ms` (1500 ms, 0 = never), instead of answering from the old database. Before, it said "정의를 찾지 못했습니다" or landed on the prototype. A `-`, or a larger change, still runs `gtags -i` on the list, because single-update cannot take a file out. When the list matches the copy, nothing runs. If something outside autoindex changed the database's file set, the copy is not trusted and `gtags -i` brings the database back in line with the list.

Measured on a 6,500-file preset: from the key to the database holding a new file went from 0.84 s to 0.12 s. autoindex's own work on the keypress went from 67-70 ms (6,500 `stat`s) to 7-15 ms (about 20 `stat`s). With 100 µs per `stat` it went from 0.72 s to about 10 ms.

**The preset list is read as it is.** In preset mode autoindex reads `.tags/files` itself and gives a snapshot of it to gtags, without `indexfiles.sh`. `indexfiles.sh` also prints `.tags/files` without checking it again (gutentags uses it on every save). `projectfiles.lua` has already removed binaries and files over the size limit. The check took 0.5-0.9 s at 6,500 files and now takes 0.03 s. Set `INDEXFILES_TRUST_LIST=0` to filter it again. `.indexfiles`, `git ls-files`, `cscope.files` and `find` keep their filters.

**Nothing is dropped when another nvim is indexing.** A list change made while another nvim holds `.tags/.autoindex.lock` used to be skipped silently: the tree showed `[●]`, but `global` never found the file. Now it waits until the lock is free and then applies the change. It checks every second for the first 30 seconds, then after 2, 4, 8, 15 and 30 seconds and every 30 seconds from then on, and says once: `… 은 다른 nvim 이 색인 중 (pid@host) - 끝나면 반영합니다`. Every forced refresh also leaves `.tags/refresh.pending`, which is removed only once the database has been built from a list read after the request. That covers three cases:
- If you quit before the refresh ran, the next start applies it.
- If the other nvim finishes first, it runs once more for you, even if you have already quit.
- If the refresh fails, it is retried twice (after 2 s and 30 s), and after that the next start tries again.

`:GtagsIndexRefresh!` also waits rather than skipping. `:GtagsIndexStatus` lists what is waiting, what is queued, and any pending request.

**A preset list is followed, not second-guessed.** The rule "an automatic refresh that would shrink the index by more than half is skipped" no longer applies to a preset's list. Presets are shared between projects and machines. When a preset was trimmed elsewhere, every later start printed `색인 6430개 -> 266개 축소, 자동 갱신 생략` and went on answering from removed files. Now it prints one line, `색인 N개 -> M개 (preset 목록을 따름)`, and follows the list. The guard still applies to `git`, `cscope.files` and `.indexfiles` lists, and its message now suggests `:GtagsIndexRefresh!`.

**Fixes that came with it:**
- Removing the last entry of a preset (none mode) no longer indexes the whole project through `git ls-files`. The same applies to a preset whose list could not be written.
- Switching to an empty preset now empties the database instead of leaving the old index answering.
- Starting nvim in a preset project no longer runs `indexfiles.sh` at all (it ran three times at 6,500 files). In auto mode, the three callers at startup now share one run.
- The list cache that decides whether a saved file belongs to the index now notices rewrites within the same second. A file removed with `-` and then saved no longer creeps back into the index.
- A queued forced refresh is no longer turned into a plain one by a later `:GtagsIndexRefresh`.
- Saves (`global --single-update`) take the same lock as `gtags -i` and never run at the same time as it, in this nvim or another.
- With the gutentags cache under `/tmp`, the big-tree ctags snapshot was rebuilt on every start, because `'wildignore'` hid the path. It is now written once.

**ctags follows the list.** After `+`/`-` from any place (the tree, quickfix, telescope, the command line), the tags file of that project is refreshed in the buffer gutentags manages for it. If an update is already running, one more runs after it, so quick `+ +` both arrive. Buffers opened before a mode was picked get gutentags attached first. Big trees that gutentags does not handle keep their weekly snapshot (`:CtagsIndex`). Set `g:autoindex_ctags_follow = 0` to turn this off.

For plugins:
- `User VimIdeIndexUpdated` fires after every change that reached the database, with `data = { root, kind = 'build' | 'update' | 'single', paths }`.
- `_G.autoindex_refresh(root, force, why, changes)` takes `changes = { added = {…}, removed = {…} }` (absolute paths); `nil` means a full refresh.
- `_G.autoindex_ctags_refresh(root)` and `_G.autoindex_single_update(root, paths)` route through the same queue and lock.

```vim
let g:autoindex_fast_add_max = 8        " adds put in one by one (0 = always gtags -i)
let g:autoindex_tagfunc_wait_ms = 1500  " Ctrl+] waits for a + still going in
let g:autoindex_ctags_follow = 1        " refresh ctags after a list change
```
```sh
INDEXFILES_TRUST_LIST=0                 # filter .tags/files again in indexfiles.sh
```

### Marks in neo-tree cost nothing per row

The marks are no longer part of neo-tree's rendering. The `projectfiles_index` component in the neo-tree setup only reserves the column: a blank of constant width, the mark plus one space. A decoration provider then overlays the mark on the rows that are actually on screen, when they are drawn. Before, the component worked out the mark for every row whenever neo-tree rendered, and a `+` or `-` re-rendered the whole tree twice. Each row stat'ed `.tags/files`, and after a change each row ran `realpath` again.

Measured per `+`/`-` with 2,090 rows expanded (one 2,000-file directory):

| | before | now |
|---|---|---|
| neo-tree re-renders | 2 | 0 (only the tree window is redrawn) |
| `fs_stat` / `realpath` in the tree's part | 4,195 / 2,090 | 6 / 0-1 |
| list changed -> mark on screen | 124-145 ms | 1-6 ms |
| same, with 0.1 ms added to every stat (slow server) | 753-788 ms | 1-5 ms |
| expanding the 2,000-file directory | 2,077 stats + 2,031 realpaths | 26 stats + 2 realpaths (neo-tree's own) |

The cost now depends on the window height. It no longer depends on how many rows are expanded or how long the list is: 300 and 6,500 listed files measured the same. With the slow-stat setting, the index on a 300-file preset also caught up sooner, 258-264 ms after the key instead of 913-929 ms. The main loop is no longer held up by the two re-renders.

- The list file is stat'ed once per draw, not once per row, and the check includes nanoseconds and size. A list rewritten by another nvim shows up at the tree's next redraw.
- Real paths are cached per directory and kept when the list changes. Only nodes that are links themselves, or of unknown type, are resolved one by one. Files under a symlinked directory are still marked.
- Marks follow the list, not the index. A `+` or `-` in the tree redraws the tree window inside the key, and the index catches up in the background. The tree window is also redrawn, only if the list or the project actually changed, when:
  - the list is changed elsewhere (quickfix, RelationView, `:ProjectFilesAdd`);
  - you `:cd`;
  - an index refresh rewrites the list (`User VimIdeIndexUpdated`), for example new files under a directory entry after a `git pull`.
- The column has a constant width, so names line up. Before, neo-tree put an extra space after `]` on marked rows only, so marked names sat one column to the right of unmarked ones. Unmarked rows now move one column right instead.

There are no new options. `g:projectfiles_tree_mark_file` / `_mark_dir`, `g:projectfiles_mark_hl`, `g:projectfiles_mark_color` and `g:projectfiles_neotree = 0` work as before. The column widens by itself for a wider mark glyph. Marks in neo-tree need nvim 0.10 or later, which `projectfiles.lua` already requires.

### Saves, renames and preset names

**Saving a new file keeps the index current, even mid-refresh.** A file saved under a directory entry of the preset goes into the list as before. Now it is handed to autoindex, which indexes it under the same lock as everything else, with no `gtags -i`. Before, projectfiles ran its own `global --single-update`, which knew nothing about a `gtags -i` already running. If the save landed during a refresh (the startup refresh, a `+`/`-` just before, seconds on the server), that refresh finished with the old list and removed the file again. Nothing retried, and the file stayed out of GTAGS until the next unrelated change or restart. Now the request is recorded (`.tags/refresh.pending`) and runs right after the current refresh, or after another nvim releases the lock. The same applies to "add the file that defines this symbol" (the relation window and SiHl after a failed jump). It adds the file with one single-update, without the duplicate update and the full `gtags -i` it used to cause. The retried jump waits until the file is really in the index. If autoindex is switched off (`g:autoindex_gtags = 0`) or missing, the old one-at-a-time queue is used.

**One ctags rebuild per `+`/`-`.** Only autoindex regenerates the gutentags snapshot after a list change, when its refresh ends. Each `+`/`-` used to regenerate the whole tags file twice (0.4 s each on a 3,300-file preset). When the current buffer belonged to another project, it also rebuilt that project's tags for nothing. `:ProjectFilesReindex` (`\fR`) still rebuilds ctags when the list did not change.

This also holds with two nvims. When another nvim indexed this nvim's change, this one skips its own rebuild only if the shared tags file has already been rebuilt from the current list: whoever starts a whole-list rebuild records next to the tags file which list it read (`<tags>.followed`). While a tags update is running (`<tags>.lock`), it waits and looks again. The first version went by the tags file's time instead, and a save in this nvim - gutentags rewriting the tags of that one file - counted as "already rebuilt". When the other nvim had no gutentags buffer for the project, nobody rebuilt it and the added file stayed out of ctags for the rest of the session. The first list in a project that has no tags yet now builds ctags once: gutentags' own build when it attaches counts as the rebuild, where a second whole rebuild used to follow it.

**`+` on a directory that is already in rescans it.** On a directory entry, or a directory under one, `+` runs one `find` over that directory, adds what is new and drops listed files that are gone: `다시 훑음: drivers/net (새 파일 1개, 사라진 파일 2개)`. `이미 있습니다: drivers/net (다시 훑음, 새 파일 없음)` means nothing was added or removed. Files created or deleted there by a shell, `git pull` or a build no longer wait for `\fR` or the next start. Removals reach GTAGS through `gtags -i`, because a single-update cannot take a file out. Before, a rescan only added: a deleted file stayed in the list, `\fo` still offered it and GTAGS answered from it until the next `gtags -i`, while the message said there was nothing new. With exclusions under it, `다시 넣음` also picks up the new files and drops the vanished ones. This adds "or `+` on its directory" to the list of things that pick up such a file.

A listed file that this `find` cannot reach is kept as long as it is still a regular file. That is a file another entry brings in: an entry inside a pruned directory (`drivers/net/out/gen`, `node_modules/x` - the rescan's `find` skips `out/`, the full expansion runs `find` on the entry itself), one reached through a symlinked directory, or a file entry. Only files that are really gone are dropped, so normally only those are `stat`ed. Without that check such files were dropped from the list, GTAGS and ctags while they were still on disk, with `사라진 파일 N개`; `\fR` put them back and the next `+` dropped them again. A file that `find` did return but that the rules now refuse (it became binary or too big) is dropped, the same as a full expansion does.

**`:ProjectFilesPreset <name>` only takes presets that exist.** A name with no preset file now gets one line, `그런 preset 이 없습니다: 'kp1x' (새로 만들려면 \fm 의 '새 preset 만들기')`. `auto`, `none` and the name already in use are always accepted. A typo used to switch to an empty, never-saved preset: the list was written empty, GTAGS went to 0 files, the ctags file to its 24-line header, and the message looked like any other switch. New presets are started from `\fm` / `:ProjectFilesMode` (`새 preset 만들기`) or with `:ProjectFilesSave <name>`. For autoindex, `_G.projectfiles_list_intended_empty(root)` says whether an empty list means "index nothing". It does only for a saved preset with zero entries, not for a name that was never saved.

**Moving an excluded path keeps it out.** A file or directory taken out with `-` and then renamed or moved (neo-tree `r` / `m`) stays out of the index. Moving it out of the directory entry no longer adds the new place as a file entry.

**The `-` question counts files and entries separately.** It now reads `'drivers/net/phy' 를 빼면 목록에서 파일 50개가 빠집니다 (목록 3200개 중; preset 항목은 9개 중 0개)` instead of "항목 50개 (전체 9개)". When it asks has not changed: the preset entries being deleted plus the files excluded from a directory entry that stays must reach `g:projectfiles_confirm_drop` (20). So `-` on a 50-file directory inside the `drivers/net` entry asks, and so does `-` on a directory that holds 25 file entries. `-` on a whole directory entry (`sound/soc`, 30 files) deletes one entry and does not ask, because that is the everyday `+`/`-` in the tree. Entries count even when the path is missing from this checkout, because it still disappears from the shared preset. The root entry `.` is the exception: it is one entry but the whole project (and, as the last entry, it deletes the preset and turns the project to none), so `-` on it asks when the files leaving the list reach the limit - that is the files the other entries no longer cover. When it asks, the files leaving the list are counted from the list itself.

**Adding a symbol's file while switching presets.** If the preset changes while the definition is being searched for (a few seconds of `git grep` on a kernel), nothing is added: `'sym' 정의를 찾는 사이 preset 이 바뀌어 (kp -> kp2) 담지 않았습니다`. Before, the old preset was overwritten with the new preset's entries plus the file.

**`g:projectfiles_nested_presets = 1` still checks the list at startup.** The background check after startup also runs in this mode, and drops files under nested projects the same way a full build does. Files created or deleted under directory entries between sessions used to stay wrong until `\fR`.

**No Press ENTER on the first start of a preset project.** When the list has to be built at startup and some files are skipped (`색인 제외: 바이너리 1`), that notice now comes once the screen is up. It used to stack with autoindex's `indexing …` line into Press ENTER. Until the key was pressed, the first GTAGS build (0.1 s of work) could not move its database in or release its lock.

### The index after `+`, saves and crashes

**A `+` during a full refresh costs one single-update.** A `+` made while `:GtagsIndexRefresh!`, `\fR`, a preset switch or the startup refresh is running is applied when that refresh ends, with `global --single-update` for the new file only. It used to inherit the running request's "full" flag and run the whole `gtags -i` a second time. `.tags/refresh.pending` now records which request first asked for a full pass (a 4th field). The nvim that served it clears the flag. A full request made after the pass started still gets its own full pass.

**A new file saved during a refresh is indexed after it.** Saves and "add the file that defines this symbol" now go through autoindex's own queue and lock. If a `gtags -i` is running, in this nvim or another one, the file goes in right after it finishes.

`_G.autoindex_single_update(root, paths)` works the same way:
- It uses the same queue and lock as saves.
- It waits behind a running refresh or another nvim's lock.
- It ignores files that are not in `.tags/files`.
- When a file enters the database, `files.indexed` is updated too, so the next `+` stays a single-update.
- If nvim quits while updates are still queued, `refresh.pending` is left behind and the next nvim applies them.

**`Ctrl+]` no longer stalls while a `+` is queued.** `Ctrl+]` and `:tag` answer from the current database first. They wait (`g:autoindex_tagfunc_wait_ms`, 1500 ms) only when the symbol is not found and the added file is being put in at that moment, and only once per `+`. Before, every lookup of any symbol froze for 1.5 s while the `+` waited behind another job (startup refresh, `:GtagsIndexRefresh!`, a long build).

**A list without a final newline works.** `.tags/files` written by hand, or by a script using `$(…)`, can lack its final newline. Before, autoindex treated such a list as half-written and silently retried every 300 ms for ever: no startup refresh, `:GtagsIndex` said "다른 nvim 이 쓰는 중". Now only a list changed within the last 2 seconds counts as being written. If a list keeps changing while it is read, autoindex retries for about 6 s (`g:autoindex_torn_retries`, 20) and then says so once:
`.tags/files 가 읽는 동안 계속 바뀝니다 - 색인 갱신을 미룹니다 (:ProjectFilesReindex 로 다시 쓰기)`.
`:GtagsIndexStatus` shows the retries and any queued single-updates.

**An empty list empties the index only when you meant it.** A saved preset with no entries empties GTAGS and ctags. An empty list for a name that was never saved, or for a deleted preset, leaves both alone. gutentags is not attached to such a project until the list is usable, because attaching rebuilds the tags file from that list.

**ctags only follows the list.**
- A ctags update queued before switching to `none` no longer builds tags for the whole tree.
- Saving a file that is not in the preset list (for example one removed with `-`) no longer adds its tags to the tags file. In `none` mode a save no longer rebuilds tags. Buffers stay attached, so `:tag` still works there.
- Each `+`/`-` still rebuilds tags once. That now also happens when a rebuild (`:GtagsCompact`) has already put the change into GTAGS.

**A crashed nvim cannot undo your `+`.** If an nvim is killed while indexing (SIGKILL, OOM, a dropped session), its `gtags -i` keeps running. The next nvim used to take over the lock at once, and the late `gtags -i` then removed the file that had just been added. Now `.tags/.autoindex.worker` records the indexing process. The next nvim waits for it to finish, says `… 은 다른 nvim 이 색인 중 (pid …) - 끝나면 반영합니다`, and then applies the current list.

**No Press ENTER on the first start.** autoindex notices printed while nvim starts (`indexing … (no GTAGS yet)`, `tags NMB - ctags 는 여기서 직접 만듭니다`) are shown one by one after the screen is up, and all stay in `:messages`. Two of them used to stack into Press ENTER. Until the key was pressed, the first build could not move its database in or release the lock: 0.2 s of work showed up as 150 s.

```vim
let g:autoindex_torn_retries = 20   " retries of a list that keeps changing while read (300 ms apart)
```

### Reindexing, waits and late answers

**`\fR` no longer freezes the screen.** `:ProjectFilesReindex` now expands the preset the way the startup check does: `find` runs in a child process and the per-file `stat` runs on the main loop in 8 ms slices. When that is done the list is written, the index is refreshed and the same one line comes (`재색인 시작`, with `색인 제외: …` in front when files are skipped), with the same result as before. Before, the key held the screen for the whole expansion, a `stat` per listed file. Measured on a 6,500-file preset with 100 µs added to each `stat`, the longest freeze went from 0.72-0.74 s to 15-19 ms (66-77 ms to 15-30 ms at normal `stat` speed), while the message, `gtags -i` and the ctags rebuild finish about when they did (the message at 0.74 s instead of 0.73 s). If anything changes the preset or the list while it expands - a `+`/`-`, a preset switch, a new file saved, another nvim - or `\fR` is pressed again, it starts over from what is current. Writing the older expansion would undo that change - in a test without this check, a new file saved 0.1 s into a slow `\fR` went out of the list, GTAGS and ctags again. Two `\fR` in a row now cost one `gtags -i` and one ctags rebuild, not two.

**A preset that expands to nothing is not a big tree.** A preset whose paths do not exist in this checkout (another checkout's preset, or every entry inside a nested project) is warned about once per session, after the screen is up, with no Press ENTER: `preset 'kz' 의 경로가 이 프로젝트에서 하나도 펼쳐지지 않았습니다 …`. Every caller that looked for the list used to expand it again and say it again - five times in one session, twice before the screen came up, which raised Press ENTER and held the startup refresh until a key was pressed. It also no longer counts as 'big tree': that excluded the root from gutentags, so even after the first `+` brought a file in there was no ctags at all. The choice between gutentags and autoindex's own ctags now waits until a list exists.

**Switching presets counts the files again.** Whether a project gets gutentags or autoindex's ctags snapshot (`g:autoindex_ctags_max_files`, 5000) is decided again after a preset switch. Before, the first decision lasted the whole session: switching from a small preset to a big one left gutentags rewriting the big list's whole tags file on every save, and because the count runs in the background, gutentags could already be attached to the first buffer of a big preset. A project that became big is treated as detached (saves no longer rewrite its tags; the snapshot is built from the new list). One that became small leaves the exclusion, its old snapshot is removed, and gutentags builds tags from the new list. Only what the count itself decided is undone. The tags-size guard (`g:autoindex_ctags_max_bytes`, `tags NMB - ctags 는 여기서 직접 만듭니다`) and the user's own entries in `g:gutentags_exclude_project_root` survive a switch: the project stays excluded and gutentags does not come back; autoindex rebuilds its own ctags snapshot from the new list instead (if it had one), so `'tags'` and the SiHl colours do not keep the old preset's files. The first version took any root on that list as "was big", so a switch removed those exclusions too and deleted the tags. gutentags then reattached and rewrote the oversized tags on every save (181 MB per `:w` in bcc).

**When another nvim finishes first.** A waiting nvim now looks at the lock every second for the first 30 seconds (see "Nothing is dropped when another nvim is indexing"). It used to back off from the start and looked at 1, 3, 7 and 15 s, so an nvim that finished at 8 s was noticed at 15 s: measured, 7.4 s after the other nvim finished, now 0.4 s. When the other nvim has already done what this one was waiting for, this nvim now also announces it (`User VimIdeIndexUpdated`), so the relation window's "add the defining file" retry, the SiHl colours and the tree follow at that point. Before, nothing was announced here, and the retry came only when its 20 s timeout ran out. A `:GtagsIndexRefresh` you type during such a wait runs after it, as its message says (`… 끝나면 반영합니다`). It used to be dropped without a word once the other nvim was done, even when that nvim had only put in its own added file, so edits made outside nvim stayed out of GTAGS. (One case is still missed: `gtags -i` decides by modification time, so a file edited outside nvim *before* the other nvim updated the database looks older than the database and is not read again. `:GtagsIndexUpdate` in that file, or `:GtagsIndex` (a build from scratch), takes it in.) The automatic refresh at startup is still dropped then - the other nvim has just indexed the current list.

**A `.tags` you cannot write is left alone.** In another user's tree or on a read-only mount the lock file cannot be created, and there is no lock to wait for. The startup refresh used to treat that as "another nvim holds the lock" and tried again every second for the whole session, while `:GtagsIndexStatus` showed `waiting for another nvim` with no other nvim running. Now it gives up quietly, as it did before the wait was added. A `:GtagsIndexRefresh` you type, or a first build, says so in one line (`… 의 색인 디렉터리에 쓸 수 없습니다 — 건너뜁니다`) and stops; a save there queues nothing either.

**A late answer no longer jumps.** Adding the file that defines a symbol answers only once the file is in the index: seconds behind a running refresh or another nvim's lock, at most `g:projectfiles_single_update_timeout` (20 s). The jump that is retried then is dropped if you have moved on - another jump, or a different window, buffer, line or word under the cursor. Before, a retry that came 8 s late replaced the newer jump, took the focus to the preview, and with the preview closed ran `<C-]>` on whatever word was under the cursor by then. This covers the relation window (its preview, the panel's `:Gtags` search, member jumps) and the relation view switched off, where `<C-]><C-]>` (or `<C-]>` with `g:vimide_jump_target = 'ctx'`) runs `:Gtags -d` again once the file is in: a late one filled quickfix and moved the cursor. Pressing again on the same word in the same place is not a new jump - the second add finds the file already in and answers at once, so the first request is kept and lands once. `:SiHlIndexAdd` only recolours the windows on screen when its answer comes, which is right whenever it comes.

### NERDTree's keys inside neo-tree

The file operations stay neo-tree's, because they are the reason to use it -
`a` add, `A` directory, `d` delete, `r` rename, `c` copy, `m` move, `Y`/`x`/`p`
clipboard, `u` undo, `T` trash, `U` restore. NERDTree's keys went into the
slots that were empty:

| | |
|---|---|
| `o` | open |
| `O` | expand everything under this node |
| `X` | collapse everything under it |
| `I` | toggle hidden files (`H` still does it too) |
| `K` / `J` | first / last sibling |
| `yy` | copy the name of the entry under the cursor, linewise (`3yy`, `"ayy` work) |
| `y` | vim's yank, as anywhere else: `yiw`, `y$`, and `y` on a visual or `<C-v>` block selection copy exactly the text selected |
| `Y` | put the entry into neo-tree's file clipboard (what neo-tree has on `y`), to paste it in the tree with `p` |
| `/` | search the tree, as anywhere else in vim (`n` / `N` to step) |
| `Tab` | pick two directories (or two files) to compare: `Tab` on the first marks it `[A]`, `Tab` on the second opens the comparison - see [Comparing directories](#comparing-directories-dirdiff). `\d` does the same. neo-tree had `Tab` on "select" (mark rows for a later action), which vim-ide never used; select rows with `V` instead |

`o` is the one key that was not free: neo-tree had it on help, and help is
also on `?`, so nothing was lost. neo-tree's two-key sort maps (`oc` `od` `og`
`om` `on` `os` `ot`) are dropped - they start with `o`, so `o` used to wait
`timeoutlen` before it opened anything.

The trees **follow the edit window by default** (*live path* mode): they
expand to every file you move to, with the cursor on it. `\P` switches a tree
to the *fixed* mode, where it stays where it is while you move between files,
and `\P` again goes back. There are two separate modes: one for the F9
sidebar and the F11 floating tree together, and one for the tree in the F12
RelationView column - fixing one leaves the other following. Which one `\P`
switches depends on where you press it: anywhere in the RelationView column
(its tree, the relation list or a preview) it is the F12 tree; in the F9 or
F11 tree it is those; in an edit window it is the tree you can see in the tab -
the F9 sidebar when it shows the file tree, else the RelationView tree when
that is open, else F9/F11. The message says which. `:VimIdeTreePin [on|off]`
(F9/F11) and `:RelationViewTreePin [on|off]` (F12) set one directly. Only a
mode that differs from the one you started with is marked at the top of its
tree windows (` [고정] \P 로 실시간 경로 `), so the default costs no line.
Going back to live jumps the tree to the current file at once (F9/F11 when you
are in an edit window, F12 unless you are in its tree - then it follows when
you go back to the edit window). Fixed stops only the following: opening and
expanding by hand in the tree, and an explicit `:Neotree reveal`, still work,
and a fixed tree you open does not expand to the current file - it shows the
place it was left at (its root the first time; the F12 tree keeps its place
when RelationView is closed and opened again or switches layouts). It is the
file tree that is fixed - neo-tree's buffers view (`<` / `>`) keeps
following. `let g:vimide_tree_pinned = 1` starts F9/F11 fixed,
`let g:relationview_tree_pinned = 1` the F12 tree.

`y` was not free either. neo-tree has it on its file clipboard, in normal and
visual mode, so `yy` or a `<C-v>` block `y` in the tree put nothing into a
register, and `p` in the edit window then pasted whatever was there before.
`y` is vim's yank again, and the file clipboard moved to `Y`. `yy` copies the
entry's name rather than the tree line itself - the line also holds the
indent, the tree guides, the icon and the git mark, which are no use in code;
select with `V` or `<C-v>` and `y` to get the line as shown.

`/` was not free either - neo-tree puts its fuzzy finder there. The fuzzy
finder is a fine thing, but `/` is muscle memory for *search*, and a tree you
cannot search is a tree you scroll. Setting the key to `"none"` makes
neo-tree skip it entirely (`ui/renderer.lua`, `skip_this_mapping`) so vim's
own `/` comes back, along with `n` and `N`, which neo-tree never mapped.
`"noop"` would not do: that is a mapping that does nothing, which still eats
the key. The fuzzy finder moved to `F`, and `D` (fuzzy find a directory),
`f` (filter on submit) and `#` (fuzzy sort) are untouched. The same swap is
applied to the `document_symbols` source, which had `/` on its filter.

### Searching from the tree

`Ctrl+g` and `Ctrl+f` work in all three neo-tree windows - the F9 sidebar, the
F11 float and the tree inside RelationView - and search *below the line the
cursor is on*:

| cursor on | searches under |
|---|---|
| a directory | that directory |
| a file | the directory holding it |
| blank space past the end | the tree's root |

`Ctrl+g` opens the same "찾기 (grep)" box as in the edit window, with the
directory filled in and the text left empty - what the tree shows are file
names, not words from the source. `Ctrl+f` opens a "찾기 (find)" box with two
fields, 찾을 파일 (the name) and 찾을 곳 (the directory). The name is filled
with the name of the entry under the cursor, and left empty on blank space.
Both go where the edit window's `Ctrl+g` goes: the RelationView list while the
panel is up, the quickfix window otherwise. A find result puts the cursor in
that list to pick a file. The RelationView preview shows whichever file the
list cursor is on, as it does for any list, but the edit window is left alone
until you pick one - there is no matching line to jump to.

A row that is not a real file or directory - a terminal or `[No Name]` in the
buffers source (`<` / `>` switch sources in the same window) - counts as blank
space: the search starts at the tree's root.

The name is a glob. With no `*`, `?` or `[` in it, it means "contains":
`uart` finds `tcc_uart.c` and `uart.h`. Type the wildcards yourself for
anything else - `*.dts`. Matching ignores case
(`let g:relationview_find_case = 1` to respect it), and the list stops at
1,000 files (`g:relationview_find_max`).

It runs `find(1)`, not `rg --files`, because ripgrep quietly skips whatever
`.gitignore` names and anything hidden. In a kernel tree the generated files
are in `.gitignore`, so a file that is plainly there would not be found - the
wrong answer when the question is "where is the file called this". The
arguments are the ones BSD find (macOS) and GNU find (the server) read the
same way. `.git`, `.svn`, `.tags` and `node_modules` are skipped below the
starting directory - the same four the grep fallback skips when ripgrep is
missing - but starting *in* one of them works: `Ctrl+f` on the `.tags` row
lists what is inside. Links to files are found; links to directories are not
listed.

`Ctrl+f` in neo-tree was `scroll_preview` (scrolling the preview `P` opens).
`Ctrl+b` still scrolls it the other way.

### Keeping it quick

Measured on the dev server with a 6,600-line C file (600 functions), the
stalls that were there and what took them away:

| where | before | after | what changed |
|---|---|---|---|
| scrolling, local-variable colours (`sihllocal`) | 55 ms per paint, 80 at worst | 9.6 ms, 22 | globals and per-function names kept per buffer change; top-down walk instead of `parent()` per name |
| after an edit, the same | 164 ms, 325 at worst | 9.6 ms, 22 | globals by walking the top level instead of a whole-file query |
| index colours (`sihlindex`) | 66-89 ms per paint | 20 ms (63 at worst after an edit) | one pass over the captures instead of two; local names kept per buffer change; the declaration a member's base variable comes from kept per function; member resolution limited to 25 ms a paint |
| moving to another file, saving | about 340 ms (tagbar re-running ctags and parsing its output in Vim script, for the status line only) | none | the status line's current function comes from treesitter (`curfunc.lua`); `g:vimide_curfunc = 0` puts tagbar back. Real vim keeps tagbar |
| every edit with the outline closed | 50 ms, 120 at worst (aerial recounting the file's symbols) | none | aerial loads when F10 opens it; `g:vimide_outline_auto = 1` still makes it open by itself, and switching that on mid-session takes effect at the next buffer |
| right after startup | 50 ms (neo-tree merging its whole configuration for the git-status size guard) | none | the guard writes into the pending configuration instead |
| startup to first screen | 0.48-0.89 s | 0.38-0.41 s | the above |

### Found by random QA

A randomized QA pass (six feature areas driven through the real TUI in
isolated sandboxes, every finding reproduced a second time before it was
fixed) turned these up; all are fixed and were checked again on screen:

| what went wrong | now |
|---|---|
| telescope keeps "the selected entry" and "the prompt" in one global slot that a new picker does not clear. Enter pressed right after opening `\fi` ran `git checkout <the file picked in the previous picker>` and threw away uncommitted edits; `\ff`/`\fb` opened the previous pick or the unfiltered top row when a name and Enter arrived together | every picker clears the slot when it opens, and Enter/moves wait for the list (see the telescope line in the key list) |
| typing a filter, a move key and Enter in one burst in the bookmark list registered a duplicate bookmark instead of jumping | moves wait too, so the move lands on the filtered list |
| the bookmark list opened from another telescope picker lost the add row and `d` died with `Invalid buffer id` | it takes its place, symbol and marks from the last edit window |
| a Markdown file with a code fence or a shell script with a heredoc showed a treesitter traceback and Press ENTER on every open (the archived nvim-treesitter's directives predate nvim 0.12's capture lists) | `.vimrc` re-registers the two directives in the new shape; fenced code is highlighted again |
| the same buffer in two windows kept its local/global/index colours only in the focused one | every window showing it is painted |
| F10 moved the edit window's cursor to a symbol (aerial's autojump fires on its own cursor placement) | autojump is off; the edit window follows only when you move to another symbol in the outline |
| the "remove N entries?" prompt had no working yes (`&예` is not a hotkey nvim can match) | `y` / `n` |
| removing the last entries that exist in this checkout left them in `.tags/files` and the index | the project goes to none mode (the preset file stays for other checkouts) |
| `\fo`/F3 in none or unset mode walked the whole tree on every press (3.4 s on 40k files) | it opens an asynchronous find over the project instead |
| each tree `+`/`-` or `^d` re-read the first KB of every file in the preset (0.4-0.85 s with 4000 files) | the binary check is kept per file by size and mtime |
| opening one file in an unset-mode tree of 5000+ files started a full ctags build | nothing is built until a mode is chosen |
| quickfix opened from the F11 float tree took over the edit window and left `cmdheight` at 38 | the float is left first |
| `Ctrl+u`/`Ctrl+w` at the start of the find dialog's second field joined the two fields | the backward-delete keys stop at a field's start |
| F10 within 1.5 s of opening RelationView replaced the edit window's file and could leave two panels | the tree cleanup only waits while the tree slot still shows the buffer it was split from, and the window guard drops records copied by `:split` |
| re-opening the list with the tree/context column up built a second column | the list goes back into the column |
| the panel of the first tab went dead once a panel was opened in a second tab; `Ctrl+n` there moved the edit window | the current tab's windows are picked up again on every tab change |
| `Ctrl+]` on a word the index does not know printed a four-line traceback | one line: `정의를 찾지 못했습니다: <word>` |
| names inside `#if 0` were painted over the grey | dead code stays grey and is not looked up |
| C++ namespaces/classes/templates and C inside `extern "C" {` lost local colours after the speed-up | those scopes are walked too |
| the status line's current function stayed blank after jumping into a large file | a blank computed before the tree exists is not kept |
| after an edit, struct members blinked black while the member budget carried on | members that were green stay green until re-resolved |
| isolated test runs left tag files in `~/.cache/tags` | `g:gutentags_cache_dir` follows `$XDG_CACHE_HOME` when it is set (it is not, normally). If that path holds `/-`, a per-user directory under `$TMPDIR` (or `/tmp`) is used instead, created 0700 and used only while it is yours: gutentags turns the first `/-` of a tag file path into `/`, so it wrote into a directory that does not exist (`ctags job failed` on every open) |
| in a deep tree the one-line notices of `\fx`/`^d` (`제거: ... → <root>/.tags`) and of opening a file (`autoindex: indexing <root> …`) ran past the screen width; Press ENTER came up and ate the next keys, so `y` after the remove prompt and the first two Enters in `\fx` did nothing | a one-line notice that does not fit is shown shortened (the paths that save the most first, then a cut in the middle); `:messages` keeps the full text (`fitmsg.lua`) |
| a tree of 5000+ files opened before its index mode is chosen: gutentags must stay off it, but our own ctags build waits | the file count still runs and keeps gutentags away; the ctags build starts with the first file opened after a mode is chosen |

Smaller ones fixed alongside: `+` on the tree's root row adds the whole project and `-` on anything under it then works; a removal that removes nothing, or an add whose path holds nothing to index, no longer switches the project to none mode; a big context window (`T`) in another tab is no longer taken for the small one; a bookmark saved through a symlink opens from the real path; a dangling symlinked `bookmarks.json` is left alone instead of replaced; long paths in notices are shortened so they do not trip Press ENTER; `\fg` at home follows symlinked dotfiles; a new file in a directory that does not exist yet searches from the nearest existing one; a repository on an orphan branch still counts; a single `+` on the tree's root row adds the root.

### Found by the second random QA

A second pass of the same kind (six areas: window layout, search and
navigation, neo-tree, DirDiff, performance, and a monkey test that sends
random key bursts and bisects what breaks; every finding reproduced a second
time, the fixes checked again on screen after they were merged, then the
merged result swept once more for what the fixes broke between them) turned
up 41 more, and the sweep 14. All are fixed; for `:copen` from the F11 float,
`Ctrl-W s`/`:vsplit`/`:new` typed inside the float still only close it
(nothing is lost).

| what went wrong | now |
|---|---|
| F12 or `:RelationView` pressed in the F11 float tree turned the edit window into the relation list (neo-tree closed the new split along with the float). The file disappeared from the tab, and the next F12 hit E444 | the float is left first, and the panel never takes over a window that already existed |
| F12 with the cursor in the column's tree, after the list and the preview had been closed by hand, showed an E1513 traceback and Press ENTER (neo-tree redrew into the new window after the panel had taken it) | the list is split into the column without autocommands, as the preview and the tree already were |
| closing the zoomed (`\z`) relation list with `:q` left the tree squashed to one row for good | the remaining column windows get their pre-zoom heights back, and the bottom one takes the freed rows |
| a list or preview copied with `Ctrl-W s`/`:split`/`:vsplit` survived F12 off, so the next F12 opened without the tree, at the wrong width, or with the preview outside the column. Turning the tree off in "relation only" set `cmdheight` to 17. `:split file` typed in a side window opened inside it | F12 off closes every copy, including tree copies in the column. A panel window that is picked up again gets the panel options back. A panel left alone in its column keeps its height. `:split`/`:vsplit`/`:new`/`:vnew` with a file name go to the edit area |
| every F12 off (and `t`/`:RelationViewTree` off) left a listed empty `[No Name]` buffer that `:bnext` landed on, because neo-tree's "current" tree hides itself by creating one | the buffer neo-tree creates while the column tree closes is wiped |
| F12 pressed while a telescope picker was open put the focus in the relation list, and the notice started at column 182, wrapped, and raised Press ENTER | the float is left first, and the notice is shown after the layout settles |
| a panel or `\fs` jump made after `Ctrl+t` was appended to the tag stack, so a later `Ctrl+t` revisited an entry already popped | the stack is written the way `:tag` does it: entries above the current one are dropped |
| `Ctrl+g` on text that starts or ends with punctuation (`legacy_init(`, `->hw.`) found nothing, because word mode always added `-w` | word boundaries apply only at the ends that are word characters (`\blegacy_init\(` with rg). grep and the vim fallback drop `-w` in that case |
| `Ctrl+f` in the tree pre-filled a name containing `[ ]` that `find -iname` read as a pattern, so `w[1].c` found nothing, or found `w1.c` | wildcards in the pre-filled name are escaped, so it finds exactly that entry |
| `Ctrl+]` on a blank line or a `{` line showed a three-line E349 and Press ENTER; `Ctrl+] Ctrl+]` there could stop at a `Gtags for pattern:` prompt | one line: `커서 밑에 이름이 없습니다` |
| `:tabnew`/`:tabedit` typed in a side window (quickfix, F9 tree, aerial, the RelationView panel, the F11 float) left the new tab with two windows: the new one and a copy of that side window | while the new tab's only window still shows the buffer it was copied from, it is not recorded as a side window; the new tab has one window, as in plain vim |
| `:copen` or `,o` typed in the F11 float tree still replaced the edit window with quickfix and left `cmdheight` at 38 (the earlier fix covered only the search results) | `:copen`, `:cwindow`, `:lopen`, `:lwindow` and `,o` leave a float first; from a side window they open in place as before |
| F9 with the F11 float open only closed the float, so F9 had to be pressed twice (both keys share one neo-tree per tab, and neo-tree's `toggle` ignores the position); `<leader>t` opened a float once F11 had been used | F9 moves an open tree to the left, and `<leader>t` is now exactly F9 |
| F11 with the F9 sidebar open closed the sidebar and showed no float | the tree moves into the float, and F9 from the float moves it back to the left |
| F10 or `<leader>o` in a telescope picker (or the F11 float) printed an aerial traceback (`Invalid window id`) with Press ENTER and left an empty narrow window | the float is left first, then the outline opens beside the edit window |
| `Ctrl+^` in a window that `:cnext` had split off the quickfix window loaded the quickfix list into it, and `,c` then closed that edit window instead of the list | `Ctrl+^` will not switch to a quickfix list; it says so in one line |
| `Ctrl+g` or `Ctrl+/` pressed in a neo-tree add/move/rename prompt (after `Ctrl+o`) failed with `Window was closed immediately` and Press ENTER, and left the form's buffer in the edit window | the form window is opened first and entered afterwards, so the prompt closes and the form opens; if a form still cannot open, one line says so |
| the grep, lookup and find/replace boxes auto-paired brackets and quotes (delimitMate), so `legacy_init(` was searched as `legacy_init()` and found nothing | the boxes keep exactly what you type; editing buffers still auto-pair |
| In a repo that holds a submodule or another git repo (committed or not), or a tracked symlink to a directory, `indexfiles.sh` printed the right list but exited 1, because `grep -Il` failed on the directory. autoindex threw the list away, so every start said 'big tree' and `:GtagsIndex` said no files were found | the binary check skips directories and judges only by its output, and untracked nested repos (`sub/`) are dropped from the git list. The list exits 0 and the index builds and refreshes |
| Ctrl+] on a parameter, a local variable or a struct member (`p->hw.min`) moved the cursor but left no tag-stack entry, so the next Ctrl+t popped an older jump and skipped this one, and the Ctrl+t after that went forward again through Ctrl+o | these jumps push a tag-stack entry like every other symbol jump. Ctrl+t undoes them in order (Ctrl+] on the declaration itself pushes nothing) |
| Inside a nested project (a sub-repo with its own `.tags`), Ctrl+] asked only the nearest index and said 'not found' for a symbol that only the outer index knows, while `<leader><leader>g`, the F12 panel, Ctrl+] Ctrl+] and the green highlighting all found it | Ctrl+] still asks the nearest index first, then each index above it (up to 4, stopping at $HOME), and lands on the first answer |
| With the relation view off, Ctrl+] (and Ctrl+click) no longer painted the jumped symbol, because Ctrl+] had moved to g]'s function and picked up g]'s 'only while the panel is open' rule. A Ctrl+t after such a jump then cleared the colour of an older jump | Ctrl+] paints the jumped symbol whether or not the panel is open, and Ctrl+t clears it in step with the tag stack. g] and f] keep the panel-only rule |
| Typing in a big C file kept the struct-member colouring busy for the whole time you typed: each pass went over its 25 ms budget, re-armed itself 60 ms later, and every keystroke threw away what it had resolved. Finding the enclosing function walked every top-level node in Lua, about 0.6 ms per member, and was 90% of the cost | the enclosing function is found from the cursor node upwards in C (about 0.001 ms). A pass that runs out of budget in insert mode no longer re-arms itself, and the rest is painted on leaving insert mode. Keystroke latency matches the members-off control |
| `o` in neo-tree (F9, F11, the RelationView tree) usually waited `timeoutlen` before opening, about 1 s: neo-tree's two-key sort maps `oc` `od` `og` `om` `on` `os` `ot` start with `o`, and `<nowait>` only wins when `o` happens to come first in the buffer's map list, an order that changes on every start | the sort maps are dropped, so `o` opens at once (4-10 ms) |
| `=` (index status) in neo-tree always answered after 0.8 s: its buffer map had no `<nowait>`, and vim-unimpaired's global `=p` `=P` `=s` start with `=` | `+` `-` `=` in neo-tree are `<nowait>`, as in netrw, quickfix, bufexplorer and the relation panel |
| the Last Modified / Created column (F11, or F9 widened with `w`) ended every row in `<ec><98>…` under a Korean locale: neo-tree's default `%I:%M %p` gives `오전`/`오후`, and its 20-column cut counts bytes, splitting the character | the date is `%Y-%m-%d %H:%M` (24-hour, no `%p`) |
| renaming or moving an indexed path in neo-tree (`r`, `m`, `x`/`p`) left the preset pointing at the old path: the new name had no mark, `=` said excluded, `.tags/files` and the index kept the old name, and the next rebuild dropped those files without a word | index entries follow the path (the path itself and everything under it). A file taken out of an indexed directory is added at its new place, and a path moved out of the project is removed like `-`. A move inside an indexed directory only rebuilds the list and the index; the preset file is not rewritten |
| deleting a directory in neo-tree (`d`, `T`) left the buffers of files under it: the edit window kept a file that no longer existed, each entry into it printed two neo-tree ENOENT errors and a false "reloaded" notice, and `:w` failed with E212 | unmodified buffers under the deleted directory are wiped, and their windows switch to the alternate file, as neo-tree already does for a single file. Modified ones are kept, with a warning. The external-change notice says the file was deleted when it is gone |
| `\m` did not set a vim-mark mark: the vendored `highlights.vim` used it for its keypad-map toggle (vim-mark skips its default `\m` because F4 already maps `<Plug>MarkSet`). Turning that toggle off unmapped `\f` (`:Gtags -P`) and vim-mark's `\n` and `\*` for the rest of the session, and cleared every match in the window (vim-mark, reference highlight, yellow marks) | `\m` marks the word like F4. The toggle is now `:HighlightMaps`; turning it off restores the maps it replaced, and it only touches its own `hl1`-`hl99` matches |
| F5 (clear marks) also moved the cursor one character right, or to the next line on a one-character line, because a stray space in the mapping ran as `<Space>`; in visual mode it failed with E481 | F5 clears marks and the search highlight without moving the cursor, in normal and visual mode |
| every status-line redraw ran airline's `xkblayout` part, which tries `require'ime'` and `require'fcitx5-ui'` (neither exists) and never shows anything: about 0.25 ms per redraw, the top function under `:profile` while moving with `j` | the extension is off |
| AutoComplPop fired `^N` on the second letter of every word, and `^N` scans the whole buffer (and, through ACP's `complete=.,w,b,k`, every loaded buffer) without reading typed keys: 100-300 ms stalls while typing in a 20k-line file, or in a small file with a big one loaded | the automatic popup stays off in buffers over `g:vimide_acp_max_lines` (5000) lines and only scans the current buffer when all loaded buffers together exceed that. `<Tab>`/`^N` by hand still complete; `0` turns the guard off |
| `Ctrl+x`/`Ctrl+v`/`Ctrl+t` in the preset pickers (`\fm`/F2, `\fM`, `\fS`, `\fx`, `:ProjectFilesAddDir`) split-opened the row label as a file name, leaving a listed empty buffer such as `● none  (아무것도 하지 않는다)` that `:w` would write to disk | those keys do nothing in these pickers and the picker stays open; file pickers such as `\fo` still split |
| `R` pressed while a tree copy ran stopped the copy half-way without a word (a folder left with part of its files, mode 0700). From then on `q` and every tree copy were refused as still copying until `:tabclose`, and a helper that died during a copy locked the tab the same way | `R` waits for the copy, as `q` does. If the helper dies, the lock is released, a message says the copy stopped part-way, and tree copies are refused until `R` |
| `:tabclose` or `:qa` during a tree copy left a half-written `.dirdiff~PID~name` temp file (gigabytes for a big file) in the target tree, and the next comparison showed it as a one-side file | before it exits (on quit, the SIGTERM from `jobstop`, SIGHUP or a closed pipe), the helper deletes the temp file it is writing. `:tabclose` says the copy was stopped, and the files already copied stay |
| making a pair identical in the edit windows and saving it with `:w` left the tree row at `≠`, with the old size and date, until `R` | saving a file inside either compared folder compares that entry again, as a tree copy does |
| with "only differences" on (`f`, `g:vimide_dirdiff_only_diff`), the whole tree was rebuilt every 60 ms while scanning, and the editor was blocked for about 60% of the scan (20,000 files in one folder) | rows that turn `=` are removed (with their open subfolders) and the rest are updated in place. The whole tree is redrawn only when a row has to appear, so blocked time matches the unfiltered view (about 0.4 s of a 2 s scan) |
| `o`/`<CR>` on a name containing a newline opened a non-existent `nl\` in both windows, ran the rest of the name as an Ex command (E492) and showed a stack traceback. Picking two such files with `Tab` in neo-tree did the same | file names are passed to `:edit`, `:tabnew` and `:diffsplit` as arguments and never pasted into an Ex line, so the real files open. Error notes no longer carry a traceback |
| on macOS a name spelled differently only in Unicode normalization (NFC/NFD, e.g. Hangul names from git or Linux) or only in case was shown as two rows, A-only and B-only, that were never compared. Copying the A one overwrote the B file without a word, and the stale B row stayed | when `lstat` shows the two spellings are the same file, the helper pairs them into one row with its contents compared, and a copy asks the usual overwrite question. File systems that really hold both spellings are not affected |
| a count that ran past the last line (`15<C-l>` on line 30 of 40) in the edit windows failed with E16 and copied nothing | the count stops at the last line, as `15dd` does |
| a name that is a folder on one side and a file on the other could not be viewed: `o` did nothing and `<CR>` only opened the folder, though the windows were supposed to show a note | `o` and `<CR>` show the file side next to `(A 쪽은 디렉터리: …)`. `<CR>` still opens or closes the folder side |
| `:tabnew`/`:tabedit` typed in the RelationView list made the new tab's only window a second panel: `:e` hit E1513, the panel buffer came back on the next redraw, and F12 there built a column with no edit window. From the preview window, the new tab's edit window was taken as the preview | a tab's first window is taken as the panel or preview only if it still shows that buffer after the command finishes (as with `:tab split`) |
| with the relation list open, a `Ctrl+g` / `Ctrl+/` / `:LookupReferences` search for text with a bracket (`legacy_init(`, `(sizeof`) gave an `unfinished capture` traceback and Press ENTER, and repeated it on every `j`, `Ctrl+n` and Enter in the list. The preview stayed at the top of the file | the preview looks for the text as typed, with word boundaries only at word-character ends, and lands on the hit |
| `Ctrl+]` on a struct member while the file that declares the struct had unsaved changes gave an E37 traceback and Press ENTER. It also left a tag-stack entry and a painted word for a jump that never happened | a member declared in the same file is reached without reloading the file. A jump that still fails shows one line and leaves neither the tag entry nor the colour |
| `Ctrl+]` (or `Ctrl+] Ctrl+]`) on a local's own declaration painted the word without jumping, so the colour stack got one entry ahead of the tag stack and the next `Ctrl+t` cleared the wrong colour | nothing is painted when the cursor is already on the declaration |
| after F12 from the column's tree (and after `c`/`T` in the list), the NORMAL status line was drawn on the new preview window while the cursor was elsewhere, until the next cursor move | the status line is redrawn for the focused window once the layout is built |
| F10 with RelationView open left a hidden listed `[No Name]` behind every time, because it closed the column's tree too | F10 closes only the left, right and floating trees |
| opening the F9 tree, the outline (F10, `\o`) or RelationView (F12) while the cursor was in the quickfix list left a hidden listed `[No Name]` each time (a split from a quickfix window starts with an empty buffer) | the sidebar is split from the edit window instead; closing one from the quickfix list keeps the cursor there |
| F12 (or `q`) pressed inside the RelationView column put the cursor in the F9 tree when one was open | the cursor goes back to the last edit window |
| `:sp`/`:vs`/`:new`/`:vnew <file>` typed in a tab with no edit window (`:tab help`, `:tab terminal`, a quickfix window moved out with `:tab split`) said 'EDIT 창이 없어 실행하지 않았습니다' and opened nothing | with no edit window in the tab, that window is split, as in plain vim; it is still refused from the F11 float when there is no edit window to leave to |
| a file name with an escaped `\%` or `\#` typed after `:e`/`:sp`/`:vs`/`:new`/`:vnew`/`:view`/`:sview`/`:diffsplit`/`:Ex` in a side window (quickfix, panel, tree) opened a wrong, empty buffer such as `src/psrc/main.cq.c`, because `%`/`#` were expanded twice; `:Ex %:h` there gave E499 | the name is expanded once, in the edit window: `\%`/`\#` open the file you typed, and `%` means the edit window's file |
| on vim 8.1 (the server) the 'all loaded buffers together exceed g:vimide_acp_max_lines' rule never fired, so ACP's popup still scanned a big hidden buffer (getbufinfo() has no 'linecount' before 8.2.0019) | the lines are counted another way there, reading no more than the limit, so the popup scans only the current buffer, as in nvim |
| after `:source ~/.vimrc` and reopening the tree, deleting a directory in neo-tree left buffers of its files again, and the git-status check for nested repos stopped running (neo-tree dropped both subscriptions when it re-read its config) | both handlers are part of the neo-tree config, so they survive a re-source |
| deleting a directory in neo-tree while a modified file inside it was kept could put that kept, now-deleted file into another window (as its `#` buffer), which then said E211 on every entry | windows of wiped files get a file outside the deleted directory, or an empty buffer |
| with the relation view off, `Ctrl+]` on a word the index does not know (`return`, `endif`) showed `mark-1/\<word\>`, `mark-1 cleared` and the not-found line, then Press ENTER (the jump now paints the word even with the panel off) | the paint and its undo are silent: one line, `정의를 찾지 못했습니다: <word>` |

### Searching from the repository

`\ff` (find files), `\fg` (live grep) and `\fi` (git commits) search the git
repository that holds what you are looking at, not the directory nvim started
in:

| pressed in | starts from | no repository |
|---|---|---|
| the edit window | the file | under the file's directory |
| neo-tree (F9, F11, RelationView tree) | the entry under the cursor, as in the table above | under that path |
| anywhere else (RelationView list, quickfix) | the file in the last edit window | under its directory |

From the starting directory it walks up to the first `.git` - a directory, or a
`gitdir:` file (worktrees, submodules) - that has at least one commit, and
searches from the top of that repository. An empty `.git`, a fresh `git init`
with no commits (the dev server has one above several SDKs) and a `gitdir:`
pointing at a directory that is gone do not count; the walk goes on. The walk stops at a
directory holding `.repo` (the top of an Android `repo` checkout: every project
below has its own `.git`, and the top one is empty or covers the whole SDK), at
the home directory and at `/`; stopping means "no repository", so the search
runs under the starting directory instead of across the whole SDK or home. The
stops only end the walk up. Starting *at* the SDK top searches under it, as the
old `\ff` did from the SDK root; starting at home, a directory above it
(`/Users`, `/home`) or `/` (say `~/.zshrc`) searches that one level only
(`--max-depth 1`, dotfiles and links to files included) - under the whole home
`rg` would also read the OneDrive folder in `~/Library/CloudStorage`, which
makes macOS download the files. Paths are resolved first, so `~/.vimrc`
(a link into `~/.vim-ide`) searches the vim-ide repository, and a home that is
itself a link still counts as home; a loop of links is used as it is instead of
failing. An old version opened with fugitive (`:Gedit HEAD~1:a.c`) searches the
repository it came from. The prompt title shows where it searches
and `[git]`, `[저장소 없음: 이 아래]` or `[저장소 없음: 맨 위 한 층만]`.
`\fi` needs a repository and says so when there is none. In neo-tree the keys
are neo-tree window mappings, so they read the line the cursor is on
(`reposearch.lua`, the same rule `Ctrl+g` uses). `:VimIdeRepoSearch
files|grep|commits` is the same from the command line, and
`:Telescope find_files` still searches the cwd.

### What `F` finds, stays found

By default neo-tree throws the result list away the moment you press `<CR>`:
it opens the highlighted file and resets the search. That leaves nothing to
work *with* - clicking another row closed the popup and took the list with
it, and picking several files to index was not possible at all. `F` now
carries `keep_filter_on_submit`, so the matches stay on screen and the tree
behaves like any other tree:

| | |
|---|---|
| `<CR>` / double-click | open that file in the EDIT window |
| `V` over rows, then `+` / `-` | add / remove them all from the index |
| `+` / `-` on one row | that one file (or directory) |
| `<C-x>` | drop the filter, back to the whole tree |

One wrinkle worth knowing about. A result list shows the matching files *and*
the directories they live in, up to the project root - the directories are
scaffolding, not results. A `V` down the whole list used to hand all of them
over, and the top row is the project root, so one keystroke would have pulled
the entire tree into the index. While a search is active, a **range** now
takes only the files; a single `+` on a directory row still means that
directory, because there you did point at it. Measured on a four-file
project filtered to `alpha`: `V`+`+` over all five rows hands over
`inc/alpha.h, src/alpha.c` and nothing else.

### netrw's `/`

netrw never mapped `/` - vim's own search has always worked there. What did
not work was reading the screen while it did: the index marks are drawn by
asking netrw itself for the name on each line, and on the banner's
`"   Sorted by      name` row that call throws *and* makes netrw print
`Press "S" to edit sorting sequence` over the command line. Every `CursorHold`
redrew the marks, so that message sat on top of the search echo, and on top
of this plugin's own `색인 추가: N개`. Banner rows are skipped now, and the
marks are drawn only for the lines actually on screen (plus a screen above
and below) instead of walking a directory of thousands, cursor-moving once
per entry.

`K` and `J` had no neo-tree command behind them, so they are twelve lines of
Lua walking the node's parent for its child ids and focusing the first or
last. Measured in a four-file directory: from `b2.c`, `J` lands on `d4.c` and
`K` on `a1.c`.

NERDTree's `x` (close parent), `p` (go to parent), `C` (change root), `P` (to
root) and `u` (up a directory) are not mapped - neo-tree already uses all
five for something else, four of them for file operations. `C` collapses,
`.` sets the root and `<BS>` goes up.

### Editing the list from netrw

`:Explore`'s listing takes the same three keys - `+` to add the entry under
the cursor or across a visual selection, `-` to remove, `=` to ask - and puts
the red mark on entries that are in.

The line is never parsed. netrw draws four different listing styles (thin,
long, wide, tree) and each puts the name somewhere else, so the name comes
from `netrw#Call('NetrwGetWord')`, which is netrw answering about its own
buffer, and the directory from `b:netrw_curdir`.

### Editing the list from the buffer list

`F6`'s BufExplorer takes the same three keys the trees do:

| | |
|---|---|
| `+` | put the file on this line - or every line of a visual selection - into the index |
| `-` | take it out |
| `=` | say whether it is in, and which preset |

A file that is in the list gets a red `●` at the end of its line, the same
mark and the same judgement the trees use (`projectfiles_tree_flag`), so the
three views never disagree. In auto mode nothing is marked, because
everything is in.

The point is that the file you want to index is usually the one you have
open. Going back to the tree to find it again is doing the same work twice.
The current buffer alone is already `:ProjectFilesAdd %` to add and `\fx` to remove.

The line is read by its buffer number, not by the name BufExplorer prints -
that name is shortened, and two buffers can print the same one.

### Where presets live, and sharing them across machines

A preset is JSON: a name and a list of project-relative paths. Nothing in it
is machine-specific, so the same preset applies to any checkout of the same
tree - entries that are not in this one are simply skipped. They are read
from two places:

| | |
|---|---|
| `stdpath('data')/vim-ide/presets/` | mine. Every save writes here |
| `.vim/presets/` in this repository | shared. Comes with vim-ide, so a `git pull` on another machine (the Linux box) brings it along |

Both are listed together; when a name is in both, my copy wins - so editing a
shared preset (adding a file, dropping one) stays local and never dirties the
checkout. `:ProjectFilesPresetShare [name]` copies a preset into the
repository; commit and push it and the other machines get it:

```
:ProjectFilesPresetShare kernel-audio_d3_under
```

(no trailing `"` comment - a user command takes the rest of the line as its
argument). It writes `~/.vim-ide/.vim/presets/<name>.json` and prints the
commit line to run:

```
cd ~/.vim-ide && git add .vim/presets && git commit -m 'preset' && git push
```

On the other machine, `git pull` in `~/.vim-ide` is enough - `~/.vim` is a
symlink into it (see `install.sh`), so nvim finds the presets with nothing to
copy. Pick one there with `\fm`, where each preset says where it comes from:

| tag | meaning |
|---|---|
| *(none)* | only mine - this machine has it, the repository does not |
| `[vim-ide]` | the repository's, and my copy (if any) is identical to it |
| `[내 사본 ≠ vim-ide N개]` | I have edited it here; the repository still holds the N-entry version, and a `git pull` will not change what this machine uses |

You are also told when a fork starts (the write that creates my copy - often
not a deliberate save, since `C-]` on a symbol outside the preset adds the
file that defines it) and every time a forked preset is put to use, because
that is when a `git pull` stops having any effect on it.

The development server is where presets are kept up to date, so its
copies are the ones that go into the repository - when a preset changes
there, that version is what gets committed. My own copy on another
machine keeps shadowing the shared one until I delete it with `^d`, so
pulling a newer shared preset never silently changes what that machine
indexes.

`^d` in that picker deletes only my copy - which is how the last case goes
back to following the shared one; the shared original is removed by deleting
the file in the repository. To ignore the shared presets entirely:
`let g:projectfiles_shared_presets = ''`, or point it at a directory of your
own.

## Moving windows inside the edit area (nvim only)

vim's own `Ctrl-W H` sends the current window to the far left of the *whole
screen*. With the tree and the outline on the left, the relation panel on the
right and the quickfix list at the bottom, that puts an edit window outside
the tree, full height, or under the quickfix list; `Ctrl-W r`, `R` and `x`
swap edit windows with side windows. Here the side windows stay where they
are and the edit windows move among themselves, however many there are:

| | |
|---|---|
| `Ctrl-W H` / `J` / `K` / `L` | to the far left / bottom / top / right of the edit area |
| `Ctrl-W r` / `R` | rotate the edit windows in that row or column |
| `Ctrl-W x` | swap with the next edit window (the cursor ends where vim puts it) |
| `Ctrl-W T` | move to a new tab; if it is the only edit window, the tab it leaves keeps an edit window in its place (showing the alternate buffer, or an empty one) so that tab's layout survives |

Counts work either way (`2 Ctrl-W x`, `Ctrl-W 2 x`), and so does Visual mode.
Pressed on a side window they do nothing - the side windows are the ones that
stay put. In a tab without side windows, and in floating windows, they are
vim's own (including `Ctrl-W T` saying "Already only one window").

How: the side windows are turned into hidden floating windows for a moment,
which leaves only the edit windows in the layout, so vim's own command sees
the edit area as the whole screen and behaves exactly as it always does. Then
the side windows go back: those before and after the edit windows, and the
ones around them, from the inside out, onto the edge they came from
(`topleft`/`botright` splits) and split back into shape. One that sat between
edit windows - a location list under its window, help above one - goes back
next to the window it was next to, and follows it if that window moved.
Afterwards:

- each side window gets back the size it owns - a column its width, a row its
  height, a pane in a stacked column its height - outer ones first, each one
  locked as it is done (restoring them in window order let a full-width
  quickfix list take lines back from the relation panel column, one pane down
  to 0 lines);
- the edit windows keep their own sizes after `x`, `r` and `R`, and are evened
  out after `H`, `J`, `K` and `L` (with `'equalalways'`), as vim does;
- every window's scroll position and cursor are put back (the side windows
  used to come back scrolled so that the cursor line was at the top);
- if a side window cannot go back (no room on a tiny screen), it goes to the
  bottom edge or stays visible as a small floating window - never hidden.

Checked in a real TUI against vim itself: the same edit windows, laid out
alone in a clean nvim, were given vim's command and the layout and the cursor
compared - H, J, K, L, r, R, x, counts before and after `Ctrl-W`, Visual mode,
with aerial, the relation panel column, the tree and a 100-entry quickfix
list scrolled to the middle around three edit windows; the tree plus four edit
windows and a location list; help and a preview window above one of two edit
windows; a 60x15 screen. The edit windows matched vim every time, and every
side window kept its position, size and scroll position.

```vim
let g:vimide_edit_winmove = 0   " vim's own behaviour
```

## Comparing directories (DirDiff)

```vim
:DirDiff <A> <B>          " compare two directories (tab-completes paths)
```

In neo-tree (F9, F11 or the RelationView tree), press `Tab` on the first
directory - its row gets an `[A]` at the end - and `Tab` on the one to compare
it with: that one becomes `[B]` and the comparison opens straight away. Two
files instead of two directories open side by side in vimdiff. `Tab` again on
the `[A]` row cancels it, and the two can come from different trees (pick `[A]`
in the F9 sidebar, `[B]` in the RelationView tree). `\d` is the same key under
another name.

The same `Tab` works in the DirDiff tree (below), and it is the same `[A]`:
pick `[A]` in neo-tree and `[B]` in a comparison tree, or the other way round.

### The side-by-side tree (nvim)

In nvim, `:DirDiff` opens a new tab laid out like Beyond Compare's folder
compare: one window holds A's tree, a verdict column, and B's tree next to
each other, and each file pair you pick opens in a *compare tab* of its own (A
on the left, B on the right, in diff mode; see *Compare tabs* below).
`let g:vimide_dirdiff_pair_tab = 0` keeps the earlier layout instead: two edit
windows on top of the tree, showing one pair at a time.

```
 A  ~/work/a                                        B  ~/work/b
 이름              크기 수정일                      이름              크기 수정일
 sub                   2026-10-10 오후 11:09:40    sub                   2026-09-20 오전 2:15:49
├─▪ d1.c              2 2026-10-10 오후 11:09:40 ≠ ├─▪ d1.c              2 2026-09-20 오전 2:15:49
├─▪ hunks.c         111 2026-10-10 오후 11:09:40 ≠ ├─▪ hunks.c         118 2026-09-20 오전 2:15:49
├─▪ onlyA.c           2 2026-10-10 오후 11:09:40   │
│                                                  ├─▪ onlyB.c           2 2026-09-20 오전 2:15:49
└─▪ same.c            5 2026-10-10 오후 11:09:40 = └─▪ same.c            5 2026-10-10 오후 11:09:40
```

Each half has three columns: the name (tree guide lines, an open or closed
folder icon - a Nerd Font glyph, `v` / `>` with `g:vimide_ascii_icons` - or a
small square before a file name, `-` in ASCII), the size (right-aligned, with
thousands separators; a folder's size is left empty, as the helper does not
add up what is below it) and the modification time as `2026-10-10 오후
11:09:40` (`g:vimide_dirdiff_date_format`, below). When a half gets too
narrow, the time goes first, then the date, then the size. The guide lines
are drawn per side, as Beyond Compare does: a half only branches to the
entries that exist on that side, and the line runs on through the rows that
are empty there. Above the tree, a one-line window shows A's root over the
left half and B's over the right one (the current side's path is green), and
the column titles `이름 크기 수정일` sit right under it, aligned with the
columns of each half (in that window's status line, or in the tree's window
bar with `'laststatus'` 0 or 3); neither scrolls away, and both follow the
window width. The path line cannot be entered - the cursor goes back to the
tree, and a click on a half switches to that side (with
`g:vimide_dirdiff_pair_tab = 0`, `<C-w>k` from the tree passes it and goes on
to the edit windows above).

The verdict column says `≠` for files that differ and `=` for identical ones,
and stays empty for one-sided entries (orphans) and folders, as in Beyond
Compare; `·` marks a file not checked yet (`x = .` with
`g:vimide_ascii_icons`). The status line shows the progress and the totals.

The colors are Beyond Compare's (`g:vimide_dirdiff_colors = 'bc'`, the
default; with `'background'` dark a matching dark set is used, and 256-color
terminals get the nearest colors):

- An identical file is plain text. A file that differs is red on the side
  whose modification time is later and grey on the earlier side (red on both
  when the times are equal or unknown). An orphan file - one that exists on
  one side only - is blue. A name that is a folder on one side and a file on
  the other is red on the file side.
- A folder - on both sides or on one side only, as in Beyond Compare - has its
  name in plain text and its date in light grey; its icon tells what is below
  it, seen from that side: red if something there differs and is newer on this
  side (or differs with equal times), otherwise grey if something there
  differs and is older on this side, and the plain folder color otherwise
  (nothing differs, or only orphans). This comes from the summary the helper
  keeps per folder (the same one the views use), so it is right for folders
  that were never opened too.
- On the row under the cursor only the half of the side the cursor is on (A or
  B) is light green, as Beyond Compare selects only that side; `<S-Tab>` or a
  click on the other half moves the selection there.
- The totals in the status line (`다름`, `A만`, `B만`) pick the light or the
  dark red and blue by the status line's own background, so they stay readable
  on a light status line in a dark theme (jellybeans).

`let g:vimide_dirdiff_colors = 'neogit'` uses Neogit's status screen colors
instead: a difference is `NeogitChangeModified` (blue, bold italic) on both
sides, only in A is `NeogitChangeDeleted` (red), only in B is
`NeogitChangeNewFile` (green), and in the compare windows A's changed lines
are Neogit's removed-line colors (`NeogitDiffDelete`), B's its added-line
colors (`NeogitDiffAdd`), with the changed characters in its in-line colors;
a group falls back to the earlier color when Neogit is not set up.
`let g:vimide_dirdiff_colors = 'classic'` brings back the earlier colors:
differences red, one-side entries blue, the compare windows in the plain
`DiffAdd` / `DiffChange` / `DiffText` colors. Both keep the earlier verdict
column (`◀` only in A, `▶` only in B, folders too). All DirDiff groups are
named `VimIdeDirDiff…` (`VimIdeDirDiffNewer`, `VimIdeDirDiffOlder`,
`VimIdeDirDiffOrphan`, `VimIdeDirDiffSelect`, `VimIdeDirDiffAddA`,
`VimIdeDirDiffFiller`, `VimIdeDirDiffArrow` ... - `:hi` one of them to change
it; that is kept over a color scheme or `'background'` change). The compare
colors are window-local (`'winhighlight'`) to DirDiff's own two windows only.

| in the tree | |
|---|---|
| `<CR>` | file: open the pair in a compare tab and move the cursor there, on the first change; a pair that already has a compare tab goes to that tab (as it was left - edits and cursor kept). Folder: open / close |
| `o` | open the pair's compare tab in the background and stay in the tree, so several pairs can be opened and then visited with `gt`; on a pair that already has one, read it again (unsaved edits are kept). With `g:vimide_dirdiff_pair_tab = 0`: show the pair in the edit windows, stay in the tree |
| `<C-n>` / `<C-p>` | next / previous file that differs (or exists on one side only), opening folders on the way. In a view other than *all* and *differences*: the next entry that view is about |
| `l` / `h` | open a folder / close it (or go to the parent) |
| `O` / `X` | open every folder that has a difference (in such a view: something the view shows) / close all (the whole tree) |
| `f` | choose the view - a small menu, like Beyond Compare's view filter, with the number of entries in each; see *Views* below |
| `F` | switch between *all* and *differences* |
| `<Tab>` | pick something to compare, as `Tab` in neo-tree: the entry on the current side becomes `[A]` (marked after its name), and `Tab` on a second entry of the same kind - folder and folder or file and file, on either side, in this tree, another comparison tab or neo-tree - makes it `[B]` and opens the comparison in a new tab straight away (two folders: a new DirDiff tab; two files: vimdiff). `Tab` on the `[A]` entry again cancels; an entry of the other kind is refused and `[A]` kept; the empty half of a one-sided row cannot be picked |
| `<S-Tab>` | switch between the A side and the B side (the cursor goes to that side's name; a mouse click on a side, or moving the cursor there, works too). The status line says which |
| `<Space>` | pick / unpick the entry on the current side and move down; `U` unpicks everything |
| `<C-r>` / `<C-l>` | copy files and folders from A to B / from B to A: what was picked in the source tree (the A tree for `<C-r>`, the B tree for `<C-l>`; picks on the other side are left alone), without picks the rows of a visual selection, without that the row under the cursor |
| `R` | compare again (while a tree copy runs it waits for the copy, as `q` does) |
| `q` | finish: closes the tab and its compare tabs, goes back, removes the buffers it opened (an edited one is kept, and named) |
| `?` | these keys |

In the two windows of a compare tab (or the two edit windows above the tree
with `g:vimide_dirdiff_pair_tab = 0`):

| in the edit windows | |
|---|---|
| `\d` | choose the view: *all*, *differences*, *context* - a small menu (`Enter`, a double click or `1` `2` `3` picks, `q` / `Esc` closes, `?` lists these keys); see *View modes* below. The window bar shows the current one |
| `q` | in a compare tab: close it and go back to the tree, onto that pair's row (`:tabclose` does the same). While a macro is being recorded `q` stops it as usual; in the edit windows of `g:vimide_dirdiff_pair_tab = 0` it is the macro key as before |
| `<C-n>` / `<C-p>` | `]c` / `[c` (next / previous change); a count works as on `]c` / `[c` |
| `<C-w>w` / `<C-w><C-w>` / `<C-w>W` | next / previous window, skipping the overview bar and the line details (and the tree's path line) - in a compare tab it goes back and forth between A and B. With a count, as usual |
| `<C-r>` / `<C-l>` | copy the whole change under the cursor to the right (B) / to the left (A): every changed line of that block on both sides, lines that exist on one side only included - what `:diffput` / `:diffget` without a range is meant to do, with the pieces linematch cuts one change into counted as one. On an unchanged line with lines of the other side right above (first) or below it, that change. On any other unchanged line it says so and does nothing |
| `<C-S-r>` / `<C-S-l>` | copy only the line under the cursor - on an unchanged line with lines of the other side right above (first) or below it, that block of other-side lines, as `<C-r>` does there (it can be several lines, or a whole file against an empty one). nvim sees these only when Ctrl+Shift reaches it as its own key - see *Ctrl+Shift in tmux* below; Tera Term usually sends a plain `<C-r>` / `<C-l>` |
| `1<C-r>` / `1<C-l>`, `N<C-r>`, visual | work in every terminal: a count copies that many lines from the cursor (`1<C-r>` is the cursor line, with the same rule on an unchanged line as `<C-S-r>`), a visual selection exactly its lines. Lines of the other side just above the first of those lines are not part of them (as with nvim's `:1,1diffget`); when nothing in the lines differs it says so |

The copy goes into the other buffer and `:w` saves it. Unsaved edits on either side are what is compared and copied, and each copy is one undo step in the buffer it changed. When one side is not a file (the empty side of a one-sided file, a note - a binary or too large file too) the keys refuse and point to the tree copy. Block copies count the rows of both windows (filler lines included) and replace exactly the block's lines, instead of handing nvim a line range: with linematch, a range one line wider than the block also took the next piece and deleted lines on the other side, and nvim's own `:diffput` loses a line when the target is a file with a single empty line (or empties one partway through) and leaves a line behind on `u` after copying into an empty file. On a very large diff (counting takes over 0.25 s), or when `'diffopt'` has `iblank` or lacks `filler` (the rows of the two windows no longer line up), it falls back to `:diffput` / `:diffget` with a range around the block - except into an empty file, which is always filled directly (one `u` empties it again), and into a file holding a single empty line, where the few rows can still be told apart. `do` / `dp` still work. Outside the DirDiff tab `<C-r>` is redo and `<C-l>` moves to the right window, exactly as before, and `<C-S-r>` / `<C-S-l>` do what nvim does without a mapping (`let g:vimide_dirdiff_copy_keys = 0` leaves all four alone everywhere).

**Ctrl+Shift in tmux.** In iTerm2 nothing has to be turned on: when nvim, or the
tmux in between, asks for modifyOtherKeys level 2, iTerm2 sends Ctrl+Shift+R as
`CSI 27;6;82~` (*Profiles > Keys > Apps can change how keys are reported*, on by
default). Inside tmux it is the tmux **server** that has to know extended keys:
3.2 or newer with `set -s extended-keys on` (the repository `.tmux.conf` has it).
tmux 3.0a - the apt package of Ubuntu 20.04 - never asks iTerm2 for it and cannot
tell Ctrl+Shift+R from Ctrl+R, so the key arrives as a plain `<C-r>` and the whole
change is copied. That was measured by standing in for iTerm2 with a pty: 3.0a
copied the whole block, 3.7c with the same `.tmux.conf` copied the cursor line
(`tmux display -p '#{pane_key_mode}'` in that pane reads `Ext 2`). A Mac tmux in
front of the server's tmux does not help while the inner one is 3.0a. `tools/deps.sh`
builds a new tmux into `~/.local`, but the `~/.local/bin/tmux` wrapper keeps
attaching to a 3.0a server that is already running - `tmux display -p '#{version}'`
shows which one you are in - so the new one is used only after that server has been
ended (save the sessions with tmux-resurrect first, restore them in the new server).
Until then `1<C-r>` / `1<C-l>` copy the cursor line; inside such a server the first
whole-block copy of a session says so once, and the `?` help adds a line about it.
`:JumpKeyTest` followed by Ctrl+Shift+R shows `<C-S-R>` when the key gets through.

#### Compare tabs

`<CR>` on a file opens the pair in a tab of its own, right after the DirDiff
tab and the compare tabs it already has, laid out like Beyond Compare's text
compare: A on the left, B on the right, in diff mode. The rows of the pairs
that have a compare tab are highlighted in the tree. The DirDiff tab itself
shows only the tree (with its path line), at full height.

`,r` / `,e` move to the next / previous tab of the comparison - the DirDiff tab
and its compare tabs, in tab order, wrapping around - from the tree and from
the compare windows alike. With several tabs the tab line shows tabs instead of
buffers, so the keys that walk the buffers elsewhere walk these tabs here
(`:bn!` did nothing in the tree, and in a compare window it put another buffer
in place of the compared file). Other tabs (the one you were editing in,
another comparison) are reached with `gt` / `gT`; outside DirDiff `,r` / `,e`
still cycle the buffers.

- **Window bars** (Beyond Compare's path field and the info row under it, in
  one line): `A: <path>  2026-10-10 오후 11:09:40  1,286 바이트  utf-8  unix`,
  and on B's bar the current view and its keys (`[모두 보이기] \d 보기 · q
  닫기`). When the bar is narrow, the encoding goes first, then the size, then
  the time (on B's bar the key hints and then the view name too), so that the
  file name always fits; the path is shortened in the middle
  (`~/…/packagegroups/packagegroup-subcore-tsound.bb`) and only a file name
  wider than the whole bar is cut. The side that has no file says `(없음)`
  before the path. With the `'bc'` colors the current window's bar is green
  and the time, size and encoding are dark grey.
- **Colors** (`'bc'`): a changed line has a light pink background, with the
  characters that differ in red (the identical parts stay as they are); a line
  that exists on one side only is pink with all its text red; where one side
  has no lines (vim's filler lines) there is a grey hatched area
  (`'fillchars'` `diff:╱`, `/` with `g:vimide_ascii_icons`, set on those two
  windows only), and nothing is drawn below the end of the file. Blank lines
  inside a change are lavender - Beyond Compare's *unimportant* lines: a blank
  line with no counterpart, or with a blank counterpart (only whitespace
  differs).
- **Arrows**: the change the cursor is in (or the nearest one) has a yellow
  `⇨` in A's sign column and `⇦` in B's on its first line, with a thin bracket
  down to its last line (`>` `<` `|` with `g:vimide_ascii_icons`). On a side
  that has no lines there (only the hatched area), the arrow is on the line
  just above it; the empty side of a one-sided file gets none, and shows only
  the hatched area (no line number, no cursor line). They follow the cursor.
  The sign column always keeps one column for them, and grows up to your
  `'signcolumn'` width (`auto:2` ...) for other signs.
- **Overview bar** at the far left of the tab (`g:vimide_dirdiff_overview`):
  the whole file squeezed into the window height, A's column and B's column -
  red where they differ, blue for those lavender blank lines, hatched where
  that side has no lines - and a grey third column for the part on screen. A
  file shorter than the window is drawn one row per line, level with the text.
  Clicking a row jumps there (in the window the cursor was in, centered).
  vim-ide's own overview bar (`overview.lua`) is not shown on the two compare
  windows while this one is there.
- **Line details** at the bottom (`g:vimide_dirdiff_line_details`): two lines
  showing the cursor line and the line facing it on the other side (empty when
  that side only has the hatched area), `⇨` for A and `⇦` for B, with spaces
  shown as `·`, tabs as `→` and the line end as `¶` (`.` `>` `$` in ASCII), in
  the compare colors. It follows the cursor, scrolling sideways when the cursor
  is far right, and its status line gives the two line numbers.
- The overview bar and the line details belong to that compare tab only. They
  cannot be entered: the cursor goes back to the compare window it came from
  (to A when the overview bar is reached from the keyboard - `<C-w>h`,
  `<C-w>t`), `<C-w>w` skips them, and `<C-w>p` keeps going back and forth
  between A and B. Files never open in them, they keep their size (3 columns,
  2 lines) when a sidebar comes and goes, and they go away with the tab - `q`,
  `:tabclose`, closing both compare windows - or on their own when the tab
  outlives the comparison (`:tabonly`). A binary or too large pair gets
  neither. All of it is drawn from one
  comparison of the two buffers (`vim.diff` with the `'diffopt'` algorithm,
  ignore options and linematch), done again only when the pair is loaded, the
  text changes (after a short pause), the diff is updated or the window is
  resized; moving the cursor only moves the arrows and the line details. Two
  files of 150,000 lines take about 50 ms; past 400,000 lines in all, the bar,
  the arrows and the lavender lines are left out.
- `<CR>` on a pair that already has a compare tab goes to it; `o` opens one in
  the background (the cursor waits on the first change) or reads an open one
  again.
- `q` in a compare tab, `:tabclose`, or closing its last compare window: back
  to the tree, on that pair's row. The buffers the compare opened are removed,
  an edited one is kept and named. `q` in the tree closes every compare tab of
  that comparison.
- One-sided files, binary and too large files, and a name that is a folder on
  one side work as before (an empty side, a note).
- Everything the edit windows did still works there: `<C-n>` / `<C-p>`, the
  `<C-r>` / `<C-l>` copies with counts and visual selections, `:w` updating
  the tree's verdict (and the bar's time and size), a tree copy reloading an
  open pair (in whichever compare tab shows it, without moving you there),
  nested `Tab` / `Tab` comparisons and several comparisons at once (each has
  its own compare tabs). With `g:vimide_dirdiff_pair_tab = 0` the two edit
  windows get the bars, colors, arrows and lavender lines, but no overview bar
  or line details.
- vim-ide's sidebar guard leaves a compare tab alone (`t:vimide_dirdiff_pair`),
  as it does the DirDiff tab.

#### View modes

`\d` in a compare window chooses how the pair is shown, like Beyond
Compare's text compare views. The window bar shows the current one. Every
pair you open starts in 모두 보이기 (the default view); a view chosen with `\d`
stays with that pair only.

| view | id | shows |
|---|---|---|
| 모두 보이기 | `all` | every line, nothing folded (the default) |
| 차이 보이기 | `diff` | only the changed lines - the unchanged ones are folded, leaving one line next to each change (vim's minimum, `context:0` counts as 1) |
| 문맥 보이기 | `context` | the changed lines with `g:vimide_dirdiff_context` lines (3) above and below |

- The folds are vim's own diff folds (`foldmethod=diff`), so `zR` opens them
  all (*all*) and `zM` closes them (*differences* or *context*); `zo` / `zc`
  work too, and both windows always fold the same way and stay aligned while
  scrolling. The bar keeps showing the view chosen with `\d`.
- The fold context is the global `'diffopt'` `context:` item. It is set when
  you enter a compare tab in *differences* or *context*, and your own
  `'diffopt'` is back as soon as you enter any other tab, so your own vimdiff
  tabs keep folding as before.
- `let g:vimide_dirdiff_file_view = 'diff'` starts in another view (an id from
  the table).
- There is no *same* view (only the identical lines): vim can fold changed
  blocks, but not the filler lines that stand in for the other side's lines,
  and a block that exists on one side only has nothing to fold on the other -
  each folded block would take a different number of rows in the two windows,
  and since diff scrolling binds the windows by line, not by screen row, they
  drift apart further down.

#### Views

`f` opens the views, as in Beyond Compare's view filter; the status line shows
the current one in brackets.

| view | id | shows |
|---|---|---|
| 모두 보이기 | `all` | everything |
| 차이 보이기 | `diff` | what differs or exists on one side only |
| 고아 없음 보이기 | `no-orphans` | everything that exists on both sides |
| 고아 없는 차이 보이기 | `diff-no-orphans` | what exists on both sides and differs |
| 고아 보이기 | `orphans` | what exists on one side only |
| 좌측 최신 보이기 | `left-newer` | different, and newer in A |
| 우측 최신 보이기 | `right-newer` | different, and newer in B |
| 좌측의 최신과 고아 보이기 | `left-newer-orphans` | newer in A, or only in A |
| 우측 최신과 고아 보이기 | `right-newer-orphans` | newer in B, or only in B |
| 좌측 고아 보이기 | `left-orphans` | only in A |
| 우측 고아 보이기 | `right-orphans` | only in B |
| 동일 보이기 | `same` | identical |

- An orphan is an entry that exists on one side only (a left orphan is only in
  A). A folder that exists on one side only is an orphan itself, and so is
  everything in it. *Newer* means the entry exists on both sides, the contents
  differ, and that side's modification time is later; a difference with the
  same time is in neither newer view. A name that is a folder on one side and a
  file on the other is a difference, and its folder side also counts as an
  orphan of that side.
- A folder is shown when anything below it matches, opened or not (the helper
  keeps a summary per folder), so *left newer* shows just the folders that lead
  to files newer in A. A folder that exists on both sides also matches *no
  orphans* by itself, and an identical one matches *same*.
- While the comparison runs, entries not checked yet stay visible if they could
  still match, and drop out as soon as they are known. Those rows are removed
  one by one; the tree is not redrawn as a whole.
- The menu counts the entries of each view (a one-sided folder counts as one,
  as in the status line) and updates while the scan runs. `Enter` (or a double
  click) picks a view; `q` / `Esc` closes the menu, and `F1` closes it and
  opens the key help from the tree (closing the help puts the cursor back in
  the tree). `F` in the tree is the quick switch between *all* and
  *differences*.
- `let g:vimide_dirdiff_filter = 'right-newer'` starts in that view (an id
  from the table). `let g:vimide_dirdiff_only_diff = 1` still starts in
  *differences*.

Copying in the tree:

- It asks first, naming what goes which way
  (`let g:vimide_dirdiff_confirm_copy = 0` to skip the question). A file with
  the same name on the other side is overwritten; a folder is merged into the
  one there - nothing on the other side is deleted.
- The helper does the copying, entry by entry, so that the target side cannot
  be damaged: a file is written to a temporary name next to it and renamed
  over the old one only when it is complete (a failed copy leaves the old file
  as it was); a symlink on the target side is replaced, never written through;
  nothing is written below a target folder that is really a symlink or a
  file; names in `g:DirDiffExcludes` (`.git`, `GTAGS`, `*.o` ...) are neither
  copied nor touched on the other side; special files (FIFOs, devices) are
  skipped. Symlinks are copied as links. One copy runs at a time, and `q`
  waits for it.
- It skips, and says why, an entry that does not exist on the source side, a
  name that is a folder on one side and a file on the other, and a target
  whose buffer has unsaved changes.
- Only what was copied is compared again (from the highest folder that did
  not exist on the target side), not the whole tree, and a pair shown in the
  edit windows is reopened with the new file once its new verdict is in.
  Other comparison tabs that contain the copied paths (a nested `Tab` / `Tab`
  comparison and the tab it was opened from) are updated the same way, as on
  `:w`, and keep their cursor where it was (still in the tree after `gT` or
  `q`); one whose compared folder lies inside a copied folder is compared
  again as with `R`.

- **Only in A / only in B.** The missing side is an empty buffer in diff
  mode, so the whole file shows as added: an A-only file on the left with an
  empty right side, a B-only file on the right with an empty left side - with
  the `'bc'` colors, as in Beyond Compare, every line of the file pink with red
  text (its blank lines lavender) and the empty side only the hatched area. The
  window bar says `(없음)` on the empty side.
- The window bars (`A: …` / `B: …`), the compare colors and diff mode belong
  to the two compare windows only. Opening a file shown there in another
  window or tab (`:tabnew file`, `:e`, `:vsplit file`, `:split` in a compare
  window, `Enter` in neo-tree, a `Tab` / `Tab` vimdiff) gives a plain window:
  nvim copies the options of the window that shows the buffer, and the bar,
  the `'winhighlight'`, `diff`, `scrollbind`, `cursorbind`, the diff folds and
  the view's fold level are taken off again there. Another file opened in a
  compare window (`:e other`) loses the bar and the colors too, and gets them
  back when the pair's file comes back (`<C-^>`). A file the edit windows showed earlier
  and that is still loaded - your own buffer after another pair replaced it,
  an edited one kept after `q` or `:tabclose` - opens the same way, with
  folding as usual and none of the comparison's folds. A `:diffsplit` or
  vimdiff you start yourself still turns diff mode on.
- Binary files and files over 20 MB (`g:vimide_dirdiff_max_mb`) are not
  loaded; the windows say so. So does a name that is a folder on one side and
  a file on the other.
- **Big trees show up at once.** `diff -r --brief` reads every file with the
  same name to the end before it says anything, and holds the editor while it
  does. On two Android 15 `maincore/external` trees (hundreds of thousands of
  files) it had not printed a single line after 120 s. Here a python3 helper
  (`.vim/tools/dirdiffscan.py`) walks both trees in the background and the
  top level is on screen in under 0.1 s; everything fills in as it is found.
  Folders are read with `readdir` alone (no `stat` per entry - one `stat` on
  that server's filesystem takes milliseconds), a different size is marked
  different on the spot, the same size and modification time counts as the
  same (`let g:vimide_dirdiff_trust_mtime = 0` to read those too), and only
  the rest is read. The folder you open is checked first, the rest in screen
  order, with the listing and the reading done by separate workers so neither
  waits for the other.
- The excludes are the same `g:DirDiffExcludes` as below.
- `:DirDiff A B` again for a pair already open goes to its tab; another pair
  opens its own (so does `Tab` / `Tab` on two folders in a tree). Any number of
  comparisons can be open side by side, each tab with its own tree, helper and
  buffers; `q` or `:tabclose` on one leaves the others working.
- `let g:vimide_dirdiff_view = 0` makes `:DirDiff` the plugin's list again;
  `:DirDiffClassic` is always that. `let g:vimide_dirdiff_only_diff = 1`
  starts with only the differences, `let g:vimide_dirdiff_filter = '<id>'`
  with any view from *Views* (it wins over `only_diff`), and
  `g:vimide_dirdiff_list_height` sets the tree height with
  `g:vimide_dirdiff_pair_tab = 0` (default 40% of the screen).
- Options of the compare side: `g:vimide_dirdiff_colors` (`'bc'` /
  `'neogit'` / `'classic'`), `g:vimide_dirdiff_pair_tab` (1: compare tabs, 0:
  edit windows above the tree), `g:vimide_dirdiff_file_view` (`'all'` /
  `'diff'` / `'context'`), `g:vimide_dirdiff_context` (3),
  `g:vimide_dirdiff_overview` (1: the overview bar, 0: none),
  `g:vimide_dirdiff_line_details` (1: the line details, 0: none). A comparison
  keeps the layout it was opened with; the colors change at the next
  `:DirDiff`, color scheme or `'background'` change.
- `g:vimide_dirdiff_date_format` (`'%Y-%m-%d %p %l:%M:%S'`) is the tree's
  modification time: `strftime()` items plus `%p` for 오전 / 오후 and `%l` for
  the 12-hour hour without a leading zero (both done by DirDiff, not by the C
  library - its `%p` follows the locale). The time part, dropped first when a
  half is narrow, runs from the first time item (`%p` `%H` `%I` `%l` `%M` `%S`
  `%T` `%R` `%r` `%X`) to the end. `'%Y-%m-%d %H:%M'` gives a 24-hour time
  without seconds.

### The plugin's list (vim, `:DirDiffClassic`)

[DirDiff.vim](https://github.com/will133/vim-dirdiff) compares two directory
trees: it runs `diff -r --brief`, lists every file that differs or exists on
one side only, and opens the pair under the cursor side by side in diff mode.
This is `:DirDiff` in real vim, and `:DirDiffClassic` in nvim.

| in the list | |
|---|---|
| `<CR>` / `o` | open that pair (`A` on the left, `B` on the right) |
| `s` | sync - make one side match the other. It asks which way (A to B, B to A, the same for the rest, skip). **This copies and deletes**: a file that differs is copied over, one that exists only on the side being copied from is copied, and one that exists only on the side being overwritten is *deleted* (`rm -rf` for a directory). Works on a visual range too |
| `u` | run the comparison again |
| `x` / `i` / `a` | change the excludes / ignored lines / extra `diff` arguments |
| `q` | finish (asks first) |

In the two diff windows the usual keys apply: `]c` / `[c` to the next and
previous change, `do` / `dp` to take or give one, `:DirDiffNext` /
`:DirDiffPrev` to step through the list.

What vim-ide adds around the plugin:

- **A tab of its own, and back again.** The plugin puts its list in the
  current window and splits around it, which in this layout means the edit
  window becomes the list and new windows squeeze in between the tree, the
  outline and the relation panel. `:DirDiff` opens a new tab instead. Finishing
  with `q` - or closing that tab any other way - closes it, returns to the tab
  it was started from, and removes the buffers the comparison opened; one you
  edited is kept and named. `let g:vimide_dirdiff_tab = 0` stays in the current
  window instead (the fixes below still apply).
- **Opening an entry is done here.** Moving to the next entry, the plugin
  `:bd`s the previous files - including a file that was already open before
  the comparison, which closed its window in the original tab. `<CR>`, `o`,
  `:DirDiffNext` and `:DirDiffPrev` close the two diff windows and split new
  ones, and never delete a buffer. An entry that is a directory on one side
  only is not opened (nvim-tree would take the window); the list says so.
- **One comparison at a time.** The plugin keeps its state in one global slot,
  so a second comparison started while the first is open broke both. Starting
  one takes you to the open one instead; finish it with `q` first. If the last
  one ended some other way, its state is cleared before the next starts.
- **Excludes.** `diff -r` holds the editor until it is done, and `.git` alone
  is often bigger than the source it tracks. `.git .svn .hg .repo .tags
  GTAGS GRTAGS GPATH *.o *.ko *.a *.so *.pyc *.swp __pycache__` are left out
  (`g:DirDiffExcludes`; set your own before `.vimrc` reaches it, or change it
  from the list with `x`). A name has to match exactly, so leaving out `.git`
  still compares `.gitignore`.
- **Paths under a `tmp` directory.** The plugin resolves its arguments with
  `expand()`, which returns an empty string for anything `'wildignore'`
  matches, and `.vimrc` has `*/tmp/*` there. Every Yocto tree lives under
  `build/tmp/work/`, so both sides quietly became the current directory. The
  plugin is called with `'wildignore'` cleared, and so is every file opened
  from the list.
- **Characters it cannot pass.** The plugin expands a path a second time and
  builds a `:!diff` command from it, so `` $ % # ! " ` \ `` in a path would compare
  the wrong place or nothing. Such a path is refused with a message.
- **`nvim -c "DirDiff A B"`** works too: the command is taken over as soon as
  the plugin is loaded, before `-c` commands run.
- In real vim (the Vundle side) `:DirDiff` is this list and all of the above
  behave the same; the neo-tree key and the side-by-side tree are nvim only.

## What Source Insight has, and what is here

Compared feature by feature against SI 4.0's own command reference. Covered:
jump to definition and back, the context preview, the relation window's
callers/members/reference tree, the reference highlight, Highlight Word (F4,
58 colours in rotation), lookup references, the project database with
background re-scan, project symbol and file browsing, the symbol window
(F10), syntax decoration of declarations, incremental search, project-wide
grep with clickable results.

Still missing, in the order it costs you:

| | |
|---|---|
| Custom commands with parsed output | `,mk` / `,mb` shell out and throw the output away; routing them through quickfix would make every build error a jump |
| Outlining | `foldmethod=manual`; treesitter folds would give fold-by-function |
| Smart rename / project-wide replace | `,H` is a single-buffer `:%s` |
| Overview strip, clip window, snippets, file compare | lower value in a read-mostly workflow |

### Both directions

A function opens with **both** directions on screen: the **Callers** tree
(who calls this) and, under it, a flat **Calls** list (what this calls) -
SI's Relationship dropdown, except you do not have to know it is there.

`d` cycles which one is the expandable tree: `both` -> `Callers` -> `Calls`
-> `both`, and the header says which you are in (`[d]dir:both`). In `both`
the second list is jump-only; press `d` once and it becomes a full tree.
`<Leader><Leader>d` goes straight to the Calls tree.

```vim
let g:relationview_relation = 'both'   " 'both' (default) / 'callers' / 'callees'
let g:relationview_max_extra = 40      " rows in the flat second list
```

gtags cannot answer the Calls direction, since GRTAGS indexes references by
name rather than by containing function, so it reads the function's body
with treesitter:
find the definition, collect its `call_expression`s in source order, and
resolve each name with the same `global -d` the Definition row uses, so a row
points at the callee's own definition and the tree grows downwards as you
expand. `ops->probe(dev)` is filed under `probe`; a callee whose body is not
readable (a prototype, a macro, a function outside the index) simply stops
being expandable.

```vim
let g:relationview_max_callees = 200      " per function
:RelationViewBoth  [symbol]               " both, the default
:RelationViewCalls [symbol]               " the Calls tree, or \\d on the cursor
```

### The member list is folded away

Selecting a `struct`, `union` or `enum` used to list every member, and a
kernel struct has dozens - the list was the whole panel. It is off by
default now; the definition row is what you get, and the one member (or enum
constant) you actually selected is still shown on its own so you can see
what you picked.

```vim
let g:relationview_members = 1   " list them all again
```

Nothing else changed: `msg->cmd` still resolves through the base variable's
type to the member's own declaration, and an enum constant still opens on
its enum.

## When it feels slow

Most of what made this configuration feel slower on a remote Linux box
than on the laptop was not the box. It was measured, not guessed:

| | |
|---|---|
| Leaked indexers | `autoindex.lua` ran `gtags` through `sh -c`, so nvim killed the shell and the indexer survived as an orphan - one per session. Eleven of them were pinned at 99.9% CPU, 11-17 hours old, on a shared build server: 1099% CPU, and the whole of that machine's load average of 11.4. Killing them took the load from 11.38 to 0.10. Every indexer now runs as a direct argv, holds a lock file so a second nvim does not start a second index of the same tree, carries a timeout, and is killed on `VimLeavePre` |
| Two indexers on one database | `add_for_symbol` fired `global --single-update` for every file it added, all at once, against the same `.tags`. Concurrent incremental updates of one database do not finish: two `gtags` sat on `d5_qnx_hyp/.tags` for 13 hours 18 minutes at 99.9% CPU each - 47,927 seconds of user time, state `R`, `wchan` 0, so not waiting on the kernel but spinning. They also outlived the nvim that started them (reparented to init). One update runs at a time per project now, at most `g:projectfiles_single_update_max` (4) of them, with the `reindex` that follows covering the rest |
| Killing the leader is not enough | `global` runs `gtags` as its child, and `vim.system`'s own `timeout` kills only the leader - the grandchild keeps the pipe open, so the exit callback does not arrive until *it* finishes. Waiting for that callback before killing the group is circular, and it is why the first fix measured 61 s against a 3 s limit. Each update is now its own process-group leader (`detach`) with a watchdog that kills the group at the limit: measured 3.0 s, with the grandchild gone mid-run |
| Binaries in the index | The all-files rule only checked an extension denylist, so anything without a dot walked straight in: `qnx/disk/qnx-ifs` (64 MB IFS image), two `kernel-6.1` EFI binaries (34 MB each), `procnto-smp-instr.sym` (15 MB ELF). 93 of the 1,540 listed files were binary or oversized - 189 MB that ctags and gtags read on every pass and produced **zero** tag lines from. `indexed()` now checks size (2 MB) and content (a NUL byte in the first 1 KB), and `indexfiles.sh` does the same in all four of its list branches. The list went 1,540 -> 1,447; `kernel/common`, which holds only real source, went 407 -> 407 |
| Half the tags file was three headers | `vmlinux_602.h`, `vmlinux_608.h`, `vmlinux_518.h` - 3 MB of generated BTF each - produced **485,469** of the tag lines in a 120 MB tags file. The size cap takes them out; the regenerated file came back at 91 MB from 181 MB |
| A save rewrote the whole tags file | gutentags' "incremental" update is incremental in *ctags* only. `plat/unix/update_tags.sh` does `grep --text -Ev '^[^\t]+\t<the file>\t' tags > tags.temp`, appends, and moves it back - so one `:w` moves twice the size of the tags file. `android/external/bcc` has its own `.git`, 1,145 tracked files, and a **181 MB** tags file, so every save there rewrote 181 MB |
| …and the guard could not catch it | The guard counted *files* against 5,000, and 1,145 never trips that - the cost is bytes, not files. Worse, it decided asynchronously: by the time the count came back and the root went on `gutentags_exclude_project_root`, gutentags had already attached to that buffer, which then kept rewriting for the rest of the session (measured: it still ran `update_tags.sh` on a root that was already excluded). gutentags asks before attaching, though - `g:gutentags_init_user_func` - so the decision is made there now, from one `stat` of the cache file against `g:autoindex_ctags_max_bytes` (32 MB). In that project: gutentags no longer attaches, a save is 11 ms with no stall, and no ctags process appears at all |
| A tags file too big to search | With `ignorecase` and `smartcase`, a tag lookup that has to find *every* match gives up on binary search and reads the file end to end. A 1.8 GB snapshot in `&tags` means one completion reads 1.8 GB. Snapshots over `g:autoindex_tags_max_bytes` (256 MB) stay on disk but out of `&tags`; `C-]` is answered by `tagfunc`/GTAGS first, so jumps are unaffected |
| Indexers at the same priority as the editor | 60 cores, 841 logins, and the background indexers ran at nice 0. Everything through `spawn()` now carries `nice -n 10 ionice -c2 -n7` (`g:autoindex_nice` / `_ionice`), as does the single-update queue, and gutentags' ctags goes through `~/.local/bin/ctags-nice`. Verified by having a fake `gtags` report on itself: `NI=10 IONICE=best-effort: prio 7`. The one thing deliberately left alone is `tagfunc`'s `global -d` - that is a process the user is waiting on, and yielding would make `C-]` worse |
| An incremental index that never ends | `gtags -i` on one project sat at 99.9% CPU with only GPATH/GTAGS open - no input file - state `R`, spinning. Once for 13 hours (before the watchdog existed), once for 13 minutes. The full-build timeout of 30 minutes is right for a build; for an incremental pass over a known list it is not. That path now gets 5 minutes (`g:autoindex_incremental_timeout_min`) |
| Esc | `ttimeoutlen=100` plus the network made every Esc take a measured 131 ms. It is 25 ms now - twice the measured RTT, so a split arrow-key sequence still arrives in time |
| A heap that only grows | An nvim left running for two days sat at 8.9 GB, 8.1 GB of it one `[heap]` region, while the live data was small (Lua heap 398 MB, 30 buffers). glibc returns memory only from the top of the heap, so one surviving allocation above a freed block pins all of it. Every keystroke paid for it: 1.34 ms per cursor move against 0.49 ms in a fresh nvim with the same file (2.7x). Start nvim with `MALLOC_MMAP_THRESHOLD_=1048576` and anything over 1 MB is `mmap`ed and handed back to the OS when freed. It has to be in the environment before nvim starts - nvim 0.12 forks its core (`nvim --embed`) at once, and `.vimrc` runs in the core - so it goes in the shell, scoped to nvim, e.g. in `~/.profile`: `nvim() { MALLOC_MMAP_THRESHOLD_=1048576 /usr/local/bin/nvim "$@"; }` (and point `vi`/`vim` aliases at `nvim`). Restarting is the cure for one already bloated: `+Restore` brings the session back |
| matchparen | Of the 29 autocommands on `CursorMoved`, the bracket-match highlight cost 2.2 ms a move in a large C file - 90% of the total; all the others together were 0.2 ms. It is off (`g:loaded_matchparen`); `%` still jumps to the match. `let g:vimide_matchparen = 1` brings it back |
| The relation window | One `global -f` process per referencing file, up to 100 of them: 125 ms for 60 files as separate spawns, 12 ms batched. The tree cache was written and never read. `fetch_callees` cached nothing. A heavy symbol (1607 references) went 916 ms -> 694 ms cold and 129 ms -> 28 ms on a revisit |
| The pickers | `\fo` re-generated the whole 44,466-file list every press (239 ms -> 116 ms); `\fs` asked gtags for every indexed path before parsing a row, again on every prefix change (95 ms -> 8 ms) |
| Not the cause | gtags queries are *faster* on the server than on the Mac (4 ms vs 19 ms). SSH round-trip is 12 ms and cannot be reduced; compression made it worse. Plugin sourcing is 35 ms total, so lazy-loading buys nothing |

### neo-tree's git marks on a big repo

Finding or filtering in neo-tree makes it rescan, and every scan asked git
for the status of the whole worktree. On a 56,220-file kernel repo that is
one process at 90-120% CPU for six to ten seconds, and a new one for the
next scan. Measured:

| | |
|---|---|
| `git status --porcelain --ignored=traditional --untracked-files=no` | 10.2 s |
| `git status --porcelain --ignored=no --untracked-files=no` | 6.4 s |
| `git status … -- drivers/spi` | **109 ms** |
| `git ls-files --others --ignored` | 56 ms |

So only one command is expensive, no flag combination rescues it, and the
ignored-file pass - the obvious suspect - costs 56 ms. The two cases get
different answers:

- Looking at a subdirectory: `git_status_scope_to_path` asks about that
  path only. 6.4 s becomes 109 ms and the marks still work.
- At the tree root, "that path" *is* the worktree, so there is nothing to
  make cheap. The marks are switched off for a repository whose `git status`
  takes too long, and it says so once.

"Too long" used to be guessed from the size of `.git/index`, and the size
turned out not to predict the time: `kernel/common` (8.4 MB) answers in
0.15 s, so `.vimrc` forced the marks on, and that same force kept them on for
`~/k6.12` on the Mac (8.9 MB), where one `status --ignored=traditional` took
10-16 s. neo-tree's debounce only waits one second before the next call, not
for the previous process to finish, so two of those overlapped and the editor
kept a core or two busy for as long as the tree was open.

Now it is decided by the clock. Every `git status` neo-tree starts, and the
`ls-files --others --ignored` of its first scan (the same directory walk), goes
through a wrapper around its job runner:

- while a status is running for a repository, a new one is not started; the
  latest request waits and runs when the first finishes
- one that runs past `g:vimide_neotree_git_max_sec` (2 s) is killed on the
  spot together with anything else still running for that repository, the
  marks for it are put aside and switched off, and a one-line notice says so.
  Other repositories keep theirs
- `let g:vimide_neotree_git = 1`, or raising the limit, switches it back on and
  puts the marks back (neo-tree skips re-parsing output it has seen, so marks
  that were thrown away would stay blank until a file changed)
- the buffers and git_status views call a blocking `git.status()`
  (`vim.fn.system` - the editor waits for it). It is skipped for a repository
  that is switched off, and one that takes longer than the limit switches the
  repository off

```vim
let g:vimide_neotree_git = 1          " always on, however slow (no timing)
let g:vimide_neotree_git = 0          " always off
let g:vimide_neotree_git_max_sec = 2  " slower than this: off for that repo
let g:vimide_neotree_git_max_mb = 2   " (only if set) also off above this size
```

Checked with a stand-in `git` that delays `status` (real TUI, isolated): a 6 s
repository was killed at about 2 s and never asked again; a 1.5 s one was asked
four times in a burst of six refreshes, one at a time, and kept its marks; a
fast one kept its marks; with the option set to 1 the 6 s one ran to the end.

Counted live on the kernel repo while opening neo-tree, walking into a
subdirectory and revealing a file, with the old size guard: forced on, one git
process at 89%, then 97% eight seconds in, then a second at 121%. With the
guard, none at any step.

### The first telescope window used to open tiny

`set all&` at the top of `.vimrc` resets every option to its default -
including `'columns'` and `'lines'`, whose defaults are 80 and 24. A
terminal reports its size once at startup and then only when it changes,
so nothing put the real size back: nvim sat at 80x24 inside a much larger
window. `<C-z>` and `fg` produced a SIGWINCH, which is why the second
attempt always looked right.

telescope multiplies `layout_config`'s fractions by `columns`/`lines`, so
0.8 of 80 is a 64-column box - and below `preview_cutoff = 120` it drops
the preview pane entirely, which is what made it look broken rather than
merely small. Measured in a 160x40 terminal, first picker: `64x13` with no
preview before, `75` of results plus `53` of preview at `29` rows after.

The size is now taken back after the reset, from the attached UI when
there is one (that is the authoritative value) and from the saved value
otherwise, so `--embed` still gets its size when the UI attaches.

`:VimIdeColorCheck` for colour problems. For indexing, `:GtagsIndexStatus`
says what is running and which database is in use, and
`let g:autoindex_debug = 1` writes a line per index action to
`stdpath('cache')/autoindex.log`.

Two switches are left off because they change what you see, not just how
fast it arrives:

```vim
let g:vimide_light_cursorline = 1   " highlight the line number, not the line
                                    "   (1051 bytes a keypress, not 152)
let g:vimide_scrolljump = 5         " scroll five lines at a time
                                    "   (a scrolling keypress repaints 11.1 KB)
```

## Overview bar (nvim only)

Dragging it used to stutter, and a fast drag threw:

```
E5108: Lua: overview.lua:417: E565: Not allowed to change text or change window
```

Three things, all in the mouse path:

The mappings are `expr` mappings - they have to be, because a click on a
focusable float never reaches a buffer-local map, so the bar catches the
mouse globally and returns the key unchanged when the click was not on it.
Inside an `expr` mapping you are under textlock: `nvim_set_current_win` is
refused, which is the E565. Restoring focus to the edit window on
`<LeftRelease>` did exactly that. It is deferred now.

A drag emits events faster than they can be drawn, and each one was queued
with its own `vim.schedule`. The callbacks piled up, so the view crawled
through every intermediate position instead of following the mouse. Only
the newest row is kept now, and one tick processes one move - 22 drag
events in a fast sweep of a 3,000-line file land on line 2,922 with nothing
queued behind them.

And the first drag after a click jumped half a screen, because a click
centred the line (`zz`) while a drag put it at the top (`zt`). Both centre
now.

That got rid of the error and the pile-up, but it still did not feel like a
scrollbar, because every drag event was an *absolute* jump: "put the line
this row stands for in the middle of the window". Grab the viewport marker
and it teleports out from under the cursor, and since one bar row covers
`ceil(total/height)` lines - 64 lines of a 3,000-line file in a 47-row
window, more than a screenful - each row you move skips past content you
never see.

Dragging is relative now, the way a scrollbar is. Pressing inside the
viewport marker records where in the marker you grabbed it and moves
nothing; from then on the marker's top tracks the mouse, so the point you
grabbed stays under the cursor and the view moves exactly one row's worth
per row of mouse travel. Pressing outside the marker still jumps there
first. Measured on 3,000 lines with a 47-row bar (64 lines a row): pressing
inside left the top line at 1, dragging down 20 rows put it at 1,281
(1 + 20x64) and back up 15 rows at 321 - exact, both directions.

Cheaper per frame, too, which matters when the events arrive faster than
the redraw: the blank bar lines are only rewritten when the height changes,
the float is only reconfigured when the geometry changes, `sign_getplaced`
(which fetches every sign in the buffer) is cached until something that can
change signs happens, the debounce drops to `g:overview_drag_debounce`
(10 ms) while dragging, and a scroll the bar itself caused no longer
schedules a second redraw on top of the one it already asked for.

One latent bug turned up while testing the wheel over the bar: the scroll
was written `3\22y` / `3\22e`, and `\22` is Ctrl-V, not Ctrl-Y. So the
wheel ran `normal! 3<C-v>y` - it never scrolled, it selected a block and
yanked it over your register.

Fixing the control codes then produced a third error, because the wheel
branch was the one path still doing its work inline in the `expr` mapping:

```
E5108: overview.lua:579: Vim(normal):E523: Not allowed here
```

`:normal` is not allowed under textlock either. The wheel does not run
`:normal` at all now - it moves `topline` through `winrestview`, deferred
like everything else in that mapping. `g:overview_wheel_lines` (3) sets how
far one notch goes.

Even exact, relative dragging still stepped, and for a reason no amount of
tuning removes: one bar row is `ceil(total/height)` lines - 64 lines of a
3,000-line file in a 47-row window, more than a screen. A terminal reports
the mouse by cell, so the bar cannot be aimed any finer than that. What it
can do is not arrive all at once. Each move now glides to its target, half
the remaining distance every 16 ms, so one row of mouse travel reads as

```
1 -> 33 -> 49 -> 57 -> 61 -> 63 -> 64 -> 65
```

instead of a single jump, and a 20-row drag still lands exactly on 1,281.
`g:overview_smooth = 0` goes back to arriving instantly;
`g:overview_smooth_step` (0.5) is how much of the remaining distance one
frame covers.

The bar could also vanish after a few drags, and that one was mine: the
render caches I added skip rewriting the bar's blank lines unless the height
changed, but they were not cleared when the buffer itself was recreated, so
the float stayed empty - and a two-column float with no content is
invisible. The caches reset with the buffer now, and a render during a drag
never closes the bar just because the target window was momentarily not
found.



A thin bar down the right edge of the edit window standing for the whole
file, the way Source Insight and VS Code have one. The part you are
looking at is lit, the cursor's line is brighter still, and changed lines
and diagnostics show as coloured ticks. Click or drag it and the edit
window goes there.

```
<Leader>b        toggle
:OverviewToggle  the same
click / drag     go to that point in the file
wheel            scroll the edit window
```

`.vim/plugin/overview.lua`. Two cells wide by default
(`g:overview_width`), hidden for files under `g:overview_min` (40) lines
and for windows too narrow to spare the room (and for a window with
`w:overview_off` set - DirDiff's compare windows, which have their own),
and off entirely with `let g:overview = 0`. Colours are taken from whatever colourscheme is
loaded - `CursorLine` for the bar, `Visual` for the viewport, `Cursor`
for the cursor, `Diff*` and `Diagnostic*` for the ticks - so it suits
`si`, `light` and `dark` without three sets of hex codes. Override
`OverviewBg`, `OverviewView`, `OverviewCursor`, `OverviewAdd`,
`OverviewChange`, `OverviewDelete`, `OverviewError`, `OverviewWarn` to
taste. The ticks come from whatever placed a sign, so signify, gitsigns
and LSP diagnostics all show up without knowing about any of them.

Two things about the mouse were not obvious, and cost most of the work:

- A click on a floating window does not move focus into it, and a mouse
  mapping is looked up in the buffer that was current *before* the click.
  So buffer-local `<LeftMouse>` on the bar never fires - the mapping was
  demonstrably attached and the handler was demonstrably never called.
  The maps are global, and fall through by returning `<LeftMouse>` when
  the click was not on the bar (`noremap`, so that runs the built-in
  behaviour rather than recursing). Clicking in the text still just moves
  the cursor, and buffer-local maps elsewhere - the relation window's
  double-click - still win over a global one.
- Restoring focus to the edit window on the click broke dragging, because
  the drag events then went to the edit window. Focus stays put until
  `<LeftRelease>`.

Verified by injecting mouse events at the bar's real screen position in a
pty: on an 800-line file with a 20-row bar, clicking at 75% goes to line
601, at 25% to 201, at 95% to 761, and a drag from 90% to 10% tracks down
to line 81. Clicking in the text at screen row 9 still goes to line 9 and
leaves you in normal mode.

### Two neo-tree things that were not obvious

**`H` looked broken.** It runs `toggle_hidden`, which flips one flag:
`filtered_items.visible` - "show the filtered items, just differently".
With `hide_dotfiles = false` nothing was ever filtered, so the flag flipped
and the screen did not change. Filtering is on now (`hide_dotfiles = true`)
with `visible = true`, so dotfiles still show by default, dimmed, and `H`
takes them away and brings them back - with a `(2 hidden items)` line where
they were. `hide_gitignored` stays off: turning that on in a tree full of
build output changes the view far more than the key is worth.

**Opening a file could fail** with

```
E1513: Cannot switch buffer. 'winfixbuf' is enabled
```

neo-tree picks a window to open into by looking at the last-used windows and
skipping the types in `open_files_do_not_replace_types`. The relation
window's context pane got picked: its `buftype` is `nofile`, but its
`filetype` is that of the file being previewed (`c`, `h`, ...), so it reads
as an ordinary edit window - and it has `winfixbuf` set, so the open failed.
neo-tree does have a winfixbuf recovery path, but an `assert(pcall(...))`
throws before it is reached. The list matches `buftype` as well as
`filetype`, so `nofile` in it keeps every scratch window out - which is the
right rule anyway.

### Bold means "a function is called here"

Every green thing used to be bold - type names, `struct` tags, `typedef`s,
storage classes, qualifiers and calls alike - so on screen a `struct packet`
and a `helper()` call carried the same weight and the call stopped standing
out. Bold now belongs to calls alone; the rest of the green family is plain.

| | |
|---|---|
| `@function`, `@function.call`, `@function.builtin` | green **bold** |
| `@type`, `@type.builtin`, `@type.definition`, `@si.type.ref`, `Type`, `Typedef` | green, no bold |
| `@keyword`, `@type.qualifier`, `@storageclass` | navy bold, unchanged - a different colour, so no confusion |

`s:tp` is the new empty attribute those green entries use, next to `s:kw`,
which the navy reserved words keep. Measured on real code: `helper(3)` and
`printf(...)` resolve to `@function.call` green bold, while `struct packet`,
`u32` and `int` come out `@si.type.ref` / `@type.builtin` green and plain.

### Getting back out

Three things were broken here at once, and they hid each other.

**`Ctrl+]` skipped the context window whenever the panel was closed.**
`ctx_jump_from_edit()` asked `panel_visible()` and gave up if the panel was
not there. That was true when it was written; then `F3` grew a *context
only* mode and that became the startup default, so in the most common layout
the whole handler bailed on its first line - `Ctrl+]` moved the edit window
and opened a quickfix list instead of showing the definition in the preview.
It now asks whether *either* of our windows is up.

**`Ctrl+t` never used the tag stack.** It was mapped `nmap <C-t> <C-o><CR>`,
which walks the jumplist instead and then presses Enter, so it came back one
line below where it left. And the reason it faked it is that the tag stack
really was empty: these jumps go through `nvim_win_set_buf`, not `:tag`, so
vim records nothing. Both halves are fixed - the jumps push a proper entry
with `settagstack()`, and `Ctrl+t` pops it, falling back to `Ctrl+o` when
the stack is empty. `Ctrl+o` / `Ctrl+i` keep doing what they always did.

**The context window could go back but not forward.** `Ctrl+t` popped the
preview's own stack and threw the entry away, so one key too many meant
digging down from the top again. What it pops is now kept for `Ctrl+i`, and
any new `Ctrl+]` clears it - the same rule the jumplist uses.

Measured in a small C project, context-only mode, after `Ctrl+]` on a call:

| | |
|---|---|
| edit window `Ctrl+]` | definition in the preview, focus there, edit window unmoved, no quickfix |
| preview `Ctrl+]` → `Ctrl+t` → `Ctrl+i` | definition → back → definition again |
| panel jump → `Ctrl+t` | back to the exact line it left, tag stack 1 → 0 |

### The mouse back/forward buttons

They are mapped (`<X1Mouse>` / `<X2Mouse>`, in the edit window, the panel and
the preview) and in most terminals they still do nothing, because **the
terminal never sends them**. xterm's mouse report covers buttons 1-5, where
4 and 5 are the wheel; the side buttons are outside it. iTerm2 and Tera Term
both stop there, so nvim has nothing to turn into `<X1Mouse>`.

Check before configuring anything - if this prints nothing when you click
the side buttons, the terminal is the problem, not the mapping:

```bash
nvim -u NONE -c 'set mouse=a' -c 'nnoremap <X1Mouse> :echo "back OK"<CR>' -c 'nnoremap <X2Mouse> :echo "forward OK"<CR>'
```

The way through is to make the button send a *key* instead. Back and forward
are therefore also on `Ctrl+o` / `Ctrl+i` everywhere (the panel and preview
learned those here; the edit window always had them) and on a configurable
alias pair: `<F17>`/`<F18>`, `<S-F5>`/`<S-F6>`, `<A-Left>`/`<A-Right>`,
`<M-b>`/`<M-f>` and `<C-RightMouse>`/`<S-RightMouse>` by default. The two function-key names are
both bound because the same bytes - `ESC [15;2~` and `ESC [17;2~` - are read
as a high function key by some builds and as a shifted one by others; only
one ever arrives.

**Windows Terminal, PuTTY and MobaXterm are in the same boat as Tera Term** -
none of the three reads the side buttons at all, and none has a setting to
bind them, so no terminal-side configuration exists to find. Send
`Alt+Left` / `Alt+Right` instead: it is what a browser's back and forward are
bound to, so a mouse vendor's utility usually has that mapping ready, all
four terminals pass the keys straight through, and vim-ide binds them out of
the box. With no vendor utility, [`tools/vim-ide-mouse.ahk`](tools/vim-ide-mouse.ahk)
is ready to run - install AutoHotkey v2, double-click the file, done. It is
three lines:

```ahk
#Requires AutoHotkey v2.0
XButton1::Send("!{Left}")
XButton2::Send("!{Right}")
```

It deliberately does not restrict itself to terminal windows. Scoping it with
`#HotIf WinActive("ahk_exe ...")` looks tidier and then quietly fails to
match, because the executable names vary - MobaXterm ships as
`MobaXterm_Personal_24.2.exe`. Alt+Left and Alt+Right are back and forward in
a browser and in Explorer too, so leaving it global costs nothing.
([`vim-ide-mouse-v1.ahk`](tools/vim-ide-mouse-v1.ahk) is the same thing for
AutoHotkey v1, whose syntax v2 will not run.)

Windows Terminal has also been measured delivering the side buttons as
**`Alt+b` / `Alt+f`** - `:JumpKeyTest` read them as `<M-b>` and `<M-f>`, raw
`<80><fc>^Hb` and `<80><fc>^Hf`. That is readline's back-a-word /
forward-a-word pair, which a mouse utility or the terminal itself may be
sending on its own, so the buttons can turn out to work there with nothing
installed. Both are in the default alias list, so it costs nothing either
way. They are normal-mode maps only; `Alt+b`/`Alt+f` in insert mode are
untouched.

Then run `:JumpKeyTest` and press the button once: `<A-Left>` or `<M-b>` on
screen means it is done. Nothing at all means the button still has not been turned into a
key on the Windows side, which is not something vim can fix. If Alt is being
eaten by a window menu, use the escape-sequence or `Ctrl+O`/`Ctrl+I` route
below instead.

**iTerm2** - Settings → Pointer → *Mouse Button and Trackpad Gesture
Actions* → `+`, click the side button to record it, Action = **Send Escape
Sequence**, Text = `[15;2~` for back and `[17;2~` for forward (iTerm2 sends
the ESC itself).

**Tera Term never sees those buttons at all.** Its mouse reporting in
`vtwin.cpp` handles `IdLeftButton`, `IdMiddleButton`, `IdRightButton` and the
wheel, and there is no `WM_XBUTTONDOWN` case anywhere - so no setting will
make it forward them.

What it *does* send is modifiers: `MouseReport()` in `vtterm.c` ORs
`Shift=4`, `Alt=8`, `Ctrl=16` into the button byte. So **`Ctrl` +
right-click goes back and `Shift` + right-click goes forward**, in the edit
window, the panel and the preview, with nothing installed on the Windows
side. `Ctrl`+right-click is also where vim puts `<C-t>` by default, so the
meaning matches. (If Tera Term's *Disable mouse tracking by Ctrl* option is
on, Ctrl+click is swallowed before it is reported - use the Shift one, or
turn that option off.)

For the physical side buttons it has to come from outside Tera Term.
AutoHotkey, scoped so the buttons keep working in other apps:

```ahk
; AutoHotkey v2 (the current default download)
#HotIf WinActive("ahk_exe ttermpro.exe")
XButton1::SendInput("{Esc}[15;2~")
XButton2::SendInput("{Esc}[17;2~")
#HotIf
```

```ahk
; AutoHotkey v1 - v2 will not run this, and v1 will not run the above
#IfWinActive ahk_exe ttermpro.exe
XButton1::SendInput {Esc}[15;2~
XButton2::SendInput {Esc}[17;2~
#IfWinActive
```

Simpler and with one fewer thing to get wrong - send a plain key instead,
since back and forward answer to `Ctrl+O` / `Ctrl+I` in all three windows:

```ahk
#HotIf WinActive("ahk_exe ttermpro.exe")     ; v2
XButton1::SendInput("^o")
XButton2::SendInput("^i")
#HotIf
```

The mouse vendor's own utility can do the same binding with no AutoHotkey at
all. The one cost is that `Ctrl+I` is `Tab`, so the forward button inserts a
tab if you press it in insert mode, and in a neo-tree window (F9, the
RelationView tree) it picks the row for a comparison (`[A]`, then `[B]` - see
[Comparing directories](#comparing-directories-dirdiff)); the escape-sequence
route has no such overlap. If Tera Term runs elevated and AutoHotkey does not, Windows blocks
the synthetic input - run both the same way.

**`:JumpKeyTest`** says where the chain breaks. Run it, press the button
once, and it prints the key nvim received and the raw bytes. Nothing at all
means the button never reached nvim, which is a terminal/AutoHotkey problem,
not a mapping one. Measured through a pty against this config:

| sent | `TERM=xterm` | `TERM=vt100` |
|---|---|---|
| `ESC [15;2~` | `<F17>` | `<S-F5>` |
| `ESC [17;2~` | `<F18>` | `<S-F6>` |
| `Ctrl+O` | `<C-O>` | `<C-O>` |

which is why both names in each row are bound by default.

| | |
|---|---|
| `g:vimide_jump_back_key` | list of key names for back. Default `['<F17>', '<S-F5>', '<C-RightMouse>']`, `[]` disables |
| `g:vimide_jump_forward_key` | same for forward. Default `['<F18>', '<S-F6>', '<S-RightMouse>']` |

### Parameters and locals are blue

Source Insight marks a declaration with an underline and leaves the colour
alone, which this config followed. Told apart from a use that way, a
declaration is easy to miss in a long function, so parameters and the
variables a function declares in its own body are now navy as well - the
same blue the reserved words use.

`@si.declaration` already covered those identifiers, but it covers struct
members and file-scope declarations too, and those should stay as they were.
So the query pulls out the narrower cases by their position in the tree:
`@si.declaration.parameter` for anything under a `parameter_declaration`,
and a new `@si.declaration.local` for a `declaration` inside a
`compound_statement` (plus the `for (int i = 0; ...)` initializer, which
hangs off the `for_statement` instead).

The awkward part is the declarator wrappers. `int x` is an identifier, but
`int *p = NULL` is `init_declarator > pointer_declarator > identifier` and
`int (*cb)(void)` is `function_declarator > parenthesized_declarator >
pointer_declarator > identifier` - and that middle one is an *unnamed* child,
so a `declarator:` wildcard chain walks right past it. Both the parameter and
the local forms are therefore spelled out for the nesting depths that occur.
Verified against a file holding each shape:

| | |
|---|---|
| `p_ptr`, `p_plain`, `p_argv`, `p_cb`, `p_name` | `@si.declaration.parameter` - navy bold, underlined |
| `local_plain`, `local_init`, `local_ptr`, `local_buf`, `loop_i` | `@si.declaration.local` - navy bold, no underline |
| struct members, file-scope variables | unchanged |

The underline is what separates the two, since both are navy bold: a
parameter is a value that came from outside, a local is one made here, and
that is worth seeing without reading. It also lines up with the factory
palette, where the underline belongs to parameters and labels only.

Struct members and file-scope (global) variables are navy bold too, with the
underline kept - a header is read to find out *what is declared here*, and
in body colour the name sat at the same weight as its type.

That one needed the same rule written twice. `.h` opens as **cpp**, and
nvim-treesitter's cpp query begins `; inherits: c`, so the order is: c
defaults → our `after/queries/c` → cpp defaults → our `after/queries/cpp`.
Anything the cpp defaults also capture therefore beats our c rule. The
symptom was a struct where `char *p` was navy bold and `int m` beside it
stayed black, because the plain member is the only one cpp's
`@variable.member` claims - and our `(field_declaration declarator:
(field_identifier))` never fired anyway, since in this grammar a
`field_identifier` directly under `field_declaration` carries no
`declarator:` field name. Both halves are fixed: the rule is written without
a field name, and repeated in the cpp query.

(`let g:c_syntax_for_h = 1` makes `.h` open as C instead, if you would rather
not have C++ rules near your C headers at all.)

**The underline is down to one job: function parameters.** Everything a
declaration used to be marked with is now carried by navy bold, and the one
place bold cannot help is a parameter sitting next to the locals below it -
same colour, same weight, and only their position in the function tells them
apart. Every other declaration is already distinguished by where it is, so a
rule under each one read as noise rather than emphasis.

| | underline |
|---|---|
| **parameters** | **yes** |
| struct members, file-scope variables | no |
| function / struct / enum / typedef names being defined | no |
| variables a function declares in its body | no |
| goto labels | no - red bold already separates them |

The definition names lost theirs through the default
`g:sourceinsight_declaration_emphasis = 'bold'`, which now means navy bold
and nothing else; `'strong'` still carries the underline, with the grey
background. The `'factory'` palette is untouched - it reproduces Source
Insight's shipped stylesheet, where the underline belongs to parameters and
labels.

`g:sourceinsight_decl_local` is not read yet; edit `s:c.decllocal` in the
colorscheme for a brighter blue.

### A local you can jump to is olive

A reference to a variable the function declared itself - or to one of its
parameters - is drawn in teal (`#008080`) when the declaration is actually
there to jump to. Anything else keeps the body colour.

The colour was not chosen so much as found: `#008080` is one of the seven
inks in Source Insight's shipped palette, and this colorscheme was already
using it as `reflocal`, its name for a *local symbol reference*. The first
attempt used a dark yellow-green; SI had answered the question years ago.
It sits clear of the green that means "a symbol you can look up" and the
navy that means "declared here".

The mechanism is treesitter and nothing else. **gtags does not index locals**
- GTAGS holds global symbols, and a parameter or a block-scoped variable is
never in it - so asking the index this question would be both slow and
wrong. `sihllocal.lua` instead collects the declared names of every function
overlapping the view and paints the uses that match. No subprocess is ever
spawned, which matters on a shared box: this repo has lost a core for
thirteen hours to an orphaned index process, and the cheapest way not to
repeat that is to have nothing to orphan.

Two properties are deliberate. Only the *found* case is painted, so a symbol
whose declaration is absent renders exactly as it does today rather than
flashing black - "not found is black" costs nothing because black is already
what it was. And the scope is the function, not the block: C shadows inside
a block rarely, resolving per block would mean walking scopes for every
name, and the case it gets wrong - the same name declared in two blocks of
one function - is still a name you can jump to.

| | |
|---|---|
| `g:sihl_local = 0` | off (`:SiHlLocalToggle` at runtime) |
| `g:sihl_local_delay` | ms of stillness before painting, default 120 |
| `g:sihl_local_pad` | lines resolved above and below the screen, default 40 |
| `g:sihl_local_max` | most lines examined in one pass, default 4000 |
| `g:sihl_local_global` | 0 turns off the purple globals below |
| `g:sourceinsight_global_color` | a different purple, e.g. `'#6a1b9a'` |

What stays the same while the text does is kept per buffer change
(`changedtick`): the file-scope globals and each function's declared names.
Scrolling therefore costs only the lines on screen. The globals are found by
walking the top-level nodes (declarations at file scope and inside the
top-level `#ifdef` chain) instead of running a query over the whole file, and
the names on screen are visited top-down, function by function, instead of
climbing to the enclosing function from every name - treesitter's `parent()`
searches down from the root each time, which in a file of 600 functions cost
0.13 ms per name. Measured on the dev server, 6,600-line C file: a paint went
from 55 ms on average (80 at worst) while scrolling and 164 ms (325) after an
edit, to 9.6 ms (22). A declaration inside an `#ifdef` in a function body is
no longer taken for a global.

**A global used inside a function is purple**, and italic where the terminal
can draw it.

**The italic is off by default, and that took two passes to get right.** A
terminal with no italic face draws it as reverse video, so the colour meant
to be read as letters arrived as a purple block. Stripping it from `cterm`
was not enough: the same nvim on the server is reached from iTerm2 and from
Tera Term, and if that session has `termguicolors` on it is the `gui`
attribute that applies - so Tera Term went back to a block while iTerm2 was
fine. The terminal changes per connection and nvim does not, so neither side
can be the default.

`let g:sourceinsight_italic = 1` turns it on where it renders - iTerm2, a
GUI - and `g:sourceinsight_cterm_italic` still controls the terminal
attribute alone. For the exact `#800080` rather than its 256-colour
approximation, `let g:vimide_truecolor = 1`.

**A macro the index confirms is red, wherever it appears.** Treesitter cannot
tell `ADD(x, 2)` from a function call - the syntax is identical - so
function-like macros came out green and bold like any other call, while
`MAXLEN` beside them was red. The index can tell: `--result=ctags-x` returns
the defining source line, and a macro's begins `#define`. Measured on a file
holding every shape: `MAXLEN`, `VERSION_STR`, `ADD`, `LOG` and a bodyless
`EMPTY_MACRO` all red, and only the two names the index does not know left
black.

Reading a function,
the thing worth noticing is which names reach outside it - a local you can
follow with your eye, a global you cannot. Purple `#800080` is another of
Source Insight's inks, shared with comments, which are never identifiers and
are purple by the line rather than by the word; the italic separates them
anyway and says "this is state from outside".

It applies **wherever the name is used**, not only inside functions: in
another global's initializer, in a struct initializer list, anywhere at file
scope. Measured on a file with all of those - `static int *g_ptr = &g_a;`
and `.p = &g_b` in a designated initializer both come out purple, alongside
the references inside the function.

The query is deliberately narrow. It matches declarations at file scope only,
and never through a `function_declarator` - `int helper(int);` is a
declaration too, and a wildcard would have painted every function name as a
global variable. The declaration itself is left alone, since it is already
navy bold. A local that shadows a global wins, because the local is what the
code actually touches: a `g_count` redeclared inside a function comes out
teal, not purple.

Globals that arrive from a header are not marked. This pass only knows what
the file in front of it declares, and from the file alone an `extern` name
cannot even be told apart from a function.

Measured on a file holding every local-declaration shape: 31 uses painted,
and calls (`helper`, `printf`), struct members (`m`), file-scope variables
(`g_global`) and the declarations themselves are all left alone.

### Green means the index can take you there

A struct, enum, typedef, function or macro reference keeps its green only
while `global` can find a definition for that name. When it cannot, the name
drops to body colour - because green is a promise that `Ctrl+]` will land
somewhere, and a promise that fails is worse than no colour at all.

Mostly only the *missing* case is painted - known and not-yet-asked render
as before, so scrolling never flashes black and a pending answer costs
nothing. The exception is a constant that turns out not to be a macro. nvim's
own query gives an enum constant and an object-like `#define` the same
`@constant`, so both start red; the index is what tells them apart, by the
source line it hands back with the definition.

A macro you *call* is green, and only an object-like one stays red. At the
point of use `MIX(a, b)` is a call; `LIMIT` is a constant. The index hands
back the definition line with the answer, and that line settles it: `(`
immediately after the name, or not. `#define LIMIT (5)` keeps its parens and
stays red, because the separator between name and value breaks the match.
Checked over every `#define` in the 441 files this tree's index covers -
6,340 lines, 1,385 function-like, 4,954 object-like - the rule disagrees
with "what character follows the name" exactly zero times. It moves roughly
429 of the 447 function-like macros in the indexed set from red to green.

Bold still means *a real function*: a function call keeps treesitter's green
bold, a macro call gets plain green. Log macros are the exception, green and
bold, because they were asked for that way.

The definition alone does not settle it, though. `#define MIX(a,b)` is
function-like, but `MIX` written without parentheses is a reference, not a
call, and reads like a constant - so it goes red. Treesitter answers that
exactly: green needs the node to be the `function` field of a
`call_expression`. `MIX(p, 2)` is; `MIX` on its own is not.

`EXPORT_SYMBOL` and its family are navy by *name*, not by path. Path does not
work here: from the outer root this tree's index finds `EXPORT_SYMBOL` in
`kernel/common/include/asm-generic/export.h`, and from `kernel/common` it
finds it nowhere at all - `include/linux/export.h` is in neither list. A
colour that depends on which directory you opened is not a colour. The
pattern is an unanchored `find`, so the one entry `EXPORT_SYMBOL` covers
`_GPL`, `_NS` and `_NS_GPL` too; in the indexed files that is 872 + 165 + 5
occurrences.

`module_platform_driver` joins them for the same reason, and by name for a
second one: its header, `include/linux/platform_device.h`, also holds
`platform_get_drvdata` and friends, which are ordinary accessors and should
stay green. A path pattern cannot separate the two; a name pattern can. It
covers `module_platform_driver_probe` as well, and there are 16 uses of it
across the indexed files.

What it exports is green bold. The name inside `EXPORT_SYMBOL(sym)` is always
something this file defines - that is what exporting means - so it is painted
without asking the index at all. nvim's query calls it `@variable` and leaves
it body-coloured, which reads as "unknown" when it is the opposite.

Order matters more than the rules do. Navy-by-path is tested first, then the
log vocabulary, then function-like shape. It has to be that way round:
`MODULE_INFO(tag, info)` in `include/linux/module.h` ends in `_info`, so the
log vocabulary claims it, and it is function-like, so the new rule claims it
too - but it is a declaration site and belongs in navy. Nothing in this tree
shows it (neither database indexes `module.h`), which is exactly why the
order was worth fixing before it could.

Enum constants *stay* red - they were briefly painted green back, on the
reading that green means "the index can jump here", which is true of them.
Red is the better answer: a named constant is a named constant, and an
enum member and an object-like `#define` do the same job at the point of
use. What the index decides is which of the two a name is, not what colour
constants get. A constant the index cannot place still drops to body colour,
so red keeps meaning "I know what this is".

Telling an enum member from everything else needs no new query - the
definition line already came back with the lookup. An enum member's line
begins with its own name and then stops, or carries `,`, or `= value`:
`COMP_DISABLE	= 0,`, `BF_BYPASS,`, `PCM_RUN,`. A global puts a type in
front and a `;` behind (`int G_FLAG = 5;`), and a macro starts `#define`.
Checked against 15 lines taken from the real index - 7 enum members, 8 that
must not be red (two macros, a struct member, a function, a typedef close,
two globals) - the rule separates them all. Definition sites are untouched
either way: `@si.declaration.enumconst` is skipped before any of this.

Inside a function the rule reads whole:

| | |
|---|---|
| function call the index knows | green, bold |
| macro called like a function (`#define NAME(`) | green |
| the same macro named without calling it | red - it is a reference, not a call |
| `EXPORT_SYMBOL(sym)` | navy bold; `sym` green bold |
| `module_platform_driver(...)` | navy bold - a declaration, not a call |
| struct / union / enum / typedef the index knows | green |
| enum constant the index knows, used | red |
| macro the index confirms | red |
| anything the index cannot place | body colour |
| struct members | green when the index has one, body colour otherwise - GNU Global's default parser records few of them |
| `goto done` | green - it is a reference, like any other |
| `done:` | red, bold, underlined - the place itself |

Measured on a project built for it: `lib_send` green bold, `packet`, `mode`,
`pkt_t` green, `M_A`, `LIMIT` and `WRAP` red, `missing_fn`,
`MISSING_MACRO`, `id` and `name` black.

**How the index is asked, and two wrong answers on the way there.**

`global --result=ctags-x -d -e '^(a|b|c)$'` does work - the 512-byte pattern
buffer is what had failed before (511 bytes rc=0, 512 bytes rc=1 with
`global: buffer overflow. strlimcpy(dest, '...', 512)`, and the pattern
behind the original "returns nothing" was 1009). But working is not the same
as usable: an anchored alternation has no literal prefix, so `global` cannot
use the btree and reads the whole database. On the dev server's 70MB GTAGS
an eleven-name query sat at 98% CPU until a 60-second timeout killed it. The
same eleven names, asked one at a time inside a single shell loop, take
**0.16s** - 15ms each, an indexed seek. Four hundred times faster, and the
process count, which is what a shared box actually feels, is still one.

The second wrong answer: `global -d` exits 0 whether or not it finds
anything - only the output differs. Judging by exit code marked every absent
name as found, and the feature silently painted nothing at all.

Four things the review caught, all of which would have painted the screen
wrong:

- `static`, `const` and `volatile` carry `@si.type.ref`, the same capture as
  a real type name, so without a node-type check every line of C would have
  gone black. Only `identifier` and `type_identifier` nodes are asked.
- Locals and parameters are never asked. GTAGS holds no locals, so the
  answer would always be "absent" - which would black out the blue
  declarations and the olive uses that were just added. An ALL-CAPS local is
  the sharp case: nvim's own query calls it `@constant`, indistinguishable
  from a macro by capture alone, so the filter is by name against the
  enclosing function's declarations.
- A failed `global` (non-zero exit) records nothing, and three failures in a
  row stop the feature for the session with a notice. Writing "absent" on
  failure blacks out a file; retrying forever is worse - `global` lives in
  `~/.local/bin`, which only `~/.profile` puts on `PATH`, so a session
  without it had `ionice` failing on its behalf with rc=127 on every repaint.
  The binary is resolved through `exepath()` once now.
- The watchdog sends `TERM` and `KILL` together, and `VimLeavePre` kills
  synchronously. Scheduling the `KILL` 500ms later through `defer_fn` loses
  it when nvim exits in between - one `global` was left running at 98% CPU
  on the shared server that way.
- An index change drops the `missing` half of the cache and moves the found
  half aside to be re-checked while it keeps painting. Dropping all of it
  made every black mark vanish and slowly return after each `:w`; keeping
  it, as before, left a function you removed from the list green for the
  rest of the session.

| | |
|---|---|
| `g:sihl_index = 0` | off (`:SiHlIndexToggle`, `:SiHlIndexClear`, `:SiHlIndexStatus`) |
| `:SiHlIndexAdd` | find the file that defines this symbol, add it to the index, index it, repaint |
| `g:sihl_index_autoadd = 1` | do that by itself when the cursor rests on a black symbol (off by default) |
| `:SiHlIndexWhy` | why *this* name is that colour: which database was asked, what the cache holds, what `global` says right now, and how many files the index list covers |
| `g:sihl_index_budget` | `global` processes per minute, default 30 |
| `g:sihl_index_delay` / `_pad` / `_batch` / `_names` / `_timeout` | 200ms, 20 lines, 2 batches, 40 names each, 5s watchdog |
| `g:sihl_index_db` | `'chain'` (the module default) asks the database above the file, then the ones above it; `'near'` only the nearest, `'root'` only the outermost - vim-ide's `.vimrc` sets `'root'` |
| `g:sihl_index_nodb_ttl` | seconds a "no GTAGS above this file" verdict is trusted, default 30 (0 = until `:SiHlIndexClear` or the next index this nvim builds) |
| `g:sihl_index_nice` | 0 drops the `nice`/`ionice` prefix |
| `g:sihl_index_member_budget` | ms per paint spent resolving struct members, default 25 (0 = no limit). The rest are left untouched, as while an answer is pending, and the next paint 60 ms later carries on - after an edit every member on screen is resolved again, which on a 6,600-line file held the screen for 60 ms and more. In insert mode a pass that runs out of budget does not re-arm itself; the rest is painted on leaving insert mode |
| `g:sourceinsight_local_color` | a different colour for the local uses, e.g. `'#6b8e23'` for the old yellow-green |

**Turning a black symbol green.** `:SiHlIndexAdd` on it searches the sources
for the file that defines it, adds that file to the preset, indexes just it,
and repaints - the machinery `Ctrl+]` already used as its last resort, put on
a key. `g:sihl_index_autoadd = 1` does it when the cursor rests on one.

**The search prefers a definition to a mention.** The patterns were one set,
and `struct foo;` satisfied them, so asking the kernel about
`platform_device` returned headers whose only mention of it is that forward
declaration. They are split now: a strong pass wants an opening brace on a
`struct`/`union`/`enum`/`typedef`, a `#define`, or a function shape, and the
old looser set runs only if the strong one finds nothing - a definition whose
brace sits on the next line is still reachable that way, since grep works a
line at a time. Measured on the kernel tree: strong returns
`include/linux/platform_device.h` alone, weak returns the `mach-s3c` and
`qcom` headers that started this.

**A symbol the index already knows is never searched for.** Running the
search anyway means grepping the whole tree and putting the result in the
preset, and the result is not what you want: asked about `platform_device`,
which the database already placed in `include/linux/platform_device.h`, the
grep returned seven headers that merely say `struct platform_device;` -
`arch/arm/mach-s3c/cpu.h`, `drivers/clk/qcom/common.h`,
`drivers/dma/dw/internal.h` and the like - and every one of them went into
the preset. Forward declarations are mentions, not definitions.

Automatic is deliberately narrow: the symbol under the cursor, one at a time,
no sooner than `g:sihl_index_autoadd_gap` seconds apart, and never the same
name twice. Doing it for every black name on screen would be dozens of
whole-tree searches per screen, each over a second on a kernel tree, on a box
with sixty cores and eight hundred other people.

**"It jumps, so why is it black?"** came up repeatedly, with a different
answer each time: the outer database was being asked; a long-running session
was holding a cache from before that was fixed (`:SiHlIndexClear`); or the
defining file is simply outside the preset. `:SiHlIndexWhy` settles it in one
command. A worked case: `snd_kcontrol` in `tcc-snd-card.c` came out black,
and `include/sound/control.h`, where `struct snd_kcontrol` is defined, is not
among the 414 files that project's preset indexes - `global -d` and
`taglist()` both return nothing for it, so black was the truthful answer.

**On a preset index most of a kernel screen will be black, and that is the
answer, not a fault.** A preset indexes a chosen subset - 1,452 files out of
a QNX SDK - so `task_struct`, `WARN_ON` and `ENOMEM` genuinely are not in
that database and `Ctrl+]` genuinely will not find them. Measured on a
701-file preset: 25 of 42 symbols on one screen. Add the files (`\fa`,
`:ProjectFilesReindex`) and they go green again; `g:sihl_index = 0` if you
would rather not know.

**Which database answers matters, and it is not the one the panel uses.**
`platform_get_drvdata` and `snd_soc_card_get_drvdata` came out black while
`Ctrl+]` found them without trouble: the module was asking `d5_qnx_hyp`'s
GTAGS, which holds 39 files under `kernel/common` and knows neither, while
`kernel/common`'s own GTAGS knows both. The outermost root is RelationView's
rule - it decides what the panel answers from and what paths are measured
against - but colour has to agree with where `Ctrl+]` actually lands, which
is the nearest database above the file (`Ctrl+]` then tries the ones above it,
up to four, so a symbol only the outer index knows is still found).
`g:sihl_index_db = 'root'` restores the old choice.

**Colour follows the index when the list changes.** After `+` / `-` in the tree, `\fx`, `:ProjectFilesAdd` / `:ProjectFilesRemove`, a preset switch or a reindex, the colours catch up as soon as the index has been rewritten, even while the focus stays in the tree. Before, a `-` never took the green away, because the module assumed a reindex only adds definitions. A `+` showed only once the cursor moved in a C window: measured, 28 s in the tree with nothing changing. autoindex now announces every finished GTAGS change (`User VimIdeIndexUpdated`, with the root and whether it was a full build, an incremental update or a single-file save), and every visible C/C++ window in the tab is checked again:

- Green names are not wiped. They keep their colour while they are re-checked, so nothing flickers; only the answer changes them. The names most likely to have changed go first: definitions in a file that just left the list (or that you just saved), then names that were black. So a `-` turns its functions black in one small query. Measured on a 300-file preset: about 110 ms after the index update, 270-310 ms after the keypress; 70-90 ms at 6,500 files with stat slowed to 100 µs. A `+` brings its names back with the next batch: 0.5-0.8 s with about 45 unknown names on screen, about 0.2 s at 6,500 files.
- A save re-checks only what that file defined, plus the black names, as before. A list change, or an index change nobody announced (another nvim, a `gtags` run in the shell), re-checks everything on screen.
- An answer computed while the database was being rewritten is thrown away and asked again once the database has been quiet for half a second. Such answers come from a half-written index, and asking during a long `gtags -i` would otherwise use up the per-minute `global` budget.
- The ctags snapshot and `taglist()` answers now follow the preset too: a line from a file that is not in `<root>/.tags/files` is ignored. The snapshot is not rebuilt when you `-` from the tree, and it kept a removed function green ("ctags" in `:SiHlIndexWhy`) while `global -d` had nothing. Auto-mode projects (no list) are unaffected. `taglist()` is now asked in the buffer that wanted the answer, not in whichever window has the focus; from the tree it used to come back empty.
- The database key includes the nanoseconds of GTAGS's mtime. Removing files never changes the file's size, so two updates within the same second used to look identical.

**The first index of a project colours by itself.** A file opened before a mode was chosen used to remember "no GTAGS here" until `:SiHlIndexClear`. Picking a preset or pressing `+` then built the index, and the buffer stayed uncoloured. Now the finished index clears that memory: the first marks appear about 0.2 s after the index exists, and the whole screen about 0.6 s. A database built outside this nvim (another instance, a shell `gtags`) is noticed after `g:sihl_index_nodb_ttl` seconds. The chain of databases is also read again after `:cd`, after a list change, and when a database it relied on has disappeared. Before, that case meant three failed `global` runs and the feature switching itself off for the session.

**When autoindex does not announce.** With an older autoindex that does not send `VimIdeIndexUpdated`, a list change starts a light watch on the database (one stat per root every 0.5 s, for at most 60 s) and recolours once the database has been rewritten, about 1 s later. The watch never runs once an announcement has been seen.

The per-keystroke cost is unchanged: one `stat` and about 2 ms per repaint at both 300 and 6,500 listed files, with or without a 100 µs stat. Handling an index update costs 0.6-3 ms and two stats, including re-reading a 6,500-line list. `:SiHlIndexStatus` also counts the names waiting to be re-checked. `:SiHlIndexWhy` reads the chain from disk and shows such a name as "찾음 (색인이 바뀌어 다시 확인 중)".

**Both passes run in the context window too**, on the same rules as the edit
window - a preview that coloured its copy differently from the file would be
worse than no colour. The preview is a scratch copy, so its buffer name
cannot name a project; `_G.relationview_ctx_path()` says which file is on
show and the root is taken from that.

Verified end to end against a real GTAGS, in both windows: `no_such_function`,
`UNKNOWN_MACRO` and `absent_helper_qqq` painted black, `helper_add`,
`render_point`, `struct point`, `platform_get_drvdata` and
`snd_soc_card_get_drvdata` left green, every local and parameter left to the
teal pass.

## The symbol outline (nvim only)

`<F10>` opens **aerial**, on the left where tagbar used to sit. `:Tagbar` is
still there for the files aerial cannot read - aerial's backends are
treesitter, LSP, markdown and man, with no ctags fallback, so a language
without a parser shows nothing. `let g:vimide_outline = 'tagbar'` puts the
old one back everywhere.

**Only `<F10>` opens it.** It used to appear by itself whenever you opened a
file with symbols in it, which sounds convenient and was not: aerial runs
with `attach_mode = 'window'`, so `open_automatic` is asked again every time
you *enter an edit window*, not every time you open a file. Split the window
and move down into the new one and a second outline appeared there. Press
`<F10>` to close it and it came back the moment focus landed anywhere else.
A switch that turns itself back on is not a switch. So the automatic path is
gone: `<F10>`, `<leader>o` and `:AerialOpen` open it, and all three are
things a person pressed.

| | |
|---|---|
| `g:vimide_outline_auto = 1` | open by itself again, as before. Read when the decision is made, so `:let` works mid-session |
| `g:vimide_outline_startup = 1` | open it at startup too (deferred 200 ms - at `VimEnter` neither the buffer nor treesitter is ready, and it would open empty) |

`h` and `l` move the cursor in there, which sounds like it should not need
saying. Aerial ships them as collapse and expand, so inside the outline you
could go up and down but not sideways - press `h` and instead of the cursor
moving left, the symbol under it folded shut. They are handed back
(`keymaps = { ['h'] = false, ['l'] = false }`; a `false` makes aerial skip
the mapping, and the table merges deeply so nothing else changes). Folding
loses nothing: `o` toggles, `za`/`zo`/`zc` do the same, and the recursive
forms stay on `O` and `zA`/`zO`/`zC`. `H` and `L` are left alone - in vim
those are not sideways, they are top and bottom of the screen; add
`['H'] = false, ['L'] = false` to take them back too. Measured in the
outline: `virtcol` 1, `5l` to 6, `2h` to 4, and `j` still steps a line.

The old automatic behaviour, kept intact behind that option, also refuses
while neo-tree is up. Both want the left column, so with the tree open,
moving to another file had aerial elbow in and push the tree aside - `F9`
closing aerial was not enough, because the next file brought it straight
back. `open_automatic` takes a function, so it answers no while a `neo-tree`
window is in the tab (and keeps aerial's own `is_ignored_buf` check, which
the plain `true` form applies for you).

Two things make it behave like Source Insight's Symbol Window:

| | |
|---|---|
| move the cursor in the outline | the edit window follows to that symbol, focus stays in the outline (`autojump`) |
| double-click a symbol (or press `v`) | the edit window selects that function **including the comment above it**, with the selection's first line at the top of the window (the cursor sits on that line; `o` goes to the end) |
| `yy` `Y` `3yy` `y{motion}` / visual `y` | copy that symbol (or those) **including the comment above** into the register |
| `dd` `3dd` `d{motion}` / visual `d` `x` | cut it from the edit window - deleted into the register like vim's `dd` (`"1`-`"9` shift, `"_dd` deletes for good) |
| `p` / `P` `3p` | paste the register below / above the symbol under the cursor, in the edit window |
| `u` / `Ctrl+r` | undo / redo in the edit window |
| `.` | repeat the last `d` / `y` / `p` |

The outline edits like a text buffer whose lines are symbols: every key
above is vim's own key and does to the symbol's lines in the edit window what
it would do to a line here, with focus staying in the outline. A row is the
same range a double-click selects (the comment above through the end); several
rows (`3dd`, a visual range) are one piece of the source from the first
symbol's comment to the last symbol's end, so whatever lies between goes too.
Registers are vim's - copying and cutting run `:yank` / `:delete` in the edit
window - so `"ayy`, `"ap`, `"_dd` work, `ddp` swaps a function with the next,
and the edit window's own `p` pastes what the outline copied. Blank lines are
kept tidy: a cut takes one of two blank lines that would end up adjacent, and a
piece copied or cut in the outline is pasted with one blank line between it and
its neighbour (text copied elsewhere goes in line for line). After each change
the outline re-reads the buffer at once (an edit made from the outline raises
no `TextChanged` in the edit window, so aerial used to catch up only when you
went there) and its cursor goes where vim's would: onto what was pasted, or
the symbol that took the cut one's place. aerial's own `p` (scroll the
preview) gives way, since `autojump` already shows the symbol.

The selection is the useful unit: a function without the comment that says
what it is for is rarely what you wanted to copy or move. The comment is
found through treesitter rather than a regex - walk up from the function's
first line while the node covering that line is a `comment`, allowing
`g:aerial_range_blank_gap` (1) blank lines between the comment block and the
function, since that is how most of this tree is written. Measured on a file
with all three shapes: a `/* */` block above `alpha` gave lines 3-9, two `//`
lines and a blank above `beta` gave 11-18, and `gamma_no_comment` with
nothing above gave just the function, 20-23. `g:aerial_range_comments = 0`
selects the function alone. `:AerialSelectRange` does the same from a
mapping of your own.

Why aerial over tagbar at all: on measurement they are close - walking eight
real kernel sources, tagbar stalled the UI twice for 100 ms total and aerial
once for 62 ms. (An earlier note here claimed tagbar cost seconds per file;
that was a benchmark that wiped the buffer before each open, which forces a
synchronous rebuild that normal editing never triggers.) The reasons that
survived are the outline itself - 27 entries against tagbar's 57 on the same
file, because treesitter lists what you navigate by and ctags also lists
macros, prototypes and variables - and that nothing has to spawn a process.

## Yellow marks (nvim only)

Put the cursor on a symbol, press `<F8>`, and every occurrence of it goes
yellow and stays yellow. Press `<F8>` on it again and the mark comes off.
Several symbols can carry the mark at once, and the marks follow you -
split the window or open another file and they are painted there too.
`.vim/plugin/yellowmark.lua`, black on `#ffff00`.

That is how you read code in Source Insight: pin the two or three names
this function is really about, then stop looking for them.

| | |
|---|---|
| `<F8>` | toggle the mark on the symbol under the cursor |
| `:YellowMarkList` | which symbols are marked |
| `:YellowMarkClear` | take them all off |

Three highlights can sit on one word, so the order matters. vim-mark
(`F4`) uses priorities from -10 down to -67, and the automatic reference
highlight sits far below at -1010; a yellow mark is something you asked
for by hand, so it goes above both at -8 (`g:yellowmark_priority`).

One `matchadd` per window covers every marked symbol - the words are
joined into a single `\V\%(\<a\>\|\<b\>\)` pattern - so marking more
symbols does not cost more per window. Unlike the reference highlight,
this one does not skip C keywords: if you press `<F8>` on `int`, you
meant `int`.

## Reference highlight (nvim only)

Source Insight washes every visible occurrence of the symbol under the
cursor in pale blue as you move around, which is how you see where a
variable is used without searching for it. `.vim/plugin/refhighlight.lua`
does the same with SI's own colour (`#000000` on `#aae1ff`).

It paints 80 ms after the cursor stops, on a window-wide `matchadd`, so the
cost does not grow with the file. It stays out of the way of keywords,
one-character names, strings and comments, and it sits *below* `F4`
(vim-mark) and search highlighting, which use higher match priorities.

```vim
let g:refhighlight = 0             " off
let g:refhighlight_delay = 150     " ms after the cursor stops
let g:refhighlight_min = 3         " ignore names shorter than this
:RefHighlightToggle
```

### F3 cycles four layouts

`<F3>` walks the four states in order:

| | |
|---|---|
| relation + context | the list at the bottom, the preview beside it |
| relation only | just the list |
| context only | just the preview - and it follows the cursor in the edit window |
| off | neither |

The state is read off the screen rather than remembered, so `<F3>` does the
intuitive thing even after you closed a window by hand or moved to another
tab. `:RelationViewMode both\|relation\|context\|off` jumps straight to one.

Four states is the default, not the rule - pick the ones you actually use and
the order you want them in:

```vim
let g:relationview_cycle = ['context', 'off']          " just the preview
let g:relationview_cycle = ['both', 'off']             " all of it, or none
let g:relationview_cycle = ['relation', 'context']     " swap between the two
let g:relationview_cycle = ['context', 'both', 'off']  " three
```

If the layout you are looking at is not in your list - you set it with
`:RelationViewMode`, or closed a window by hand - `<F3>` goes to the first
entry. A name that is not one of the four is dropped with one warning, and a
list with nothing usable in it falls back to the default order.

**A new startup default: context only.** The relation list takes twelve rows
off the bottom and is not always what you want; the definition of the symbol
under the cursor, sitting beside the code, is useful the whole time you are
reading. `let g:relationview_startup = 'both'` restores the old layout
(`'relation'` and `'off'` are the other two).

With the panel open the context window previews *the row you are on in the
list* - that is what it has always done. On its own there is no list to read
from, so it does what Source Insight's Context Window does: takes the symbol
under the cursor in the edit window, asks gtags where it is defined, and
shows that. One `global -d` per symbol, on `CursorHold`, skipped when the
symbol has not changed. `g:relationview_ctx_debug = 1` logs why it decided
to do nothing, into `stdpath('cache')/rvctx.log`.

### Paths in the panel

Navy, the colour vim uses for paths everywhere else, and the whole path from
the project root:

```
kernel/common/include/sound/soc.h:437
kernel/common/sound/soc/telechips/tcc-snd-card.c:1243
```

**The same file always reads the same**, wherever nvim was started. That
needs saying because the obvious implementation does not do it. Relative to
`:pwd` a file moves as you move. Relative to the root the panel queried it
still moves, because this tree has a project inside a project - start inside
`kernel/common`, which owns a `.tags` of its own, and `soc.h` shrinks to
`include/sound/soc.h`. So the base is the *outermost* indexed root: walk up
past every nested one, stopping at `$HOME`.

| `g:relationview_path_base` | |
|---|---|
| `'root'` (default) | from the outermost indexed root - stable |
| `'pwd'` | vim's own `%:.`, relative to `:pwd`, absolute for anything outside it |
| `'abs'` | absolute. `g:relationview_full_path = 1` is the old name for this |

**Nothing is cut.** The path column used to cap at a fraction of the panel
width and elide at the front, which is fine for `src/util.c` and useless for
`subcore/build/tcc8070-sub/tmp/work-shared/tcc8070-sub/kernel-source/sound/soc/telechips/tcc-snd-card.c`
- the half you needed was the half that got eaten. Now the whole path is
printed. The column is still padded to line up the source text, but only
while that fits the panel; past that each row uses just the width it needs
and the source column starts wherever the path ends. Ragged, and complete.
`let g:relationview_path_truncate = 1` brings the old clipping back.

### Which index answers the question

This tree has a project inside a project - `d5_qnx_hyp` has a `.tags`, and
so does `kernel/common` underneath it. They are not the same database: the
outer one indexes 39 files under `kernel/common`, the nested one 407. Ask
the nested database and you get fewer answers, and different ones depending
on where you happened to start nvim.

So the panel pins itself to the *outermost* index, the same one the paths
are measured from. Standing in `d5_qnx_hyp/kernel/common/sound/soc` now
gives the same `References (undefined symbol) (4)` as standing in
`d5_qnx_hyp`; before this it gave 3. If the outer index provably does not
contain the file - it has a `.tags/files` list and the file is not in it -
the search falls back to the nearest one that does, so a file outside the
big index is still searchable.

| `g:relationview_db_base` | |
|---|---|
| `'root'` (default) | the outermost indexed root, whatever `:pwd` is |
| `'cwd'` | the old behaviour: the index nearest `:pwd`, then the one nearest the file |

`:Gtags` into the panel (`<leader><leader>s` and the rest of those maps while
it is open) asks the same index as the tree and `Ctrl+/`. It used to ask the
nearest one, so in a nested project `<leader><leader>s` could report 0
callers that the tree right above it listed. `:Gtags -f %` works in the panel
too (`%` and `#` are expanded the way gtags.vim does, and a file named from
the cwd is passed to `global` relative to the root).

With the panel closed the search is gtags.vim's own, and gtags.vim runs
`global` in the cwd - which only looks for an index from there upwards.
Started above every index root, each quickfix search (the `<leader><leader>`
maps, `:GtagsQf`, `<C-\><C-]>`, and `<C-]>` when the tags have no answer)
said `GTAGS not found`. When the cwd's index does not hold the file, vim-ide
now sets `GTAGSROOT`/`GTAGSDBPATH` to the file's index for that one call -
`global` still answers relative to the cwd, so the quickfix entries open as
usual. Started inside a project, nothing changes; a `GTAGSROOT` you set
yourself is left alone.

## Relation window (nvim only)

The Source Insight style relation window opens by itself when nvim starts
(set `g:relationview_auto_open = 0` to keep it closed; it is always skipped
in diff mode and in git's editor sessions). `F3` toggles it and
`:RelationView` opens it on demand. While it is open, resting the cursor on
a symbol in a source window updates the panel in real time with the
definition and the caller tree:

```
── Definition ──────────────────────
  util_log             src/util.c:4
── Callers (4) ─────────────────────
  ├─[+] main           src/main.c:12
  ├─[-] util_add (x2)  src/util.c:11
  │   ·  util_add      src/util.c:16
  │  ├─[+] helper      src/main.c:5
  │  └─[+] util_mul    src/util.c:19
  └─[+] rec_a          src/util.c:30
```

Each row is the symbol, where it is, and the source line itself as a third
column (`g:relationview_show_text = 0` drops that column when the panel is
narrow; the context window shows the line either way). Resizing the panel (`Shift+h` / `Shift+l`, or
resizing the terminal) lays the columns out again, so the paths always use
the width that is actually there.

What the panel shows depends on the symbol under the cursor:

```
function          definition + the expandable caller tree (below)
struct/union/enum definition + its members
typedef           definition + the members of the type behind it
variable          its declaration in the function (parameters included),
(struct, enum,    the definition and members of its type, and every use
 or plain)        of the variable inside that function
member access     the member of the type the VARIABLE was declared with,
(msg->cmd,        so the right struct is used even when several structs
 ctx.id)          have a member of that name
enum constant     the enum it belongs to, focused on that constant
```

An `#include "foo.h"` or `#include <a/b.h>` line is about a file, not a
symbol: the header goes in the Definition section (with the symbols gtags
knows about it below) and the context window shows the header itself. The
header is looked up next to the including file, then in the GTAGS path
index, then in 'path'.

Paths follow the rules in [Paths in the panel](#paths-in-the-panel) above:
the whole path from the outermost indexed root, in navy, never cut.

The row under the panel cursor has its symbol coloured sky blue, and the
same symbol is highlighted in the context window.

For a variable the context window opens on its TYPE definition, so simply
resting the cursor on a variable in the edit window shows what it is made
of. Selecting a member row moves the context window to that member, and a
use row moves it to that line inside the function.

The panel queries the same GTAGS database `:Gtags` does - the one above
the working directory - so both agree line for line. (Searching from the
file's own directory would pick up a stale nested GTAGS left in a
sub-directory, which reports different files and different line numbers.)
Up to `g:relationview_max_refs` references are listed (default 1000); when
there are more, the section header says how many of how many are shown.

A caller that calls the symbol several times shows every call site: the
first one on its own row (marked `(xN)`) and the rest as `·` rows beneath
it, so the list matches `:Gtags -r` line for line
(`g:relationview_max_sites`, default 8, caps how many are listed).

Each node is a calling function; expanding a node queries the callers of
that function, so the call chain can be followed to any depth. A caller
that already appears higher up in the chain is marked `↺` (recursion) and
stops there. Expanding a node pins the panel automatically so cursor moves
do not rebuild the tree; press `p` to unpin.

A context window (Source Insight style) shows the source around the
location under the panel cursor, centred on the referenced symbol. By
default it is a split inside the panel (below the tree in the 'right'
layout, beside it in 'bottom'); `g:relationview_context_position = 'right'`
(or `'left'`) gives it a window of its own next to the file you are
editing instead, so the panel keeps the whole bottom and the preview the
full height - that is the layout this setup ships with
(`g:relationview_context_width` sets its width, capped at half the edit
window so a narrow screen stays usable). Jumps land exactly on the referenced symbol - line and
column - and if the file changed since the last gtags run the symbol is
re-located within +-30 lines automatically.

The context window is a preview, never a driver: resting the cursor on a
symbol there does not rebuild the relation tree, and it renders a copy of
the file rather than the file itself, so a quickfix jump (`Ctrl+9` / `Ctrl+0`,
`]q` / `[q`, or `Ctrl+n` / `Ctrl+p` when the panel holds no list), `:tag` or
`gf` always lands in a real edit window instead of taking over the preview. Inside the context window
`Ctrl+]` (and a double click) follows the symbol under the cursor within that
window only - a parameter or a local variable goes to its declaration in the
function being previewed, everything else to its definition - the source windows and the tree stay untouched - and
`Ctrl+t` walks back along the context window's own jump stack. A double
click in the context window takes the edit window to the line under the
mouse.

While the panel is open, `:Gtags -d`, `:Gtags -r` and friends (so
`<leader><leader>c` and the rest of those maps) list their results **in the
panel** instead of the quickfix window, as a `Gtags -r foo (27)` section
that behaves like any other list here - Ctrl+n/Ctrl+p, preview, Enter,
Ctrl+Enter. With the panel closed the original quickfix behaviour is
untouched (`g:relationview_capture_gtags = 0` turns the capture off).

Keys inside the panel:

```
Enter: jump to the call site under the cursor (lands on the symbol)
Ctrl+Enter: the same jump, but it works from ANY window - after walking the
       list with Ctrl+n / Ctrl+p from the edit window, this is how the walk
       ends in the edit window (:RelationViewJump). Like the other Ctrl'ed
       punctuation keys it needs a CSI u terminal; Enter inside the panel
       does the same thing everywhere.
Ctrl+n / Ctrl+p: next / previous item in the list. It works from ANY
       window: the panel's cursor moves and the context window previews
       that call site, centred on the symbol, while the EDIT WINDOW STAYS
       WHERE IT IS - this is for reading through the call sites, not for
       going to them. The focus does not move either, so the keys can be
       pressed again; Enter in the panel is what actually goes there.
       With no relation list in the panel the same keys walk the quickfix
       list, and Ctrl+9 / Ctrl+0 (or ]q / [q) always mean quickfix.

Browsing the list - a mouse click on a row, j/k, Ctrl+n/Ctrl+p - marks the
panel PINNED, so the tree you are reading cannot be rebuilt under you; only
the context window follows. A DOUBLE click takes the edit window to that
symbol (the panel stays pinned). Resting on a symbol in a source window for
g:relationview_unpin_delay ms releases the pin and the panel follows the
cursor again - or press `Ctrl+c` (`p` inside the panel) to release it now.
`Ctrl+c` outside a pinned panel keeps whatever it meant before (the
checksymbol.vim CONFIG lookup here).

While the focus is in the context window, `Ctrl+n` / `Ctrl+p` still walk the
relation list and the preview follows to each hit, so a search can be read
through without leaving that window (a late redraw still cannot yank the
preview away while you are following symbols inside it with `Ctrl+]`).

`Ctrl+]` in an edit window opens the definition **in the context window**,
moves the focus there, and switches the panel to that symbol - pinned, so
its callers stay in front of you while you read (`Ctrl+n`/`Ctrl+p` then walk
that new list). The edit window stays where it is, so it remains the place
you are working in. `Ctrl+t` walks back: right after the jump it
returns the focus to the edit window, and if you kept following symbols
with `Ctrl+]` inside the context window it unwinds that window's own stack
first and hands the focus back only when it reaches the spot the jump
started from. `<leader><leader>c` (`:Gtags -r`) behaves the same way - the
hits are listed in the panel and the focus lands in the preview, `Ctrl+t`
returns. A double click in the edit window now does exactly what `Ctrl+]`
does - a function goes to the preview, a parameter or local to its
declaration, an `#include` to that header - so `Ctrl+Enter` (and `Enter` in
the panel) are what move the edit window to a list item.
double click: same jump, with the mouse

In the edit window a double click behaves like `Ctrl+]` in every case: a
symbol the index knows opens in the context window (with the panel switching
to it, pinned), a parameter or a local variable goes to its declaration in
the edit window, and an `#include` line opens that header there.
In the context window a double click follows the definition of the symbol
under the mouse - like `Ctrl+]` there - and on an `#include` line it opens
that header in the context window (`Ctrl+t`, `Ctrl+o` or the mouse back
button returns, `Ctrl+i` or the forward button follows it again), while
`Enter` takes the edit window to the line under the cursor. Special windows (quickfix, NERDTree, tagbar)
keep their own double-click behaviour.
mouse button 4 / 5: back / forward, exactly like Ctrl+o / Ctrl+i (the
       panel's jumps land in the jumplist too, so they are undone the same
       way); from the panel they move the edit window, and in the context
       window they walk that window's own stack
o:     jump but keep focus in the panel (peek)
Space: expand/collapse the caller under the cursor (+ and - work too)
*:     expand the whole tree (bounded by max_depth/max_nodes options)
O (zO): expand everything under the symbol at the cursor - all its callers,
       their callers and so on (same limits, counted from that symbol;
       cycles are skipped); on an already open [-] row it opens what is
       still closed below
X (zC): collapse everything under the symbol at the cursor; the rows below
       stay closed too, so the next + opens one level again
x:     export the current tree as an HTML call graph (Source Insight
       style boxes) and open it in the browser - not 'g', which would
       swallow the first key of 'gg'
c:     toggle the context window
p:     pin - freeze the current symbol (auto update stops until unpinned)
r:     refresh - drop the cache and query gtags again (use after F2)
a:     toggle realtime auto update
q:     close the panel (and its context window)
```

`:RelationView {symbol}` looks up an explicit symbol and
`:RelationViewGraph` exports the graph without focusing the panel.
Options such as `g:relationview_position` ('bottom' or 'right'),
`g:relationview_height`, `g:relationview_width`,
`g:relationview_debounce`, `g:relationview_max_refs`,
`g:relationview_max_depth` and `g:relationview_max_nodes` can be set in
`.vimrc` - see the header of `~/.vim/plugin/relationview.lua`.

Note for nvim: cscope support was removed in nvim 0.9+, so the
`<leader><leader>` cscope shortcuts above are transparently remapped to the
equivalent `:Gtags` queries in nvim (`<leader><leader>d` opens the relation
window). Plain vim keeps the original cscope behavior.

## Session restore (nvim only)

`:qa` 로 닫을 때의 작업 상태 - 창 분할, 각 창의 파일과 커서, 열려 있던 옆 창 -
를 적어 두고 다음에 그대로 다시 연다. 저장은 자동, 되살리기는 물어봤을 때만.

    nvim               지금까지와 똑같이 기본 상태로 연다 (아무것도 안 바뀐다)
    nvim +Restore      지난번 :qa 자리로 연다
    nvim +Restore x.c  지난번 자리로 열고 x.c 를 EDIT 창에 띄운다

    :Restore / :VimIdeRestore   지금 nvim 안에서 되살린다
    :VimIdeSessionSave          지금 배치를 바로 적는다
    :VimIdeSessionWhere         이 프로젝트의 세션 파일 자리

세션은 디렉터리가 아니라 **프로젝트 루트**마다 하나다. 같은 SDK 를 하위
디렉터리에서 열어도 같은 세션을 찾는다. 파일은
`~/.local/state/nvim/vim-ide/sessions/` 아래에 세션과 그 짝(`...x.vim`) 두
개로 놓이고 직전 것은 `.bak` 로 한 벌 남는다. 소스 트리 밖이라 커널
저장소의 `git status` 에 뜨지 않고 `.tags/` 의 preset/색인 데이터와 섞이지도
않는다. `nvim -S <그 경로>` 로 열어도 옆 창까지 따라온다.

되살리는 것: 창 배치와 크기, 각 창의 파일과 커서, 폴드, 버퍼 목록, 탭, 그리고
'무엇이 떠 있었나' (RelationView both/relation/context, 그 열의 neo-tree,
세로 전체 context, 왼쪽 neo-tree, aerial, tagbar, NERDTree, quickfix 창).

미리보기(context)는 창만이 아니라 **보고 있던 자리까지** 되살린다. 저장할 때
{파일, 줄, 심볼}을 적어 두었다가 그대로 다시 그린다. 그 파일이 그새 없어졌으면
아무것도 하지 않는다 - 없는 파일을 열면 그 이름으로 빈 버퍼가 생기고 :w 한 번에
진짜 파일이 되기 때문이다.

vim-mark 로 칠해 둔 색(F4, LookupReferences 가 쓰는 그것)도 같이 돌아온다.
mark#ToList() 로 적고 mark#Load() 로 되돌린다. 색은 미리보기를 그리기 전에
먼저 되돌려서, 되살아난 미리보기에도 칠해진 채로 뜨게 한다.

되살리지 않는 것: telescope 뜬창, 터미널 버퍼, quickfix 의 **목록**(색인을
다시 만들면 줄 번호가 어긋나 오히려 위험하다 - 창만 빈 채로 연다),
RelationView 의 점프 스택과 pin 상태(다시 질의하는 편이 낫다).

패널 버퍼는 nofile 스크래치라 그냥 `:mksession` 을 찍으면
`enew | file RelationView` 로 적힌다. 그대로 되살리면 프로젝트 안을 가리키는
'쓸 수 있는 빈 파일 버퍼'가 생기고 `:wa` 한 번에 RelationView 라는 파일이
진짜로 만들어진다. 그래서 저장 직전에 패널을 먼저 닫고 찍는다 - 실측으로
세션 파일의 enew 줄 수는 0 이다.

| 변수 | 기본값 | |
|---|---|---|
| `g:vimide_session` | `1` | `0` 이면 기능 전체를 끈다 - 명령도 안 만들고 저장도 안 한다 |
| `g:vimide_session_save` | `1` | `0` 이면 저장만 끈다. `:Restore` 와 `:VimIdeSessionSave` 는 그대로 |
| `g:vimide_session_cd` | `1` | `0` 이면 되살릴 때 저장 당시 디렉터리로 옮기지 않는다 |
| `g:vimide_session_dir` | `stdpath('state').'/vim-ide/sessions'` | 세션 파일 자리 |

vim(개발 서버)은 `plugin/*.lua` 를 읽지 않으므로 이 기능은 nvim 에만 있다.
`.vimrc` 는 한 줄도 건드리지 않았다.

## How to make gtags for multi directory

To make gtags for multi directory, use `mktags.sh` command below. <br/>

```
Usage : mktags.sh {DIR1} {DIR2}...


        =======================================================================
        Ex1) mktags.sh .
        Ex2) mktags.sh maincore/external/tinyalsa maincore/kernel
        Ex3) mktags.sh maincore/external/tinyalsa maincore/kernel subcore/build/tcc8050-sub/tmp/work/aarch64-telechips-linux/t-sound/1.1.0-r0/git
             ...
        -----------------------------------------------------------------------

```
