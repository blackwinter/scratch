#! /bin/bash

function die() { echo "$1"; exit 1; }

[ $# -lt 2 -o $# -gt 3 ] && die "Usage: $0 <FILE> <START> [<END>|+<NUM>|-<NUM>]"

f="$1"
s="$2"
e="${3:-+1}"
n="${e:1}"
o="${e::1}"

[ "$f" == "-" -o -r "$f" ] || die "No such file: $f"

[[ "$s" =~ ^[0-9]+$ ]] || die "Illegal argument: $s"

function snip() {
  [[ "$n" =~ ^[0-9]$1$ ]] || die "Illegal argument: $e"
  [ $# -gt 1 ] && head -n $2 "$f" | tail -n ${3:-$n}
}

case "$o" in
  [0-9] )
    snip "*" $e $(($e - $s + 1))
    ;;
  + )
    snip "+" $(($n + $s - 1))
    ;;
  - )
    snip "+" $s
    ;;
  * )
    snip "-"
    ;;
esac
