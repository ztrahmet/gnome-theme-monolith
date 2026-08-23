#!/usr/bin/env bash
# Monolith — fetch pinned upstream Adwaita and GNOME Shell sources into vendor/.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vendor="$root/vendor"
api="https://gitlab.gnome.org/api/v4/projects"

fetch() {
  local project="$1" tag="$2" path="$3" dest="$4"
  local encoded_project encoded_path tmp
  encoded_project="${project//\//%2F}"
  encoded_path="${path//\//%2F}"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  echo "  fetching ${project} ${tag}:${path}"
  curl -sSLf -o "$tmp/src.tar.gz" \
    "$api/${encoded_project}/repository/archive.tar.gz?sha=${tag}&path=${encoded_path}"
  tar xzf "$tmp/src.tar.gz" -C "$tmp" --strip-components=1

  rm -rf "$dest"
  mkdir -p "$(dirname "$dest")"
  cp -r "$tmp/$path" "$dest"
}

# adw-gtk3 is bundled rather than imported: GTK 3 has no resource path for it,
# so an @import would need an absolute path resolved on the build machine, and
# GTK 3 discards the whole stylesheet when an @import fails. Vendoring it keeps
# the shipped theme self-contained. LGPL-2.1-only; its LICENSE ships with us.
fetch_adw_gtk3() {
  local tag="v6.5" tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  echo "  fetching adw-gtk3 $tag"
  curl -sSLf -o "$tmp/adw.tar.xz" \
    "https://github.com/lassekongo83/adw-gtk3/releases/download/$tag/adw-gtk3$tag.tar.xz"
  curl -sSLf -o "$tmp/LICENSE" \
    "https://raw.githubusercontent.com/lassekongo83/adw-gtk3/$tag/LICENSE"

  rm -rf "$vendor/adw-gtk3"
  mkdir -p "$vendor/adw-gtk3"
  tar xf "$tmp/adw.tar.xz" -C "$vendor/adw-gtk3"
  cp "$tmp/LICENSE" "$vendor/adw-gtk3/LICENSE"
}

mkdir -p "$vendor"
fetch GNOME/libadwaita  1.9.3 src/stylesheet "$vendor/libadwaita"
fetch GNOME/gnome-shell 50.4  data/theme     "$vendor/gnome-shell"
fetch GNOME/gtksourceview 5.20.0 data/styles "$vendor/gtksourceview"

fetch_adw_gtk3

echo "upstream sources in vendor/"
