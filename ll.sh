#! /bin/bash

# Find the longest line in a file

[ $# -ne 1 ] && {
  echo "Usage: $0 <file>";
  exit 1;
}

[ -r "$1" ] || {
  echo "File not found: $1";
  exit 1;
}

i=0; j=0; k=0

while read l; do
  i=$((i + 1))
  n=$(echo "$l" | wc -c)
  
  [ "$n" -gt "$k" ] && {
    k="$n";
    j="$i";
  }
done < "$1"

echo "$j"
