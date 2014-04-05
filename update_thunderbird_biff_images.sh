#! /bin/bash

# run this script after any update of the thunderbird biff
# (https://addons.mozilla.org/en-US/firefox/addon/3788) extension
# to replace the default indicator images with your favourite ones.

# replacement images and path
i="n?*Mail.png"  # {no,new}Mail.png
b="$(dirname "$0")"

# paths to thunderbird and firefox
t="$HOME/.thunderbird"
f="$HOME/.firefox"

# extension ID and path to extension's image directory
e="{aee74dd0-6dc9-11db-9fe1-0800200c9a66}"
p="default/extensions/$e/chrome/skin/classic/images"

for d in "$t"; do
  q="$d/$p"  # the actual path we're acting on

  if [ -d "$q" ]; then
    chmod u+w "$q"/$i
    cp -v "$b"/$i "$q"
  else
    echo "not found: $q"
  fi
done
