#!/usr/bin/env bash
# Monolith — compile stylesheets and assemble complete theme trees.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$root/src"
vendor="$root/vendor"
build="$root/build"
css="$build/css"
themes="$build/themes"

command -v sassc >/dev/null || { echo "error: sassc not found" >&2; exit 1; }
[ -d "$vendor/gnome-shell" ] || { echo "error: vendor/ missing, run tools/fetch-upstream.sh" >&2; exit 1; }

rm -rf "$build"
mkdir -p "$css" "$themes"

VARIANTS="classic-light classic-dark black"

scheme_of() { case "$1" in *-light) echo light ;; *) echo dark ;; esac; }
adw_base()  { case "$(scheme_of "$1")" in light) echo adw-gtk3 ;; *) echo adw-gtk3-dark ;; esac; }

echo "compiling:"
for v in $VARIANTS; do
  # GTK 4 — bare output per variant
  sassc -I "$src" "$src/gtk-4.0/$v.scss" "$css/gtk4-$v.css"

  # GTK 3 — bundled adw-gtk3 + overrides
  adw="$(adw_base "$v")"
  sassc -I "$src" "$src/gtk-3.0/$v.scss" "$css/gtk3-overrides-$v.css"
  cat "$vendor/adw-gtk3/$adw/gtk-3.0/gtk.css" "$css/gtk3-overrides-$v.css" \
    > "$css/gtk3-$v.css"

  # Shell
  out="$css/shell-$v.css"
  sassc -I "$src" -I "$vendor" "$src/gnome-shell/$v.scss" "$out"

  # Accent substitution: replace St runtime keywords with literal monochrome accent
  marker="$(sed -n 's|.*pitch-accent \(#[0-9a-fA-F]\{6\}\) \(#[0-9a-fA-F]\{6\}\).*|\1 \2|p' "$out" | head -1)"
  if [ -n "$marker" ]; then
    read -r accent_bg accent_fg <<<"$marker"
    sed -i -e "s|-st-accent-fg-color|$accent_fg|g" \
           -e "s|-st-accent-color|$accent_bg|g" \
           -e '/pitch-accent/d' "$out"
  fi

  echo "  $v"
done

# ── Assemble theme trees ─────────────────────────────────────────────────
assemble() {
  local name="$1" v="$2" comment="$3" pair="${4:-}" dest="$themes/$1"
  local scheme; scheme="$(scheme_of "$v")"
  mkdir -p "$dest/gtk-3.0" "$dest/gtk-4.0" "$dest/gnome-shell"

  # GTK 3
  local dark_v="${pair:-$v}"
  [ "$(scheme_of "$dark_v")" = "light" ] && dark_v="$v"
  install -m644 "$css/gtk3-$v.css" "$dest/gtk-3.0/gtk.css"
  install -m644 "$css/gtk3-$dark_v.css" "$dest/gtk-3.0/gtk-dark.css"
  local adw; adw="$(adw_base "$v")"
  cp -r "$vendor/adw-gtk3/$adw/gtk-3.0/assets" "$dest/gtk-3.0/assets"
  install -m644 "$vendor/adw-gtk3/LICENSE" "$dest/LICENSE.adw-gtk3"

  # GTK 4 theme-tree — prepend Default base import
  { printf '@import url("resource:///org/gtk/libgtk/theme/Default/Default-%s.css");\n' "$(scheme_of "$v")"
    cat "$css/gtk4-$v.css"
  } > "$dest/gtk-4.0/gtk.css"
  chmod 644 "$dest/gtk-4.0/gtk.css"

  # gtk-dark.css — always the dark variant
  { printf '@import url("resource:///org/gtk/libgtk/theme/Default/Default-dark.css");\n'
    cat "$css/gtk4-$dark_v.css"
  } > "$dest/gtk-4.0/gtk-dark.css"
  chmod 644 "$dest/gtk-4.0/gtk-dark.css"

  # Libadwaita overlay — our colours, with the counterpart behind a media query
  local counter_scheme
  [ "$scheme" = "light" ] && counter_scheme="dark" || counter_scheme="light"
  { cat "$css/gtk4-$v.css"
    if [ -n "$pair" ]; then
      printf '\n@media (prefers-color-scheme: %s) {\n' "$counter_scheme"
      cat "$css/gtk4-$pair.css"
      printf '}\n'
    fi
  } > "$dest/gtk-4.0/libadwaita.css"
  chmod 644 "$dest/gtk-4.0/libadwaita.css"

  # Shell CSS. Asset references resolve against GNOME's own built-in resources,
  # so nothing else needs shipping alongside it.
  install -m644 "$css/shell-$v.css" "$dest/gnome-shell/gnome-shell.css"

  # index.theme
  sed -e "s|@NAME@|$name|g" -e "s|@COMMENT@|$comment|g" -e "s|@SCHEME@|$scheme|g" \
    "$src/index.theme.in" > "$dest/index.theme"
  chmod 644 "$dest/index.theme"
  echo "  $name"
}

echo "assembling themes:"
assemble Monolith-Classic      classic-light "Monolith Classic, light" classic-dark
assemble Monolith-Classic-dark classic-dark  "Monolith Classic, dark"  classic-light
assemble Monolith-Black        black         "Monolith Black"
assemble Monolith-Black-dark   black         "Monolith Black"

"$root/tools/schemes.sh"

echo "themes assembled in build/themes/"
