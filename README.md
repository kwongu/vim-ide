# Vim IDE
colorscheme : jellybeans

## Download
git clone --depth 1 --recurse-submodules https://github.com/kwongu/vim-ide.git ${HOME}/.vim-ide

## Installation
cd ${HOME}/.vim-ide <br/>
./install.sh

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

* Source code browser: provides an overview of the structure of the source code.

* Git status check: uses signs to indicate added, modified and removed lines based on data of an underlying version control system.

* Smooth scrolling: moves smoothly the screen when exploring source code.

* Relation window (nvim only): Source Insight style panel that shows the definition and an expandable multi-depth caller tree of the symbol under the cursor in real time. The tree can be expanded per node or all at once, and exported as an HTML call graph. It uses the same GTAGS database created with F2. Toggle with F3.


## Usage (shortcut)

This section describes mapping keys for Vim IDE.

```
F1: Show a man page for the keyword under the cursor.
F2: Source files under the current path are indexed and cscope.files, GPATH, GRTAGS and GTAGS files are created.
F3: Toggle RelationView, Source Insight style relation window (nvim only)
F4: Mark the keyword under the cursor, the keyword is highlighted in different colors
F5: Clear all marks
F6: Toggle MiniBufExplorer, source file explorer on the top side
F7: Fold a function body
F8: Unfold a function body
F9: Toggle NERDTree, file system explorer on the left side
F10: Toggle tagbar, source code browser on the right side
F11: Empty
F12: Delete gtags files created with F2.
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

Press `F3` (or run `:RelationView`) to open the Source Insight style relation
window. While it is open, resting the cursor on a symbol in a source window
updates the panel in real time with the definition and the caller tree:

```
── Definition ──────────────────
  src/util.c:4 │ void util_log(const char *msg)
── Callers (4) ─────────────────
  ├─[+] main      src/main.c:12 │ util_log("done");
  ├─[-] util_add  src/util.c:11 │ util_log("add");
  │  ├─[+] helper   src/main.c:5 │ return util_add(x, 1);
  │  └─[+] util_mul src/util.c:19 │ r = util_add(r, a);
  └─[+] rec_a     src/util.c:30 │ util_log("a");
```

Each node is a calling function; expanding a node queries the callers of
that function, so the call chain can be followed to any depth. A caller
that already appears higher up in the chain is marked `↺` (recursion) and
stops there. Expanding a node pins the panel automatically so cursor moves
do not rebuild the tree; press `p` to unpin.

Keys inside the panel:

```
Enter: jump to the call site under the cursor
o:     jump but keep focus in the panel (peek)
Space: expand/collapse the caller under the cursor (+ and - work too)
*:     expand the whole tree (bounded by max_depth/max_nodes options)
g:     export the current tree as an HTML call graph (Source Insight
       style boxes) and open it in the browser
p:     pin - freeze the current symbol (auto update stops until unpinned)
r:     refresh - drop the cache and query gtags again (use after F2)
a:     toggle realtime auto update
q:     close the panel
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
