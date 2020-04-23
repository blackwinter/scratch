#! /bin/bash

# server-map: short-cuts to ssh to, scp from/to, or ssh-mount remote hosts

function warn() {
  [ -n "$1" ] && echo "$1" >&2
}

function die() {
  warn "$1"
  exit 1
}

# server.map:
#
#   map=(
#     name:host:user
#     ...
#   )
mapfile="$(dirname "$0")/server.map"
[ ! -r "$mapfile" ] && die "map file not found: $mapfile"

source "$mapfile"
[ ${#map[*]} -eq 0 ] && die "no server map: $mapfile"

real="server-map.sh"
name="$(basename "$0")"

shopt -s extglob

if [ "$name" = "$real" ]; then
  # create symlinks
  cd "${1:-$HOME/bin}" || die

  for item in "${map[@]}"; do
    entry=(${item//:/ })

    for prefix in "+" "-" "2" "4" "cp2"; do
      link="${prefix}${entry[0]}"

      if [ -e "$link" ]; then
        if [ -h "$link" ]; then
          if [ "$(readlink -- "$link")" != "$name" ]; then
            warn "! $link: not pointing to $name"
          fi
        else
          warn "? $link: not a symbolic link"
        fi
      else
        warn "+ $link -> $name"
        ln -s -- "$name" "$link"
      fi
    done
  done
else
  base="${name/#@(+|-|2|4|cp2)/}"

  # connect to host
  for item in "${map[@]}"; do
    entry=(${item//:/ })
    [ "${entry[0]}" = "$base" ] && break
  done

  host="${entry[1]}"
  user="${entry[2]}"

  if [ "$1" == "-l" ]; then
    user=$2
    shift 2
  fi

  [ -z "$host" ] && die "no host name: $base"
  [ -z "$user" ] && die "no user name: $base"

  case "$name" in
    +* )
      mnt="$HOME/mnt/$base"
      [ ! -d "$mnt" ] && die "no mount point: $base"

      warn "mounting $mnt [$user@$host]..."
      sshfs -o sshfs_sync,transform_symlinks,cache_timeout=5 "$user@$host:/" "$mnt"

      home="$mnt/home/$user"
      [ -d "$home" ] && warn "> $home"
      ;;
    -* )
      mnt="$HOME/mnt/$base"
      [ ! -d "$mnt" ] && die "no mount point: $base"

      warn "unmounting $mnt [$user@$host]..."
      fusermount -u "$mnt"
      ;;
    2* )
      warn "$user@$host"
      ssh -l "$user" "$host" "$@"
      ;;
    4* )
      rport="$1"; shift
      lport="${1:-$rport}"; shift

      lhost="localhost"

      warn "$user@$host:$rport -> $lhost:$lport"
      ssh -l "$user" "$host" "$@" -fNL "$lhost:$lport:$lhost:$rport"
      ;;
    cp2* )
      args=()

      while [ -n "$1" ]; do
        args+=(${1/#:/$user@$host:})
        shift
      done

      scp "${args[@]}"
      ;;
    * )
      die "unknow command: $name"
      ;;
  esac
fi
