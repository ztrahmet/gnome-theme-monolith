#!/usr/bin/env bash
# Monolith — generate GtkSourceView style schemes from the upstream Adwaita ones.
#
# Only the neutral ramp and the editor surfaces are replaced. Syntax colours are
# left exactly as upstream ships them, the same way status colours stay native.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vendor="$root/vendor/gtksourceview"
css="$root/build/css"
out="$root/build/schemes"

[ -d "$vendor" ] || { echo "error: vendor/gtksourceview missing, run tools/fetch-upstream.sh" >&2; exit 1; }
[ -d "$css" ]    || { echo "error: build/css missing, run tools/build.sh" >&2; exit 1; }

mkdir -p "$out"

# The ramp is identical across variants, so any compiled sheet will do.
ramp() { sed -n "s/.*@define-color $2 \(#[0-9a-f]\{6\}\);.*/\1/p" "$css/gtk4-$1.css" | head -1; }
view() { sed -n "s/.*--view-bg-color: \(#[0-9a-f]\{6\}\);.*/\1/p" "$css/gtk4-$1.css" | head -1; }

L2="$(ramp classic-light light_2)"; L3="$(ramp classic-light light_3)"
L4="$(ramp classic-light light_4)"; L5="$(ramp classic-light light_5)"
DARK_BG="$(view classic-dark)";      DARK_ALT="$(ramp classic-dark dark_4)"
BLACK_BG="$(view black)";            BLACK_ALT="$(ramp black dark_4)"

# An unreadable value would otherwise be substituted in as value="", which is
# still well-formed XML and would pass unnoticed.
for _v in L2 L3 L4 L5 DARK_BG DARK_ALT BLACK_BG BLACK_ALT; do
  [ -n "${!_v}" ] || { echo "error: could not read $_v from build/css" >&2; exit 1; }
done

# The light scheme still ships GNOME's legacy purple-leaning dark ramp; the dark
# scheme already carries the neutral one, so take it from there.
neutral() { sed -n "s|.*name=\"$1\"[[:space:]]*value=\"\([^\"]*\)\".*|\1|p" "$vendor/Adwaita-dark.xml" | head -1; }

# Substitute a colour by name, tolerating upstream's column alignment.
recolor() { printf 's|\\(name="%s"[[:space:]]*value="\\)[^"]*"|\\1%s"|;' "$1" "$2"; }

generate() { # base id name counterpart-prop old-counterpart counterpart [bg alt]
  local base="$1" id="$2" name="$3" cprop="$4" cold="$5" cnew="$6" bg="${7:-}" alt="${8:-}"
  local script=""
  script+="s|<style-scheme id=\"[^\"]*\" _name=\"[^\"]*\"|<style-scheme id=\"$id\" _name=\"$name\"|;"
  script+="s|<property name=\"$cprop\">$cold</property>|<property name=\"$cprop\">$cnew</property>|;"
  script+="s|<_description>[^<]*</_description>|<_description>Adwaita with Monolith's neutral surfaces</_description>|;"
  # LGPL-2.1 asks that modified files say so.
  script+="s|\\(Copyright 2020 Christian Hergert.*\\)|\\1\\n\\n  Modified for the Monolith theme: neutral greys and editor surfaces.|;"
  script+="$(recolor light_3 "$L2")$(recolor light_4 "$L3")$(recolor light_5 "$L4")"
  script+="$(recolor light_6 '#b0b0b0')$(recolor light_7 "$L5")"
  local n; for n in 1 2 3 4 5; do script+="$(recolor "dark_$n" "$(neutral "dark_$n")")"; done
  [ -n "$bg" ]  && script+="$(recolor libadwaita-dark "$bg")"
  [ -n "$alt" ] && script+="$(recolor libadwaita-dark-alt "$alt")"
  sed -e "$script" "$vendor/$base" > "$out/$id.xml"
  chmod 644 "$out/$id.xml"
  echo "  $id.xml"
}

echo "generating style schemes:"
generate Adwaita.xml      Monolith       "Monolith"       dark-variant  Adwaita-dark Monolith-dark
generate Adwaita-dark.xml Monolith-dark  "Monolith Dark"  light-variant Adwaita      Monolith \
  "$DARK_BG" "$DARK_ALT"
# Black has no light form, so it stays itself when the desktop turns light.
generate Adwaita-dark.xml Monolith-black "Monolith Black" light-variant Adwaita      Monolith-black \
  "$BLACK_BG" "$BLACK_ALT"
