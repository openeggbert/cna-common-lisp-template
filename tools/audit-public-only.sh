#!/bin/sh
# Prove that the template uses only CNA-Lisp's public API.
#
# It is a consumer, and a consumer that reached into a binding's internals would
# not be evidence of anything. This refuses:
#
#   * any CNA-Lisp internal package name;
#   * any CFFI package reference;
#   * any raw handle or result-code accessor;
#   * any dependency other than the public cna-common-lisp system.
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
status=0

strip_comments() {
    # Drop ;-comments so that prose about what the template does not do cannot
    # fail an audit of what it does.
    sed -e 's/;.*$//' "$1"
}

for file in "$here"/src/*.lisp "$here"/run.lisp "$here"/*.asd; do
    body=$(strip_comments "$file")
    for pattern in 'cna-lisp\.internal' 'cffi:' 'cffi::' 'sb-alien' 'handle-of' \
                   'callback-registry' 'native-library' 'ensure-abi' '%cna' \
                   'cna-lisp\.surface'; do
        if printf '%s' "$body" | grep -qiE "$pattern"; then
            echo "FAIL $file mentions $pattern"
            status=1
        fi
    done
done

if ! grep -q '"cna-common-lisp"' "$here"/cna-common-lisp-template.asd; then
    echo "FAIL the system does not depend on cna-common-lisp"
    status=1
fi

deps=$(sed -n 's/.*:depends-on (\(.*\)).*/\1/p' "$here"/cna-common-lisp-template.asd)
for dependency in $deps; do
    case "$dependency" in
        '"cna-common-lisp"') ;;
        *) echo "FAIL unexpected dependency $dependency"; status=1 ;;
    esac
done

if [ "$status" -eq 0 ]; then
    echo "the template uses only the public CNA-Lisp API"
fi
exit "$status"
