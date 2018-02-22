#! /bin/bash

[ "$1" == "-d" ] && d=1 && shift
[ $# -lt 2 -o $# -gt 3 ] && echo "Usage: $0 [-d] <index> <name> [<host>]" && exit 1

h="${3:-http://localhost:9200}"
o="$1"; [ "${o:$((${#o}-1))}" == "-" ] || o+="-"; o+="$2.jsonl.gz"

es-sample -h "$h" -c - -o "$o" "$1" && zgrep -c '^ *{' "$o" || exit 1

[ -n "$d" ] && curl -sSXDELETE $h/$1 && echo

exit 0
