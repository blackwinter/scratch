#! /bin/bash

set -e

solr_version="$1"
solr_user_id="solr"
solr_service="solr${2:+-$2}"
solr_dirname="solr-$solr_version"
solr_archive="$solr_dirname.tgz"
solr_var_dir="/var/opt/solr"
solr_ext_dir="/opt"
solr_opt_dir="$solr_ext_dir/$solr_dirname"
solr_tmp_dir="$(mktemp -d)"

function die() {
  [ -d "$solr_tmp_dir" ] && cd && rm -r "$solr_tmp_dir"
  [ -n "$1" ] && echo "$1" >&2
  exit "${2:-1}"
}

[ -z "$solr_version" ] && die "Usage: $0 <solr-version> [<solr-service>]"

function fetch() {
  local path="lucene/solr/$solr_version/$solr_archive"

  local url="$(curl -s "http://apache.org/dyn/closer.lua/$path" \
    | grep -om1 '<strong>.*</strong>' | sed 's/[^>]*>//; s/<.*//')"

  curl -O "$url" || die "Download failed: $url"
}

cd "$solr_tmp_dir"

if [ -e "/etc/init.d/$solr_service" ]; then
  [ -d "$solr_opt_dir" ] && die "Already installed $solr_service: $solr_opt_dir"

  fetch

  sudo tar xf "$solr_archive" -C "$solr_ext_dir"
  sudo chown -R "$solr_user_id:" "$solr_opt_dir"

  sudo ln -nfs "$solr_opt_dir" "$solr_ext_dir/$solr_service"

  sudo systemctl restart "$solr_service"
else
  fetch

  tar xf "$solr_archive" \
    "$solr_dirname/bin/install_solr_service.sh" --strip-components=2

  id -u "$solr_user_id" &> /dev/null || sudo adduser \
    --system --group --disabled-password --shell /bin/bash \
    --no-create-home --home "$solr_var_dir" "$solr_user_id"

  sudo ./install_solr_service.sh \
    "$solr_archive" -d "$solr_var_dir/${solr_service#*-}" \
    -i "$solr_ext_dir" -s "$solr_service" -u "$solr_user_id"
fi

die "" 0

# /etc/systemd/system/solr.service
# - http://serverfault.com/a/690179
# - https://confluence.t5.fi/display/~stefan.roos/2015/04/01/Creating+systemd+unit+%28service%29+for+Apache+Solr
