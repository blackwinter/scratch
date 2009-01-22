#! /bin/bash

# Simple directory snapshot tool using git.

git="$(which git)"
[ -z "$git" ] && echo "Please install git first!"

gitdir="$(git rev-parse --git-dir 2> /dev/null)"
[ -z "$gitdir" -a "$1" != "--init" ] && echo "Not in a snapshot repository! Create a new one with '$0 --init'."

snapshotdir="$(dirname "$gitdir")"

# exit on error
set -e

function git() {
  [ -z "$git" -o -z "$gitdir" ] && exit 1

  echo "> git $@"
  $git "$@"
}

function commit() {
  git add --verbose "$snapshotdir"
  git commit --all --message "${1:-snapshot commit}"
}

case "$1" in
  --init )
    [ -z "$git" ] && exit 1

    [ -n "$2" ] && mkdir -p "$2" && cd "$2"
    $git init
    ;;
  -t|--tag )
    if [ -n "$2" ]; then
      commit "$3"
      git tag -a "$2"
    else
      git tag -l -n1
    fi
    ;;
  -l|--list )
    git whatchanged --reverse --pretty=format:"%Cred%h %Cgreen%ai %Cblue%an %Creset- %s" --name-status
    ;;
  -d|--diff )
    git diff "${2:-HEAD}" "${3:-.}"
    ;;
  -s|--status )
    git status --all
    ;;
  -v|--view )
    git show "${2:-HEAD}":"$3"
    ;;
  -w|--switch )
    git checkout "${2:-master}"
    ;;
  -h|--help )
    echo "Usage: $0 [options]"
    echo
    echo "        --init [path]                               Create a new snapshot repository"
    echo
    echo "    -c, --commit [<commit-msg>]                     Commit all changes"
    echo "    -t, --tag                                       Display all existing tags"
    echo "    -t, --tag <tag-name> [<commit-msg>]             Commit all changes and create a new tag"
    echo "    -l, --list                                      Display the history of all changes"
    echo "    -d, --diff                                      Show the current changes"
    echo "    -d, --diff <commit-hash> [path]                 Show the changes for given commit"
    echo "    -s, --status                                    Display the current status"
    echo "    -v, --view {<commit-hash>|<tag-name>} <path>    View a previous version of the file"
    echo "    -w, --switch {<commit-hash>|<tag-name>}         Switch to the specified version"
    echo "    -w, --switch                                    Switch back to the current version"
    echo "    -h, --help                                      Print this help and exit"
    echo
    echo "With no options, or only a commit message given, acts like --commit."
    ;;
  * )
    commit "$1"
    ;;
esac
