#! /bin/bash

sysencoding="${LANG#*.}"
sysencoding="${sysencoding:-ISO-8859-1}"

to="${1:-$sysencoding}"
from=(
  ISO-8859-1
  ISO-8859-2
  ISO-8859-15
  CP1250
  CP1251
  CP1252
  CP850
  CP852
  CP856
  UTF-8
)

# additional candidates: ANSI_X3.4, EBCDIC-AT-DE, EBCDIC-US, EUC-JP,
# KOI-8, MACINTOSH, MS-ANSI, SHIFT-JIS, UTF-7, UTF-16*, UTF-32*, ...

input="$(cat -)"

for encoding in "${from[@]}"; do
  printf "%-12s: %s%s\n"                                            \
    "$encoding"                                                     \
    "$(echo "$input" | iconv -f "$encoding" -t "$to" 2> /dev/null)" \
    "$([ $? -ne 0 ] && echo "<<ILLEGAL INPUT SEQUENCE")"
done
