#! /bin/bash

# Find the longest line in a file

[ $# -lt 1 ] && {
  echo "Usage: $0 <file> ...";
  exit 1;
}

while [ -n "$1" ]; do
  f="$1"; shift

  [ -r "$f" ] || {
    echo "File not found: $f" >&2;
    continue;
  }

  i=0; j=0; k=0

  while read l; do
    i=$((i + 1))
    n=$(echo "$l" | wc -c)
  
    [ "$n" -gt "$k" ] && {
      k="$n";
      j="$i";
    }
  done < "$f"

  echo "$j $f"
done
