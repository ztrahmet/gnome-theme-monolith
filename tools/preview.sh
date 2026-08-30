#!/usr/bin/env bash
# Monolith — render theme previews from the compiled palette.
#
# Every colour is read out of build/css, and the folder icons are the ones the
# theme actually ships, so a preview cannot drift from what it claims to show.
# Deterministic: no display, no compositor, no screenshots.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
css="$root/build/css"
icons="$root/src/icons/scalable"
out="$root/docs/previews"

command -v magick >/dev/null || { echo "error: ImageMagick (magick) not found" >&2; exit 1; }
[ -d "$css" ] || { echo "error: build/css missing, run tools/build.sh" >&2; exit 1; }
mkdir -p "$out"

# GTK 4 custom property, e.g. tok classic-dark accent-bg-color
tok() { sed -n "s/.*--$2: \([^;]*\);.*/\1/p" "$css/gtk4-$1.css" | head -1; }

# A declaration from the compiled Shell sheet, e.g. shelltok black .popup-menu background-color
shelltok() {
  sed -n "/^$2/,/}/p" "$css/shell-$1.css" | sed -n "s/.*$3: \([^;}]*\).*/\1/p" \
    | head -1 | tr -d ' '
}

# Inline an icon, renaming its ids so several copies can coexist.
inline() {  # file prefix x y size
  local f="$1" p="$2" x="$3" y="$4" sz="$5" sc
  sc=$(awk -v s="$sz" 'BEGIN{printf "%.6f", s/128}')
  printf '<g transform="translate(%s,%s) scale(%s)">' "$x" "$y" "$sc"
  sed -e '/<?xml/d' -e 's|<svg[^>]*>||' -e 's|</svg>||' \
      -e "s|id=\"\([a-zA-Z0-9]*\)\"|id=\"$p\1\"|g" \
      -e "s|url(#\([a-zA-Z0-9]*\))|url(#$p\1)|g" \
      -e "s|xlink:href=\"#\([a-zA-Z0-9]*\)\"|xlink:href=\"#$p\1\"|g" "$f"
  printf '</g>'
}

render() {  # variant title basename
  local v="$1" title="$2" name="$3" svg="$out/$3.svg"
  local win fg side sidefg view acc accfg bop edge
  local spanel stoggle sfg

  win="$(tok "$v" window-bg-color)";    fg="$(tok "$v" window-fg-color)"
  side="$(tok "$v" sidebar-bg-color)";  sidefg="$(tok "$v" sidebar-fg-color)"
  view="$(tok "$v" view-bg-color)"
  acc="$(tok "$v" accent-bg-color)";    accfg="$(tok "$v" accent-fg-color)"
  bop="$(tok "$v" border-opacity)"
  spanel="$(shelltok "$v" '\.popup-menu' background-color)"
  stoggle="$(shelltok "$v" '\.quick-toggle' background-color)"
  sfg="$(shelltok "$v" '\.quick-toggle' color)"

  for c in win fg side sidefg view acc accfg bop spanel stoggle sfg; do
    [ -n "${!c}" ] || { echo "error: $v: could not read $c" >&2; exit 1; }
  done
  edge="0.${bop%\%}"

  {
  cat <<EOF
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
     width="1060" height="470" viewBox="0 0 1060 470">
  <defs><clipPath id="win"><rect width="700" height="470" rx="14"/></clipPath></defs>
  <g clip-path="url(#win)">
    <rect width="700" height="470" fill="$view"/>
    <rect width="185" height="470" fill="$side"/>

    <!-- sidebar header: search, title, menu -->
    <circle cx="24" cy="28" r="5" fill="none" stroke="$sidefg" stroke-width="1.6" opacity=".8"/>
    <line x1="28" y1="32" x2="31" y2="35" stroke="$sidefg" stroke-width="1.6" opacity=".8"/>
    <rect x="73" y="24" width="38" height="9" rx="4.5" fill="$sidefg" opacity=".8"/>
    <g stroke="$sidefg" stroke-width="1.6" opacity=".8">
      <line x1="152" y1="24" x2="166" y2="24"/>
      <line x1="152" y1="28" x2="166" y2="28"/>
      <line x1="152" y1="32" x2="166" y2="32"/>
    </g>

    <!-- selected row is the accent at low alpha, as libadwaita mixes it -->
    <rect x="8" y="196" width="169" height="32" rx="8" fill="$acc" opacity=".25"/>
    <g fill="$sidefg" opacity=".72">
      <rect x="22" y="71"  width="34" height="9" rx="4.5"/>
      <rect x="22" y="105" width="44" height="9" rx="4.5"/>
      <rect x="22" y="139" width="48" height="9" rx="4.5"/>
      <rect x="22" y="173" width="32" height="9" rx="4.5"/>
      <rect x="22" y="242" width="66" height="9" rx="4.5"/>
      <rect x="22" y="276" width="70" height="9" rx="4.5"/>
      <rect x="22" y="310" width="50" height="9" rx="4.5"/>
      <rect x="22" y="344" width="38" height="9" rx="4.5"/>
      <rect x="22" y="387" width="82" height="9" rx="4.5"/>
    </g>
    <rect x="22" y="208" width="52" height="9" rx="4.5" fill="$sidefg"/>
    <line x1="14" y1="194" x2="171" y2="194" stroke="$sidefg" stroke-opacity=".14"/>
    <line x1="14" y1="373" x2="171" y2="373" stroke="$sidefg" stroke-opacity=".14"/>

    <!-- content header: back/forward, centred path bar, actions, close -->
    <g stroke="$fg" stroke-width="1.8" fill="none" stroke-linecap="round" opacity=".8">
      <polyline points="209,24 203,29 209,34"/>
      <polyline points="231,24 237,29 231,34"/>
    </g>
    <rect x="258" y="14" width="300" height="30" rx="9" fill="$fg" opacity=".10"/>
    <rect x="278" y="25" width="34" height="9" rx="4.5" fill="$fg" opacity=".5"/>
    <rect x="320" y="25" width="4"  height="9" rx="2"   fill="$fg" opacity=".3"/>
    <rect x="332" y="25" width="48" height="9" rx="4.5" fill="$fg" opacity=".9"/>
    <g fill="$fg" opacity=".55">
      <circle cx="540" cy="23" r="1.6"/><circle cx="540" cy="29" r="1.6"/><circle cx="540" cy="35" r="1.6"/>
    </g>
    <rect x="578" y="18" width="22" height="22" rx="6" fill="$fg" opacity=".14"/>
    <rect x="610" y="18" width="22" height="22" rx="6" fill="$fg" opacity=".14"/>
    <circle cx="662" cy="29" r="13" fill="$fg" opacity=".14"/>
    <g stroke="$fg" stroke-width="1.7" stroke-linecap="round" opacity=".8">
      <line x1="658" y1="25" x2="666" y2="33"/><line x1="666" y1="25" x2="658" y2="33"/>
    </g>
EOF

  # folder grid: the icons the theme actually ships
  xs=(225 340 455 570); widths=(46 62 50 36)
  files=(places/folder places/folder-documents places/folder-pictures places/folder-music)
  for i in 0 1 2 3; do
    inline "$icons/${files[$i]}.svg" "g${i}_" "${xs[$i]}" 92 72
    printf '<rect x="%s" y="186" width="%s" height="9" rx="4.5" fill="%s" opacity=".7"/>' \
           "$(( ${xs[$i]} + 36 - ${widths[$i]} / 2 ))" "${widths[$i]}" "$fg"
  done

  cat <<EOF
    <line x1="185" y1="0" x2="185" y2="470" stroke="$fg" stroke-opacity="$edge"/>
  </g>
  <rect x=".5" y=".5" width="699" height="469" rx="14" fill="none"
        stroke="$fg" stroke-opacity="$edge"/>

  <!-- GNOME Shell quick settings -->
  <rect x="730" y="18" width="310" height="334" rx="22" fill="$spanel"
        stroke="$sfg" stroke-opacity=".12"/>

  <rect x="750" y="42" width="82" height="32" rx="16" fill="$stoggle"/>
  <rect x="763" y="52" width="9" height="12" rx="2" fill="$sfg" opacity=".8"/>
  <rect x="780" y="54" width="26" height="9" rx="4.5" fill="$sfg" opacity=".8"/>
  <g fill="$stoggle">
    <circle cx="888" cy="58" r="16"/><circle cx="926" cy="58" r="16"/>
    <circle cx="964" cy="58" r="16"/><circle cx="1002" cy="58" r="16"/>
  </g>
  <g fill="$sfg" opacity=".8">
    <circle cx="888" cy="58" r="6"/><circle cx="926" cy="58" r="6"/>
    <circle cx="964" cy="58" r="6"/><circle cx="1002" cy="58" r="6"/>
  </g>

  <circle cx="760" cy="103" r="7" fill="$sfg" opacity=".8"/>
  <rect x="782" y="99" width="238" height="9" rx="4.5" fill="$sfg" opacity=".22"/>
  <rect x="782" y="99" width="112" height="9" rx="4.5" fill="$acc"/>
  <circle cx="894" cy="103.5" r="10" fill="$acc"/>
  <circle cx="760" cy="140" r="7" fill="$sfg" opacity=".8"/>
  <rect x="782" y="136" width="238" height="9" rx="4.5" fill="$sfg" opacity=".22"/>
  <rect x="782" y="136" width="86" height="9" rx="4.5" fill="$acc"/>
  <circle cx="868" cy="140.5" r="10" fill="$acc"/>

EOF

  # toggle pills: icon and label inline, active ones carry the accent
  tiles=("750 176 1 26" "891 176 0 50" "750 232 0 58" "891 232 0 52"
         "750 288 1 48" "891 288 0 62")
  for tile in "${tiles[@]}"; do
    set -- $tile; tx="$1"; ty="$2"; on="$3"; lw="$4"
    if [ "$on" = 1 ]; then bg="$acc"; ink="$accfg"; op="1"; else bg="$stoggle"; ink="$sfg"; op=".8"; fi
    printf '<rect x="%s" y="%s" width="129" height="44" rx="22" fill="%s"/>' "$tx" "$ty" "$bg"
    printf '<circle cx="%s" cy="%s" r="8" fill="%s" opacity="%s"/>' \
           "$((tx + 24))" "$((ty + 22))" "$ink" "$op"
    printf '<rect x="%s" y="%s" width="%s" height="9" rx="4.5" fill="%s" opacity="%s"/>' \
           "$((tx + 42))" "$((ty + 18))" "$lw" "$ink" "$op"
  done
  printf '</svg>\n'
  } > "$svg"

  magick -background none "$svg" -strip "$out/$name.png"
  rm -f "$svg"
  printf '  %-26s %s\n' "$name.png" "$(du -h "$out/$name.png" | cut -f1)"
}

echo "rendering previews:"
render classic-light "Monolith Classic"      monolith-classic
render classic-dark  "Monolith Classic Dark" monolith-classic-dark
render black         "Monolith Black"        monolith-black
# Monolith-Black-dark is the same theme under a second name, for tools that
# blindly append -dark. Same palette in, so the same image out.
render black         "Monolith Black Dark"   monolith-black-dark
