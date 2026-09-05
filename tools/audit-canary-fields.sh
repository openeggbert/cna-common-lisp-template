#!/bin/sh
# Every CANARY field the program emits must be documented in README.md.
#
# The canary's output is its interface: a script greps those lines, and a reader
# is told what to expect from them. The README's example block had fallen four
# fields behind the program -- triangle_pixel, render_target_pixel, font and
# text_pixel were all being emitted and none of them was written down -- which is
# the same drift the binding generates its own claims to avoid. The field names
# are enumerable, so they are checked.
#
# This checks *coverage*, not the values: what a field reports depends on the
# renderer, and the README says so in prose.
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
status=0

# The field names the program can print, taken from the format strings that
# print them rather than from a list kept beside them.
fields=$(grep -ho 'CANARY [a-z_]*=' "$here"/src/*.lisp \
             | sed 's/^CANARY //; s/=$//' | sort -u)

if [ -z "$fields" ]; then
    echo "audit-canary-fields: found no CANARY fields in src/ -- the pattern that" >&2
    echo "  extracts them has stopped matching, which would make this audit vacuous" >&2
    exit 1
fi

for field in $fields; do
    if ! grep -q "^CANARY $field=" "$here/README.md"; then
        echo "audit-canary-fields: src/ emits 'CANARY $field=' and README.md does not document it" >&2
        status=1
    fi
done

# And the other way: a documented field the program cannot emit is a promise
# nothing keeps.
documented=$(sed -n 's/^CANARY \([a-z_]*\)=.*/\1/p' "$here/README.md" | sort -u)
for field in $documented; do
    if ! echo "$fields" | grep -qx "$field"; then
        echo "audit-canary-fields: README.md documents 'CANARY $field=' and src/ never emits it" >&2
        status=1
    fi
done

if [ "$status" -eq 0 ]; then
    echo "every CANARY field the program emits is documented"
    echo "$fields" | sed 's/^/  /'
fi
exit "$status"
