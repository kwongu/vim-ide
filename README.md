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

* Relation window (nvim only): Source Insight style panel that shows the definition and an expandable multi-depth caller tree of the symbol under the cursor in real time. The tree can be expanded per node or all at once, and exported as an HTML call graph. It uses the same GTAGS database created with F2. It opens automatically on startup; toggle with F3.


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
     RelationView caller list when the panel holds one, the quickfix list
     otherwise
Ctrl+comma, Ctrl+period: Next/previous quickfix item, always. These two keys
     only reach nvim from a terminal that speaks CSI u (the kitty keyboard
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

Each row is the symbol and where it is; the source line itself is one
keystroke away in the context window (`g:relationview_show_text = 1` puts
it back as a third column). Resizing the panel (`Shift+h` / `Shift+l`, or
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

A context window (Source Insight style) is attached below the tree
('right' layout) or beside it ('bottom' layout): moving the cursor in the
relation list previews the source around that location, centered on the
referenced symbol. Jumps land exactly on the referenced symbol - line and
column - and if the file changed since the last gtags run the symbol is
re-located within +-30 lines automatically.

The context window is a preview, never a driver: resting the cursor on a
symbol there does not rebuild the relation tree, and it renders a copy of
the file rather than the file itself, so a quickfix jump (`Ctrl+,` / `Ctrl+.`,
`]q` / `[q`, or `Ctrl+n` / `Ctrl+p` when the panel holds no list), `:tag` or
`gf` always lands in a real edit window instead of taking over the preview. Inside the context window
`Ctrl+]` follows the definition of the symbol under the cursor within that
window only - the source windows and the tree stay untouched - and
`Ctrl+t` walks back along the context window's own jump stack. A double
click in the context window takes the edit window to the line under the
mouse.

Keys inside the panel:

```
Enter: jump to the call site under the cursor (lands on the symbol)
Ctrl+n / Ctrl+p: next / previous item in the list - the quickfix habit,
       applied to the relation list. It works from ANY window: the panel's
       cursor moves, the edit window follows to that call site, and the
       focus stays where it was, so the keys can be pressed again. The
       panel pins itself while walking (the edit window's cursor would
       otherwise rebuild the tree); press p to unpin. With no relation
       list in the panel the same keys walk the quickfix list as before,
       and Ctrl+, / Ctrl+. (or ]q / [q) always mean quickfix.
double click: same jump, with the mouse

In the edit window a double click behaves like `Ctrl+]` (jump to the
symbol under the mouse), and on an `#include` line it opens that header.
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
