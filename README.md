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

* Auto completion: opens a popup menu to complete using tab

* File system explorer: browses directory hierarchies, and performs file system operations

* Source code browser: provides an overview of the structure of the source code. Moving the cursor onto a symbol in the tagbar window - with j/k, the arrows or a single mouse click - takes the edit window to that symbol while the focus stays in tagbar (set g:tagbar_follow_cursor = 0 to turn it off).

* Git status check: uses signs to indicate added, modified and removed lines based on data of an underlying version control system.

* Smooth scrolling: moves smoothly the screen when exploring source code.

* Magit-style git UI (nvim only): `Neogit` opens the whole staging/commit/push workflow in a tab (`<leader>s`), with `diffview.nvim` for side-by-side diffs (`<leader>v`).

* Symbol outline (nvim only): `aerial.nvim` lists the current file's symbols in a side window (`<leader>o`), built on treesitter so it needs no language server. Tagbar (F10) stays as it was.

* Automatic symbol index (nvim only): both indexes maintain themselves. `vim-gutentags` keeps the ctags `tags` file current and `~/.vim/plugin/autoindex.lua` does the same for GTAGS, so RelationView, `:Gtags` and `<leader>fs` are always in sync without pressing F2. **Starting nvim refreshes the index of the project in front of you in the background** - an incremental `gtags -i` when it exists (2s on a 69k-file kernel tree), a full build when it does not (26s there) - and saving a file updates that one file in milliseconds. `:GtagsIndex` rebuilds, `:GtagsIndexRefresh` updates incrementally, `:GtagsIndexUpdate` does the current file and `:GtagsIndexStatus` says what is running. **`Ctrl+]`, `:tag` and `g]` are answered from GTAGS** through nvim's `'tagfunc'`, so a jump works the moment a file is saved (8 ms on a 69k-file kernel tree) and needs no ctags file at all; when gtags has nothing to say, the normal tags-file lookup still runs, and an LSP client that sets its own `'tagfunc'` per buffer still wins there. Which files get indexed is decided in one place - `~/.local/bin/indexfiles.sh`: a project's own `.indexfiles`, else `git ls-files` (tracked and new files, honouring `.gitignore`), else `cscope.files` (what F2 writes), else a find over the source extensions. Drop an `.indexfiles` in a project root to index exactly the files you care about. `cscope.files` ranks below git on purpose: an F2 run that is interrupted leaves a partial list behind, and rebuilding from it drops every symbol outside it. For the same reason a rebuild that would cover less than half of what the current index covers asks first (`:GtagsIndex`) or is skipped (automatic), and every build reports how many files it indexed.
* Where the index lives: `GTAGS`, `GRTAGS` and `GPATH` go into a hidden **`.tags/` directory in the project root**, so nothing visible is dropped into the source tree, and a database still sitting at a project root (what F2 used to write) is moved there the first time the project is opened. GNU global only looks inside such a directory when `GTAGSOBJDIR` names it, so `.vimrc` exports `GTAGSOBJDIR=.tags` once - one value that works in every project, in every subdirectory, and still finds an old root-level database. In a terminal: `eval "$(gtagsenv.sh)"`, or put `export GTAGSOBJDIR=.tags` in `~/.zshenv`. The directory is added to `.git/info/exclude` (local, never committed) so it stays out of `git status`. `let g:autoindex_dbdir = ''` puts the database back in the project root.
* Trees larger than `g:autoindex_ctags_max_files` (5000) get their **ctags file built by `autoindex.lua` instead of gutentags**, once per project in the background (0.9 GB / 47 s for a 69k-file kernel tree) and never on save - gutentags rewrites the entire tags file whenever a file in the project is saved, which costs seconds at that size. It is refreshed when older than `g:autoindex_ctags_max_age` days (7), rebuilt by `:CtagsIndex`, and switched off with `g:autoindex_ctags = 0`. `g:autoindex_ctags_args` chooses the flags: the default `--fields=+n --excmd=number` trades search patterns for line numbers (~30% smaller); drop `--excmd=number` to keep patterns, which survive edits made outside nvim. `:GtagsIndex`, `:GtagsIndexUpdate` and `:GtagsIndexStatus` drive gtags by hand; `:GtagsIndex`, `:GtagsIndexUpdate` and `:GtagsIndexStatus` drive it by hand.

* Modern file tree (nvim only): `neo-tree.nvim` (F9, or `<leader>t`) shows git status inline and creates/deletes/renames with `a`/`d`/`r`. NERDTree is still one key away on F11 (right side).

* Project files (nvim only): `<leader>fo` finds and opens a file from what is indexed (a telescope picker, `^d` drops it from the list, `^a` adds more), `<leader>fp` picks files to add. Two modes: **auto** - the whole project, as before - and **preset**, where only the files and directories you picked are indexed. Adding a file brings the headers it includes and the files defining the symbols it uses along with it, and the index follows immediately; presets are named, reusable across checkouts, shipped with vim-ide itself so every machine has them, and one can be made the startup default. See "Project files and presets" below.
* Relation window (nvim only): Source Insight style panel across the bottom of the screen, with the context preview in a column of its own down the right side, showing the definition and an expandable multi-depth caller tree of the symbol under the cursor in real time. The tree can be expanded per node or all at once, and exported as an HTML call graph. It uses the same GTAGS database created with F2. It opens automatically on startup; toggle with F3.


## Usage (shortcut)

This section describes mapping keys for Vim IDE.

```
F1: Show a man page for the keyword under the cursor.
F2: Source files under the current path are indexed; `cscope.files` is written to the project root and the GPATH/GRTAGS/GTAGS database into `<root>/.tags/` (F12 removes both). With automatic indexing this is rarely needed.
F3: Toggle RelationView, Source Insight style relation window (nvim only)
F4: Mark the keyword under the cursor, the keyword is highlighted in different colors
F5: Clear all marks
F6: Toggle MiniBufExplorer, source file explorer on the top side
F7: Fold a function body
F8: Unfold a function body
F9: Toggle neo-tree, file system explorer on the left side (tagbar is closed with it, since both live on the left)
F10: Toggle tagbar, source code browser on the right side
     (the cursor or a mouse click on a symbol jumps to it in the edit window)
F11: Toggle NERDTree, file system explorer on the right side
F12: Delete gtags files created with F2.
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
\fo: Find a file among the indexed ones and open it (^d drop, ^a add)
\fp / \fd: Pick files / directories to add to the project files list
\fx: Remove entries    \fm: Choose the preset    \fS: Save it    \fR: Reindex
Ctrl+]: Open the definition in the context window and focus it; Ctrl+t back
Ctrl+9, Ctrl+0: Next/previous quickfix item, always. These two keys only
     reach nvim from a terminal that speaks CSI u (the kitty keyboard
     protocol): iTerm2 3.5+, kitty, WezTerm, Ghostty, foot. ]q / [q do the
     same everywhere, so use those if your terminal stays silent.
Shift+h, Shift+l, Shift+k, Shift+j:  Resize between split windows
Ctrl+h, Ctrl+l, Ctrl+k, Ctrl+j:  Move between split windows
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

<leader>s: Neogit - Magit style git status in a new tab (s stage, u unstage, c commit, P push, ? help)
<leader>v: DiffviewOpen - side by side diff of the working tree
<leader>o: Toggle the aerial symbol outline of the current file
<leader>t: Toggle the neo-tree file tree, same as F9 (a add, d delete, r rename)
<leader>fs: Search every symbol in the project through the ctags index
:GtagsIndex / :GtagsIndexUpdate / :GtagsIndexStatus: GTAGS index by hand
:GutentagsUpdate!: rebuild the ctags index of this project by hand

Ctrl+g: Find the keyword under the cursor, and displays the results via quickfix window
Ctrl+n: Go to the next error in the quickfix window
Ctrl+p: Go to the previous error in the quickfix window
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
\fo  find an indexed file and open it   (^d drop it, ^a add files)
\fp  pick files to add                  (<Tab> for several at once)
\fd  pick directories to add            (everything indexable under them)
\fx  pick entries to drop               (files and directories)
\fm  choose the preset                  (auto included, ^d deletes mine)
\fS  save the current entries as a preset
\fR  reindex now
\fs  find any symbol in the index      (<F3> sends it to the relation window)
\fw  the same, for the symbol under the cursor
```

(`<leader>` is `\` in this setup.) Every one of them is a telescope picker
with a preview, multi-select where it makes sense, and the same commands
behind it: `:ProjectFilesFind`, `:ProjectFilesAdd`, `:ProjectFilesAddDir`,
`:ProjectFilesRemove`, `:ProjectFilesPreset`, `:ProjectFilesSave`,
`:ProjectFilesReindex` (each takes an optional argument to skip the picker),
plus `:ProjectFilesPresetShare` (below).

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

Dropping the last entry puts the project back in auto mode rather than
leaving an empty list behind (an empty list would index nothing, and the old
index would sit there stale).

Adding, dropping or switching reindexes immediately (an incremental
`gtags -i`, which also drops what left the list), and saving a file that is
NOT in the preset does not sneak it into the index. Which preset a project
uses is remembered in `<root>/.tags/preset` and applied again when nvim
starts; `g:projectfiles_preset` names the one to fall back on for a project
that has none yet. Adding a path while in auto mode starts a preset for you.

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

Select lines with `v`, `V` or `<C-v>` and `+` / `-` act on the whole
range. That is one commit, not one per line: adding a path rewrites the
preset, re-expands the list (a `find` per directory entry) and reindexes,
so doing it fifty times over would be fifty of those. A six-line range
takes 79 ms where the same six done one at a time take 200 ms, and it
reports once - `추가 3개 (항목 0 -> 3)` - instead of once per line. The
tree root line is skipped if the selection catches it, since indexing the
root would make the preset the whole project.

Every change reindexes by itself - from the tree, from `\fp` / `\fd` /
`\fx`, from the commands. It used to go through `:GtagsIndexRefresh!`,
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

`^d` in that picker deletes only my copy - which is how the last case goes
back to following the shared one; the shared original is removed by deleting
the file in the repository. To ignore the shared presets entirely:
`let g:projectfiles_shared_presets = ''`, or point it at a directory of your
own.

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
| Esc | `ttimeoutlen=100` plus the network made every Esc take a measured 131 ms. It is 25 ms now - twice the measured RTT, so a split arrow-key sequence still arrives in time |
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
  make cheap. Above a size threshold the marks are switched off instead -
  decided from one stat of `.git/index` (5.4 MB for those 56k files) - and
  it says so once, with the size, so a missing mark is not a mystery.

```vim
let g:vimide_neotree_git = 1         " always on, whatever the size
let g:vimide_neotree_git = 0         " always off
let g:vimide_neotree_git_max_mb = 2  " the threshold (default 2)
```

Counted live on the kernel repo while opening neo-tree, walking into a
subdirectory and revealing a file: forced on, one git process at 89%, then
97% eight seconds in, then a second at 121%. With the guard, none at any
step.

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

Paths are shown relative to vim's current directory (`:pwd`), the way vim
itself shows them; `g:relationview_full_path = 1` makes them absolute.

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
that header in the context window (`Ctrl+t` or the mouse back button
returns), while `Enter` takes the edit window to the line under the cursor. Special windows (quickfix, NERDTree, tagbar)
keep their own double-click behaviour.
mouse button 4 / 5: back / forward, exactly like Ctrl+o / Ctrl+i (the
       panel's jumps land in the jumplist too, so they are undone the same
       way); from the panel they move the edit window, and in the context
       window the back button walks that window's own stack
o:     jump but keep focus in the panel (peek)
Space: expand/collapse the caller under the cursor (+ and - work too)
*:     expand the whole tree (bounded by max_depth/max_nodes options)
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
