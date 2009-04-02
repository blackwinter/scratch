#! /bin/bash

# server-map: short-cuts to ssh to, scp from/to, or ssh-mount remote hosts

map=(
  #name:host:user
)

real="server-map.sh"
name="$(basename $0)"
shopt -s extglob

if [ "$name" = "$real" ]; then
  # create symlinks to ssh-to
  cd $HOME/bin || exit 1

  for i in "${map[@]}"; do
    j=(${i//:/ })

    for k in "+" "-" "2" "cp2"; do
      l="${k}${j[0]}"

      if [ -e "$l" ]; then
        if [ -h "$l" ]; then
          if [ "$(readlink "$l")" = "$name" ]; then
            echo "= $l is a symbolic link, already pointing to $name"
          else
            echo "! $l is a symbolic link, but doesn't point to $name"
          fi
        else
          echo "? $l exists, but is no symbolic link"
        fi
      else
        echo "+ $l -> $name"
        ln -s -- $name $l
      fi
    done
  done
else
  base="${name/#@(+|-|2|cp2)/}"

  # connect to host
  for i in ${map[@]}; do
    j=(${i//:/ })
    [ "${j[0]}" = "$base" ] && break
  done

  host="${j[1]}"
  user="${j[2]}"

  [ -z "$host" ] && echo "no host name for $base" && exit 1
  [ -z "$user" ] && echo "no user name for $base" && exit 1

  case "$name" in
    +* )
      mnt="$HOME/mnt/$base"
      [ ! -d "$mnt" ] && echo "no mount point for $base" && exit 1

      echo "mounting $mnt [$user@$host]..."
      sshfs -o sshfs_sync,transform_symlinks,cache_timeout=5 "$user@$host:/" "$mnt"

      home="$mnt/home/$user"
      [ -d "$home" ] && echo "> $home"
      ;;
    -* )
      mnt="$HOME/mnt/$base"
      [ ! -d "$mnt" ] && echo "no mount point for $base" && exit 1

      echo "unmounting $mnt [$user@$host]..."
      fusermount -u "$mnt"
      ;;
    2* )
      echo "$user@$host"
      ssh -l $user $host $*
      ;;
    cp2* )
      [ -z "$1" ] && { scp --help; exit 1; }

      a=(); i=0

      while [ -n "$1" ]; do
        # FIXME: quotes or no quotes...
        #a[$i]='"'"${1/#:/$user@$host:}"'"'
        a[$i]="${1/#:/$user@$host:}"
        i=$((i+1)); shift
      done

      scp ${a[*]}
      ;;
    * )
      echo "unknow command: $name"
      exit 1
      ;;
  esac
fi

# vim:ft=sh
