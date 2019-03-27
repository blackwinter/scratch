#! /bin/bash

[ "$1" == "-c" ] && c=$1 && shift
[ "$1" == "-d" ] && d=$1 && shift

[ $# -lt 2 -o $# -gt 3 ] && echo "Usage: $0 [-c|-d] <index> <name> [<host>]" && exit 1

h="${3:-http://localhost:9200}"
o="$1"; [ "${o:$((${#o}-1))}" == "-" ] || o+="-"; o+="$2.jsonl.gz"

if [ -z "$c" ]; then
  es-sample -h "$h" -c - $d -o "$o" "$1" && zgrep -c '^ *{' "$o" || exit 1
  exit 0
else
  [ -f "$o" ]
fi
