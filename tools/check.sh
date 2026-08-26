#!/usr/bin/env bash
# Monolith — QA and validation check suite.
# Verifies script syntax, theme completeness, build markers, native status colors, and GTK 3 layering.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
themes="$root/build/themes"
vendor="$root/vendor"

RED=$'\e[31m'; GRN=$'\e[32m'; R=$'\e[0m'
failed=0

fail() { printf '  %s✗%s %s\n' "$RED" "$R" "$1" >&2; failed=1; }
ok()   { printf '  %s✓%s %s\n' "$GRN" "$R" "$1"; }

# 1. Verify syntax of all shell scripts (bash -n)
for script in "$root/install.sh" "$root/tools"/*.sh; do
  [ -f "$script" ] || continue
  if bash -n "$script" 2>&1; then
    ok "$(basename "$script") parses"
  else
    fail "$(basename "$script") syntax error"
  fi
done

# Ensure build artifacts exist
if [ ! -d "$themes" ] || [ -z "$(ls -A "$themes" 2>/dev/null)" ]; then
  "$root/tools/build.sh" >/dev/null
fi

# 2. Verify all 4 expected theme packages
EXPECTED_THEMES="Monolith-Classic Monolith-Classic-dark Monolith-Black Monolith-Black-dark"
REQUIRED_FILES=(
  "index.theme"
  "LICENSE.adw-gtk3"
  "gtk-3.0/gtk.css"
  "gtk-3.0/gtk-dark.css"
  "gtk-3.0/assets"
  "gtk-4.0/gtk.css"
  "gtk-4.0/gtk-dark.css"
  "gtk-4.0/libadwaita.css"
  "gnome-shell/gnome-shell.css"
)

for t in $EXPECTED_THEMES; do
  theme_dir="$themes/$t"
  if [ ! -d "$theme_dir" ]; then
    fail "$t directory missing"
    continue
  fi

  missing=0
  for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -e "$theme_dir/$f" ]; then
      fail "$t missing $f"
      missing=1
    fi
  done
  [ $missing -eq 0 ] && ok "$t is complete"

  # Verify scheme declared in index.theme
  scheme="$(sed -n 's/^X-Monolith-Scheme=//p' "$theme_dir/index.theme" | tr -d ' ')"
  if [ "$scheme" != "light" ] && [ "$scheme" != "dark" ]; then
    fail "$t has invalid X-Monolith-Scheme='$scheme' (expected light or dark)"
  fi
done

# 3. Check for leftover build markers
markers_clean=1
for css in "$themes"/*/gtk-*.0/*.css "$themes"/*/gnome-shell/*.css; do
  [ -f "$css" ] || continue
  rel="${css#$themes/}"

  # Ensure no unstripped marker comments remain
  if grep -qE "pitch-accent" "$css"; then
    fail "$rel contains unstripped build markers"
    markers_clean=0
  fi

  # Shell runtime keywords must not survive in compiled Shell CSS
  if [[ "$css" == *"/gnome-shell/"* ]] && grep -qE -- "-st-accent-(color|fg-color)" "$css"; then
    fail "$rel contains unstripped -st-accent keyword"
    markers_clean=0
  fi
done
[ "$markers_clean" -eq 1 ] && ok "all stylesheets checked for build markers"

# 3b. Status colors stay native by omission. Only our own output is checked;
# the bundled adw-gtk3 base defines its own.
emitted=0 status_native=1
for css in "$root/build/css"/gtk4-*.css "$root/build/css"/gtk3-overrides-*.css; do
  [ -f "$css" ] || continue
  emitted=$((emitted + 1))
  if grep -qE "@define-color (error|warning|success|destructive)_" "$css"; then
    fail "$(basename "$css") defines a status color; these must stay native"
    status_native=0
  fi
done
if [ "$emitted" -eq 0 ]; then
  fail "no emitted stylesheets in build/css to check for status colors"
elif [ "$status_native" -eq 1 ]; then
  ok "status colors left native in $emitted emitted stylesheets"
fi

# 4. Each GTK 3 stylesheet must layer our overrides after the right adw-gtk3
# base — GTK 3 resolves named colors last-wins.
check_layering() {  # file adw-dir label
  local file="$1" adw="$2" label="$3" decl base_line ours_line
  decl="$(grep -m1 -o '@define-color window_bg_color [^;]*;' \
          "$vendor/adw-gtk3/$adw/gtk-3.0/gtk.css")" || decl=""
  if [ -z "$decl" ]; then
    fail "$label: cannot read window_bg_color from vendor/adw-gtk3/$adw"
    return
  fi

  base_line="$(grep -n -F -- "$decl" "$file" | head -1 | cut -d: -f1)" || base_line=""
  ours_line="$(grep -n -- '@define-color window_bg_color' "$file" | tail -1 | cut -d: -f1)" || ours_line=""

  if [ -z "$base_line" ]; then
    fail "$label does not bundle the $adw base"
  elif [ -z "$ours_line" ] || [ "$ours_line" -le "$base_line" ]; then
    fail "$label: our overrides do not follow the $adw base (base:$base_line ours:${ours_line:-none})"
  else
    ok "$label layers over $adw"
  fi
}

for t in $EXPECTED_THEMES; do
  scheme="$(sed -n 's/^X-Monolith-Scheme=//p' "$themes/$t/index.theme" | tr -d ' ')"
  if [ "$scheme" = "light" ]; then adw=adw-gtk3; else adw=adw-gtk3-dark; fi

  if [ -f "$themes/$t/gtk-3.0/gtk.css" ]; then
    check_layering "$themes/$t/gtk-3.0/gtk.css" "$adw" "$t gtk.css"
  fi
  # gtk-dark.css always carries the dark base
  if [ -f "$themes/$t/gtk-3.0/gtk-dark.css" ]; then
    check_layering "$themes/$t/gtk-3.0/gtk-dark.css" adw-gtk3-dark "$t gtk-dark.css"
  fi
done

# 5. Editor style schemes: present, well-formed, and free of tinted greys.
schemes="$root/build/schemes"
for id in Monolith Monolith-dark Monolith-black; do
  f="$schemes/$id.xml"
  if [ ! -f "$f" ]; then
    fail "style scheme $id.xml missing"
  elif ! grep -q "<style-scheme id=\"$id\"" "$f"; then
    fail "$id.xml does not declare id=\"$id\""
  elif grep -q 'value=""' "$f"; then
    fail "$id.xml has an empty colour value"
  elif grep -qE 'value="#(1d1d20|242428|F6F5F4|DEDDDA|C0BFBC|B0AFAC|9A9996|504E55|3D3846|241F31)"' "$f"; then
    fail "$id.xml still carries an upstream tinted grey"
  else
    ok "$id.xml is neutral"
  fi
done

# 6. The theme's defining rule: what sits on an accent matches the window behind it.
for v in classic-light classic-dark black; do
  f="$root/build/css/gtk4-$v.css"
  [ -f "$f" ] || continue
  afg="$(sed -n 's/.*--accent-fg-color: \([^;]*\);.*/\1/p' "$f" | head -1)"
  wbg="$(sed -n 's/.*--window-bg-color: \([^;]*\);.*/\1/p' "$f" | head -1)"
  if [ -n "$afg" ] && [ "$afg" = "$wbg" ]; then
    ok "$v accent foreground matches the window background"
  else
    fail "$v accent-fg ($afg) does not match window-bg ($wbg)"
  fi
done

if [ $failed -eq 0 ]; then
  echo "all checks passed"
  exit 0
else
  echo "QA check failed" >&2
  exit 1
fi
