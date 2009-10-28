#! /bin/bash

enc="$1"; shift
[ -z "$enc" ] && echo "Usage: $0 <enc> [inputfile]..." && exit 1

iconv -f "$enc" -t "$enc" "$@" > /dev/null
exit $?
