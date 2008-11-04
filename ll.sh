#! /bin/bash

# Find the longest line in a file

t=0; m=0; b="$(basename "$0")"

if [ "$#" -gt 0 ]; then
  t="$#"
else
  echo "Usage: $b <file> ...";
  exit 1
fi

w="$(
  wc -l "$@" 2> /dev/null | sort -n |\
  tail -2 | head -1 | awk '{ print $1 }' | wc -c
)"

while [ -n "$1" ]; do
  f="$1"; shift

  [ -r "$f" ] || {
    echo "$b: $f: No such file or directory" >&2;
    continue;
  }

  i=0; j=0; k=0

  while read l; do
    i="$((i + 1))"
    n="$(echo "$l" | wc -c)"
  
    [ "$n" -gt "$k" ] && {
      k="$n";
      j="$i";
    }
  done < "$f"

  [ "$j" -gt "$m" ] && m="$j"

  printf "%${w}d %s\n" "$j" "$f"
done

[ "$t" -gt 1 ] && printf "%${w}d total\n" "$m"
