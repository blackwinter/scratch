#! /bin/bash

name="$(basename "$0")"
real="$(type -ap "$name" | head -2 | tail -1)"

[ -z "$real" ] && echo "command not found: $name" && exit 1
[ ! -x "$real" ] && echo "command not executable: $real" && exit 1

args=""
plus=""

while [ -n "$1" ]; do
  arg="$1"; shift

  if [[ "$arg" =~ (.+):([0-9]+)(:.*)?$ ]]; then
    file="${BASH_REMATCH[1]}"
    line="${BASH_REMATCH[2]}"

    if [ -f "$file" ]; then
      args="$args $file"

      if [ -z "$plus" ]; then
        args="$args +$line"
        plus="1"
      fi

      continue
    fi
  fi

  args="$args $arg"
done

exec $real $args
