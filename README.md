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

* Symbol outline (nvim only): `aerial.nvim` lists the current file's symbols in a side window (F10 or `<leader>o`, and only when you press it), built on treesitter so it needs no language server. `:Tagbar` stays as it was.

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
F7: Search any symbol the index knows, the same as `\fs` (nvim only). It used to fold a function body; `zf` still does that, as do `za`/`zo`/`zc`
F8: Stick a yellow mark on the symbol under the cursor, and take it off by pressing it again there (nvim only). It used to unfold (`zo`, which is still there)
F9: Toggle neo-tree on the left (F11 used to be this one; aerial closes with it, since both want the left)
F10: Toggle tagbar, source code browser on the right side
     (the cursor or a mouse click on a symbol jumps to it in the edit window)
F11: Toggle NERDTree on the right (F9 used to be this one)
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
so working in an outer tree keeps `\fo`, `\fp`, `\fd` and the tree on the
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

### Borrowing a nested project's list

Sometimes the files you want are the ones a nested project already picked -
you are working in the outer tree, but the list lives in
`kernel/common/.tags`. `:ProjectFilesAbsorb` copies those in, rebased on
the current root, so `child/.tags/files` holding `src/b.c` becomes
`child/src/b.c` here.

What comes across is the nested project's *index list*, file by file, so
re-expanding it here cannot change what it contains. A nested project in
auto mode has no list, so it comes across as one directory entry - that
tree, whole.

It is not automatic. A preset is a hand-picked thing and pushing a few
hundred entries into one at startup without asking is how presets get
wrecked. When there is something to take, it says so once:

```
하위 프로젝트 2곳이 골라 둔 파일 3개를 이 프로젝트 목록으로 가져올 수 있습니다
(:ProjectFilesAbsorb)
```

Running it twice is a no-op - entries already present are skipped.

```vim
let g:projectfiles_absorb = 1        " do it when a project is first opened
let g:projectfiles_absorb_hint = 0   " not even the notice
```

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
there too. What neo-tree does not have yet is the marks; those need a
custom renderer component, and this added only the four operations.

Select lines with `v`, `V` or `<C-v>` and `+` / `-` act on the whole
range. That is one commit, not one per line: adding a path rewrites the
preset, re-expands the list (a `find` per directory entry) and reindexes,
so doing it fifty times over would be fifty of those. A six-line range
takes 79 ms where the same six done one at a time take 200 ms, and it
reports once - `추가 3개 (항목 0 -> 3)` - instead of once per line. The
tree root line is skipped if the selection catches it, since indexing the
root would make the preset the whole project.

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
| a question | dropping `g:projectfiles_confirm_drop` entries or more (20) asks first. A visual range asks once at the end, not per line; headless says it and continues |
| a copy | every write keeps the previous file under `<presets>/.backup/<name>.<stamp>.json`, newest 20 (`g:projectfiles_backups`) |
| a way back | `:ProjectFilesRestore` lists those with their entry counts and the delta against now; `:ProjectFilesRestore 20260909-004155` takes one straight away |

The copy is taken on the path that used to lose the most, too: dropping the
last entry deletes my copy of the preset and falls back to auto mode, and
that delete now backs up first. It also writes the name to
`.tags/preset.last`, because the restore needs a name and auto mode has
none - so `:ProjectFilesRestore` still works right after the list went
empty, and turns the preset back on when it restores.

Two smaller things that came out of the same reading. Entries are
normalised and deduplicated on write: `grep -rl … .` answers with `./` on
the front, `add_for_symbol` stored that verbatim, and a `./x` entry could
not be matched by `x` - so it could not be removed and a second copy of it
could be added. And when you take one file out of a directory entry, the
entry is rewritten as the files that remain; that list is now deduplicated
against what the preset already had, which is where 21 doubled entries
under `sound/soc/telechips_dpcm/` came from.

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
The current buffer alone is already `\fp` to add and `\fx` to remove.

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
and for windows too narrow to spare the room, and off entirely with
`let g:overview = 0`. Colours are taken from whatever colourscheme is
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
alias pair, `<F17>`/`<F18>` plus `<S-F5>`/`<S-F7>` by default. Both names are
bound because the same bytes - `ESC [15;2~` and `ESC [17;2~` - are read as a
high function key by some builds and as a shifted one by others; only one
ever arrives.

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
tab if you press it in insert mode; the escape-sequence route has no such
overlap. If Tera Term runs elevated and AutoHotkey does not, Windows blocks
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
`@constant`, so both start red; once the index says `M_A` is an enum and not
a `#define`, leaving it alone would leave it red. Those are painted green
back.

Inside a function the rule reads whole:

| | |
|---|---|
| function call the index knows | green, bold |
| struct / union / enum / typedef the index knows | green |
| enum constant the index knows | green |
| macro the index confirms | red |
| anything the index cannot place | body colour |
| struct members | green when the index has one, body colour otherwise - GNU Global's default parser records few of them |
| `goto done` | green - it is a reference, like any other |
| `done:` | red, bold, underlined - the place itself |

Measured on a project built for it: `lib_send` green bold, `packet`, `mode`,
`pkt_t` and `M_A` green, `LIMIT` and `WRAP` red, `missing_fn`,
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
- A reindex drops only the `missing` half of the cache. Dropping all of it
  made every black mark vanish and slowly return after each `:w`.

| | |
|---|---|
| `g:sihl_index = 0` | off (`:SiHlIndexToggle`, `:SiHlIndexClear`, `:SiHlIndexStatus`) |
| `:SiHlIndexAdd` | find the file that defines this symbol, add it to the index, index it, repaint |
| `g:sihl_index_autoadd = 1` | do that by itself when the cursor rests on a black symbol (off by default) |
| `:SiHlIndexWhy` | why *this* name is that colour: which database was asked, what the cache holds, what `global` says right now, and how many files the index list covers |
| `g:sihl_index_budget` | `global` processes per minute, default 30 |
| `g:sihl_index_delay` / `_pad` / `_batch` / `_names` / `_timeout` | 200ms, 20 lines, 2 batches, 40 names each, 5s watchdog |
| `g:sihl_index_db` | `'near'` (default) asks the nearest database above the file, `'root'` the outermost |
| `g:sihl_index_nice` | 0 drops the `nice`/`ionice` prefix |
| `g:sourceinsight_local_color` | a different colour for the local uses, e.g. `'#6b8e23'` for the old yellow-green |

**Turning a black symbol green.** `:SiHlIndexAdd` on it searches the sources
for the file that defines it, adds that file to the preset, indexes just it,
and repaints - the machinery `Ctrl+]` already used as its last resort, put on
a key. `g:sihl_index_autoadd = 1` does it when the cursor rests on one.

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
is the nearest database above the file. `g:sihl_index_db = 'root'` restores
the old choice.

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
| double-click a symbol (or press `v`) | the edit window selects that function **including the comment above it** |

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
