#! /bin/bash

[ $# -lt 2 -o $# -gt 3 ] && echo "Usage: $0 <index> <name> [<host>]" && exit 1

h="${3:-http://localhost:9200}"
o="$1"; [ "${o:$((${#o}-1))}" == "-" ] || o+="-"; o+="$2.jsonl.gz"

es-sample -h "$h" -c - -o "$o" "$1" && zgrep -c '^ *{' "$o"
