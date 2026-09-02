#!/bin/sh

# Point GNU global(1) at the hidden databases this setup creates
# ('<project root>/.tags/').  nvim and .vimrc do this by themselves; a
# terminal needs it once:
#
#     eval "$(gtagsenv.sh)"        # this shell
#     echo 'export GTAGSOBJDIR=.tags' >> ~/.zshenv    # every shell
#
# global walks up from the current directory looking for '<dir>/GTAGS' and
# '<dir>/$GTAGSOBJDIR/GTAGS', so this one value works in every project and
# still finds a database left at a project root.

DBDIR="${1:-.tags}"
printf 'export GTAGSOBJDIR=%s\n' "$DBDIR"

d=$(pwd)
while [ -n "$d" ] && [ "$d" != "/" ]; do
	if [ -f "$d/$DBDIR/GTAGS" ] || [ -f "$d/GTAGS" ]; then
		exit 0
	fi
	d=$(dirname "$d")
done
echo "gtagsenv.sh: no GTAGS database above $(pwd) (nvim builds one, or press F2)" >&2
exit 0
