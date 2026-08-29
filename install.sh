#!/usr/bin/env bash
# Monolith — installer and theme manager.
#
# One file, two roles, chosen by the name it is invoked under.
#
#   curl -fsSL https://raw.githubusercontent.com/ztrahmet/gnome-theme-monolith/main/install.sh | bash
#     Installs, or updates an existing install. Never prompts — a menu piped
#     from curl has no dependable way to read a keypress. It also installs the
#     manager below.
#
#   monolith-theme
#     The manager, in ~/.local/bin. Choose a theme, manage Flatpak access,
#     update, or uninstall.
#
# Flags work in either role:
#   --install [Theme]   install or update, then select a theme
#   --uninstall         remove everything and revert
#   --flatpak           grant Flatpak apps access
#   --no-flatpak        revoke it
#   --schemes [Scheme]  apply the Monolith editor scheme to GtkSourceView apps
#   --no-schemes        return those apps to their own default
#   --status            show what is currently active
#
# Environment:
#   MONOLITH_VERSION    install a specific tag instead of the latest
#   MONOLITH_THEME      variant to select, e.g. Monolith-Black
#   MONOLITH_ARCHIVE    install from a local archive instead of downloading
#   MONOLITH_FLATPAK    1 to grant Flatpak access, 0 to skip
set -uo pipefail

REPO="ztrahmet/gnome-theme-monolith"
RAW_URL="https://raw.githubusercontent.com/$REPO/main/install.sh"
dest="${XDG_DATA_HOME:-$HOME/.local/share}/themes"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
overlay="$config/gtk-4.0/gtk.css"
ICONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
SCHEMES_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gtksourceview-5/styles"

# Apps exposing a GtkSourceView scheme setting, as schema:key. A schema that is
# not installed is skipped, so listing an app you do not have costs nothing.
# Matching on key name alone would catch org.gnome.desktop.interface color-scheme,
# which is the desktop light/dark preference and must never be touched.
SCHEME_APPS="
org.gnome.TextEditor:style-scheme
org.gnome.builder.editor:style-scheme-name
org.gnome.gedit.preferences.editor:scheme
org.gnome.meld:style-scheme
org.gnome.gnome-latex.preferences.editor:scheme
org.gnome.gitg.preferences.view.files:style-scheme
org.gnome.Devhelp.state.main.content:style-scheme
org.gnome.sourceview.preferences:style-scheme
"

# ~/bin is honoured when it already exists, since a user who made it usually
# has it on PATH; otherwise the XDG location.
if [ -d "$HOME/bin" ] && [ ! -d "$HOME/.local/bin" ]; then bindir="$HOME/bin"
else bindir="$HOME/.local/bin"; fi
manager="$bindir/monolith-theme"

# Piped from curl there is no script file, so BASH_SOURCE is unset; fall back to
# the working directory, where a checkout's build/themes may still be found.
self="${BASH_SOURCE[0]:-}"
here="$(cd "$(dirname "${self:-$PWD}")" 2>/dev/null && pwd || echo "$PWD")"

# Invoked as monolith-theme it manages an install; anything else installs one.
case "$(basename "${0:-bash}")" in
  monolith-theme) ROLE=manager ;;
  *)              ROLE=bootstrap ;;
esac

assume_yes=0
work=""
themes_src=""
manager_ok=0

# ---------------------------------------------------------------- appearance
if [ -t 1 ]; then
  B=$'\e[1m'; D=$'\e[2m'; R=$'\e[0m'; INV=$'\e[7m'
  GRN=$'\e[32m'; YEL=$'\e[33m'; RED=$'\e[31m'; CYN=$'\e[36m'
else
  B=""; D=""; R=""; INV=""; GRN=""; YEL=""; RED=""; CYN=""
fi
hide() { [ -t 1 ] && printf '\e[?25l'; }
show() { [ -t 1 ] && printf '\e[?25h'; }

# Prompts read from the controlling terminal, which survives even when stdin is
# something else. With no terminal at all they fall back to defaults.
TTY=""
if [ -t 0 ]; then TTY="/dev/stdin"
elif [ -r /dev/tty ] && [ -t 1 ]; then TTY="/dev/tty"
fi

# `read -rsn1` turns echo off for the duration of the read. Interrupted
# mid-read, the terminal keeps those settings and looks dead, so the original
# state is saved up front and restored unconditionally on exit.
TTY_STATE=""
[ -n "$TTY" ] && TTY_STATE="$(stty -g <"$TTY" 2>/dev/null || true)"
cleanup() {
  show
  [ -n "$TTY_STATE" ] && [ -n "$TTY" ] && stty "$TTY_STATE" <"$TTY" 2>/dev/null || true
  [ -n "$work" ] && rm -rf "$work"
  rm -rf "${dest:?}"/.Monolith-*.incoming.$$ 2>/dev/null
  return 0
}
on_interrupt() {
  cleanup
  printf '\n  %sCancelled — nothing further was changed.%s\n' "$D" "$R"
  exit 130
}
trap on_interrupt INT TERM
trap cleanup EXIT

ok()   { printf '  %s✓%s %s\n' "$GRN" "$R" "$1"; }
warn() { printf '  %s!%s %s\n' "$YEL" "$R" "$1"; }
err()  { printf '  %s✗%s %s\n' "$RED" "$R" "$1"; }
die()  { err "$1"; exit 1; }
step() { printf '\n%s%s%s\n' "$B" "$1" "$R"; }

# ------------------------------------------------------------------- widgets
CHOICE=""
menu() {
  local prompt="$1"; shift
  local -a items=("$@")
  local n=${#items[@]} cur=0 i label desc key

  if [ -z "$TTY" ]; then CHOICE="${items[0]%%|*}"; return 0; fi

  printf '\n%s%s%s\n' "$B" "$prompt" "$R"
  hide
  while true; do
    for i in "${!items[@]}"; do
      label="${items[$i]%%|*}"; desc="${items[$i]#*|}"
      if [ "$i" -eq "$cur" ]; then
        printf '\e[2K  %s❯ %-18s%s %s%s%s\n' "$CYN" "$label" "$R" "$D" "$desc" "$R"
      else
        printf '\e[2K    %-18s %s%s%s\n' "$label" "$D" "$desc" "$R"
      fi
    done
    IFS= read -rsn1 key <"$TTY"
    case "$key" in
      $'\e') IFS= read -rsn2 -t 0.05 key <"$TTY"
             case "$key" in
               '[A') cur=$(( (cur - 1 + n) % n )) ;;
               '[B') cur=$(( (cur + 1) % n )) ;;
             esac ;;
      k) cur=$(( (cur - 1 + n) % n )) ;;
      j) cur=$(( (cur + 1) % n )) ;;
      "") break ;;
      q) cleanup; echo; exit 0 ;;
    esac
    printf '\e[%dA' "$n"
  done
  show
  CHOICE="${items[$cur]%%|*}"
}

confirm() {
  local q="$1" def="${2:-y}" cur key
  [ "$def" = "y" ] && cur=0 || cur=1
  # A command-line flag is itself the consent, so prompts are not re-asked.
  [ "$assume_yes" -eq 1 ] && return 0
  if [ -z "$TTY" ]; then [ "$def" = "y" ]; return $?; fi

  printf '\n%s%s%s\n' "$B" "$q" "$R"
  hide
  while true; do
    if [ "$cur" -eq 0 ]; then
      printf '\e[2K  %s  Yes  %s   %s  No  %s\n' "$INV" "$R" "$D" "$R"
    else
      printf '\e[2K  %s  Yes  %s   %s  No  %s\n' "$D" "$R" "$INV" "$R"
    fi
    IFS= read -rsn1 key <"$TTY"
    case "$key" in
      $'\e') IFS= read -rsn2 -t 0.05 key <"$TTY"
             case "$key" in '[C'|'[B') cur=1 ;; '[D'|'[A') cur=0 ;; esac ;;
      h) cur=0 ;; l) cur=1 ;;
      y|Y) cur=0; break ;;
      n|N) cur=1; break ;;
      "") break ;;
    esac
    printf '\e[1A'
  done
  show
  [ "$cur" -eq 0 ]
}

# ------------------------------------------------------------------- helpers
scheme_now() {
  [ "$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)" = "'default'" ] \
    && echo light || echo dark
}

variant_for() {
  local style="$1"
  case "$style" in
    # Already a full variant name — pass it through rather than suffixing again.
    *-dark)         echo "$style" ;;
    Monolith-Black) echo "Monolith-Black" ;;
    *) [ "$(scheme_now)" = light ] && echo "$style" || echo "$style-dark" ;;
  esac
}

installed_themes() { ls -d "$dest"/Monolith-*/ 2>/dev/null; }
is_installed()     { [ -n "$(installed_themes)" ]; }

# A theme is only usable if it is whole; a half-finished copy would apply
# cleanly and then look broken.
REQUIRED_FILES="index.theme LICENSE.adw-gtk3 gtk-3.0/gtk.css gtk-3.0/gtk-dark.css gtk-3.0/assets gtk-4.0/gtk.css gtk-4.0/gtk-dark.css gtk-4.0/libadwaita.css gnome-shell/gnome-shell.css"
incomplete_themes() {
  local tree f
  for tree in $(installed_themes); do
    for f in $REQUIRED_FILES; do
      [ -e "$tree/$f" ] || { basename "$tree"; break; }
    done
  done
}

preflight() {
  if [ "$(id -u)" -eq 0 ]; then
    err "Running as root. This installs into your own home directory —"
    printf '    %sre-run it as your normal user, without sudo.%s\n' "$D" "$R"
    exit 1
  fi
  if ! gsettings writable org.gnome.shell.extensions.user-theme name >/dev/null 2>&1; then
    warn "User Themes extension not detected — the Shell theme cannot be applied."
    printf '    %sInstall it from extensions.gnome.org, then run this again.%s\n' "$D" "$R"
  fi
  command -v gnome-shell >/dev/null || warn "GNOME Shell not found — is this a GNOME session?"
}

# Failures are reported by the caller with context, so the tool's own message is
# suppressed to avoid printing the same problem twice.
fetch() {  # url dest
  if command -v curl >/dev/null; then curl -fsSL --retry 2 -o "$2" "$1" 2>/dev/null
  else wget -qO "$2" "$1" 2>/dev/null; fi
}

# Themes come from whichever of these is available: an explicit archive, a
# directory beside the script (a checkout), or the latest published release.
resolve_source() {
  [ -n "$themes_src" ] && return 0

  local archive=""
  if [ -n "${MONOLITH_ARCHIVE:-}" ]; then
    [ -f "$MONOLITH_ARCHIVE" ] || die "MONOLITH_ARCHIVE is not a file: $MONOLITH_ARCHIVE"
    archive="$MONOLITH_ARCHIVE"
    step "Using local archive"; ok "$(basename "$archive")"
  else
    for candidate in "$here/themes" "$here/build/themes"; do
      if [ -d "$candidate" ]; then themes_src="$candidate"; ok "using themes in $candidate"; return 0; fi
    done
    command -v tar >/dev/null || die "tar is required."
    command -v curl >/dev/null || command -v wget >/dev/null || die "curl or wget is required."

    step "Fetching"
    local tag="${MONOLITH_VERSION:-}" version url
    work="${work:-$(mktemp -d)}"
    if [ -z "$tag" ]; then
      # /releases/latest omits pre-releases, so fall back to the full list and
      # take the newest entry.
      fetch "https://api.github.com/repos/$REPO/releases/latest" "$work/rel.json" \
        || fetch "https://api.github.com/repos/$REPO/releases" "$work/rel.json" \
        || die "Could not reach GitHub. Check your connection, or set MONOLITH_VERSION."
      tag="$(sed -n 's/.*"tag_name" *: *"\([^"]*\)".*/\1/p' "$work/rel.json" | head -1)"
      [ -n "$tag" ] || die "No release found for $REPO. Set MONOLITH_VERSION to pick one."
    fi
    version="${tag#v}"
    ok "release $tag"

    url="https://github.com/$REPO/releases/download/$tag/Monolith-$version.tar.xz"
    fetch "$url" "$work/monolith.tar.xz" || die "Download failed: $url"
    archive="$work/monolith.tar.xz"

    # Catches a truncated or corrupted download; not a defence against a bad
    # release, since the checksum is published in the same place.
    if fetch "https://github.com/$REPO/releases/download/$tag/SHA256SUMS" "$work/SHA256SUMS" 2>/dev/null \
       && command -v sha256sum >/dev/null; then
      local expected actual
      expected="$(awk -v f="Monolith-$version.tar.xz" '$2 == f || $2 == "*"f {print $1}' "$work/SHA256SUMS" | head -1)"
      actual="$(sha256sum "$archive" | cut -d' ' -f1)"
      [ -n "$expected" ] && [ "$expected" != "$actual" ] \
        && die "Checksum mismatch — the download is corrupt. Try again."
      [ -n "$expected" ] && ok "checksum verified"
    else
      warn "no checksum published; skipping verification"
    fi
  fi

  work="${work:-$(mktemp -d)}"
  tar -xf "$archive" -C "$work" || die "The archive could not be unpacked."
  themes_src="$(find "$work" -maxdepth 3 -type d -name themes | head -1)"
  [ -n "$themes_src" ] || die "The archive contains no themes directory."
  ok "$(find "$themes_src" -maxdepth 1 -mindepth 1 -type d | wc -l) themes ready"
}

# --------------------------------------------------------------------- actions
install_themes() {
  resolve_source || return 1
  step "Installing themes"

  local -a found=()
  for tree in "$themes_src"/*/; do
    [ -f "$tree/index.theme" ] && found+=("$tree")
  done
  [ ${#found[@]} -gt 0 ] || { err "$themes_src holds no usable themes."; return 1; }

  mkdir -p "$dest" || { err "Cannot write to $dest"; return 1; }
  rm -rf "${dest:?}"/.Monolith-*.incoming.* 2>/dev/null

  # Each theme is staged and swapped in, so a failure part-way cannot destroy a
  # working install.
  local n=0 name staging
  for tree in "${found[@]}"; do
    name="$(basename "$tree")"
    staging="$dest/.$name.incoming.$$"
    rm -rf "$staging"
    if ! cp -r "$tree" "$staging" 2>/dev/null; then
      rm -rf "$staging"; err "Could not copy $name — left the existing one alone."; return 1
    fi
    rm -rf "${dest:?}/$name"
    mv "$staging" "$dest/$name"
    n=$((n + 1))
  done
  ok "$n themes → $dest"
}

apply_theme() {
  local variant="$1"
  step "Selecting $variant"
  if [ ! -d "$dest/$variant" ]; then
    err "$variant is not installed."
    local avail
    avail="$(installed_themes | xargs -r -n1 basename | tr '\n' ' ')"
    [ -n "$avail" ] && printf '    %savailable: %s%s\n' "$D" "$avail" "$R"
    return 1
  fi

  gsettings set org.gnome.desktop.interface gtk-theme "$variant" 2>/dev/null \
    && ok "GTK 3 theme set" || warn "Could not set gtk-theme"

  if gsettings writable org.gnome.shell.extensions.user-theme name >/dev/null 2>&1; then
    gsettings set org.gnome.shell.extensions.user-theme name "$variant"
    ok "Shell theme set"
  else
    warn "Shell theme skipped — User Themes extension not installed"
  fi

  apply_icons

  local src="$dest/$variant/gtk-4.0/libadwaita.css"
  if [ -f "$src" ]; then
    mkdir -p "$config/gtk-4.0"
    if [ -e "$overlay" ] && [ ! -L "$overlay" ]; then
      warn "$overlay already exists and is not ours"
      # Only save a backup if not already backed up from before Monolith
      if [ ! -e "$overlay.before-monolith" ]; then
        if confirm "Back it up and replace it?" y; then
          mv "$overlay" "$overlay.before-monolith"
          ok "Saved original as $(basename "$overlay").before-monolith"
        else
          warn "libadwaita apps will stay unthemed"
          return 0
        fi
      else
        rm -f "$overlay"
      fi
    fi
    ln -sfn "$src" "$overlay"
    if grep -q 'prefers-color-scheme' "$src"; then
      ok "GTK 4 overlay linked — follows the light/dark setting"
    else
      ok "GTK 4 overlay linked — dark-only style"
    fi
  fi
  printf '\n  %sRestart running GTK apps to pick up the change.%s\n' "$D" "$R"
}

flatpak_support() {
  local enable="$1"
  step "Flatpak"
  command -v flatpak >/dev/null || { warn "flatpak not installed — nothing to do."; return 0; }

  if [ "$enable" = "off" ]; then
    flatpak override --user --nofilesystem=xdg-data/themes \
                            --nofilesystem=xdg-config/gtk-4.0 \
                            --nofilesystem=xdg-config/gtk-3.0 2>/dev/null
    [ -d "$HOME/.themes" ] && flatpak override --user --nofilesystem="$HOME/.themes" 2>/dev/null
    ok "Sandbox access revoked"
    return 0
  fi

  # Flatpak apps see neither the themes directory nor the GTK 4 overlay unless
  # granted read-only access to both.
  flatpak override --user --filesystem=xdg-data/themes:ro \
                          --filesystem=xdg-config/gtk-4.0:ro \
                          --filesystem=xdg-config/gtk-3.0:ro 2>/dev/null \
    && ok "Granted read-only access to themes and GTK config" \
    || { err "Could not set overrides — run as your user, without sudo."; return 1; }
  [ -d "$HOME/.themes" ] && flatpak override --user --filesystem="$HOME/.themes:ro" 2>/dev/null \
    && ok "~/.themes also shared"
  printf '    %sRestart Flatpak apps for this to take effect.%s\n' "$D" "$R"
}

# Editor schemes ship with the themes. On install they replace an untouched
# Adwaita default only; a scheme the user picked themselves is never overridden.
scheme_for() {
  case "$1" in
    Monolith-Black*) echo Monolith-black ;;
    *-dark)          echo Monolith-dark ;;
    *)               echo Monolith ;;
  esac
}

schemes_installed() { [ -e "$SCHEMES_DIR/Monolith.xml" ]; }

# Themes and schemes install together, so both entry points stay in step.
install_payload() {
  install_themes || return 1
  install_icons "$(dirname "$themes_src")/icons"
  install_schemes "$(dirname "$themes_src")/schemes"
  schemes_installed && adopt_schemes "$(scheme_for "$(variant_for "$(default_theme)")")"
  return 0
}

icons_installed() { [ -d "$ICONS_DIR/Monolith" ]; }

install_icons() {  # source-dir
  [ -d "$1/Monolith" ] || return 0
  mkdir -p "$ICONS_DIR" || { warn "Could not create $ICONS_DIR"; return 0; }
  rm -rf "$ICONS_DIR/Monolith"
  # -a keeps the folder-open symlink a symlink.
  cp -a "$1/Monolith" "$ICONS_DIR/" 2>/dev/null \
    || { warn "Could not install the icon theme."; return 0; }
  ok "icon theme → $ICONS_DIR/Monolith"
}

apply_icons() {
  icons_installed || return 0
  gsettings set org.gnome.desktop.interface icon-theme Monolith 2>/dev/null \
    && ok "Icon theme set" || warn "Could not set icon-theme"
}

remove_icons() {
  case "$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")" in
    Monolith) gsettings reset org.gnome.desktop.interface icon-theme 2>/dev/null ;;
  esac
  rm -rf "$ICONS_DIR/Monolith"
}

install_schemes() {  # source-dir
  [ -d "$1" ] || return 0
  mkdir -p "$SCHEMES_DIR" || { warn "Could not create $SCHEMES_DIR"; return 0; }
  cp -f "$1"/Monolith*.xml "$SCHEMES_DIR/" 2>/dev/null \
    || { warn "Could not install the editor schemes."; return 0; }
  ok "editor schemes → $SCHEMES_DIR"
}

# Walks the apps that expose the setting, applies one action, and reports how
# many were touched. Apps without the schema installed are skipped.
each_scheme_app() {  # action [id]
  local action="$1" id="${2:-}" entry schema key cur n=0
  for entry in $SCHEME_APPS; do
    schema="${entry%%:*}"; key="${entry#*:}"
    gsettings writable "$schema" "$key" >/dev/null 2>&1 || continue
    cur="$(gsettings get "$schema" "$key" 2>/dev/null | tr -d "'")"
    case "$action" in
      set)   gsettings set "$schema" "$key" "$id" 2>/dev/null && n=$((n + 1)) ;;
      adopt) case "$cur" in Adwaita|Adwaita-dark)
               gsettings set "$schema" "$key" "$id" 2>/dev/null && n=$((n + 1)) ;; esac ;;
      reset) case "$cur" in Monolith*)
               gsettings reset "$schema" "$key" 2>/dev/null && n=$((n + 1)) ;; esac ;;
    esac
  done
  echo "$n"
}

apply_schemes() {
  local n; n="$(each_scheme_app set "$1")"
  if [ "$n" -gt 0 ]; then ok "$1 applied to $n app(s)"
  else warn "No installed app exposes an editor scheme setting."; fi
}

# On install we only replace an untouched Adwaita default. Anything the user
# deliberately picked is left alone.
adopt_schemes() {
  local n; n="$(each_scheme_app adopt "$1")"
  [ "$n" -gt 0 ] && ok "$1 set in $n app(s) still on Adwaita"
  return 0
}

reset_schemes() { each_scheme_app reset >/dev/null; }

remove_schemes() {
  reset_schemes
  rm -f "$SCHEMES_DIR"/Monolith*.xml 2>/dev/null
  rmdir "$SCHEMES_DIR" 2>/dev/null || true
}

# The manager is this same script: a checkout copies itself, a curl run fetches
# a fresh copy. Either way one file, never a stale duplicate.
install_manager() {
  mkdir -p "$bindir" || { warn "Could not create $bindir — skipping the manager."; return 0; }
  # Piped from curl there is no local file to copy, so a fresh one is fetched.
  if [ -n "$self" ] && [ -r "$self" ]; then
    cp "$self" "$manager" || { warn "Could not write $manager — skipping."; return 0; }
  else
    fetch "$RAW_URL" "$manager" \
      || { rm -f "$manager"; warn "Could not download the manager — the themes are installed regardless."; return 0; }
  fi
  chmod +x "$manager"
  manager_ok=1
  ok "manager → $manager"
  case ":$PATH:" in
    *":$bindir:"*) ;;
    *) warn "$bindir is not on your PATH"
       printf '    %srun it as %s, or add that directory to PATH%s\n' "$D" "$manager" "$R" ;;
  esac
}

do_uninstall() {
  step "Uninstall"
  # Returns non-zero when nothing was done, so the caller can tell a completed
  # uninstall from a cancelled one.
  confirm "Remove all Monolith themes and revert the selection?" n || { warn "Cancelled."; return 1; }

  gsettings reset org.gnome.desktop.interface gtk-theme 2>/dev/null || true
  gsettings reset org.gnome.shell.extensions.user-theme name 2>/dev/null || true
  if [ -L "$overlay" ] && [[ "$(readlink "$overlay")" == *"/themes/Monolith-"* ]]; then
    rm -f "$overlay"; ok "Removed the GTK 4 overlay"
  fi
  [ -e "$overlay.before-monolith" ] && { mv "$overlay.before-monolith" "$overlay"; ok "Restored your previous overlay"; }
  local tree
  for tree in $(installed_themes); do
    rm -rf "$tree"; ok "Removed $(basename "$tree")"
  done
  if icons_installed; then
    remove_icons; ok "Removed the icon theme"
  fi
  if schemes_installed; then
    remove_schemes; ok "Removed the editor schemes"
  fi

  if command -v flatpak >/dev/null && [ -n "$(flatpak override --user --show 2>/dev/null)" ]; then
    if confirm "Also revoke Flatpak sandbox access to your themes?" y; then
      flatpak_support off
    else
      warn "Left the Flatpak overrides in place."
    fi
  fi

  # Removed last: on the manager's own path this is the running file, which
  # bash has already read into memory.
  [ -e "$manager" ] && { rm -f "$manager"; ok "Removed $manager"; }
  ok "Done."
}

show_status() {
  printf '  %-16s %s\n' "gtk-theme" "$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null)"
  printf '  %-16s %s\n' "shell theme" \
    "$(gsettings get org.gnome.shell.extensions.user-theme name 2>/dev/null || echo '(extension not installed)')"
  if [ -L "$overlay" ]; then
    printf '  %-16s -> %s\n' "gtk-4.0 overlay" "$(readlink "$overlay")"
  elif [ -e "$overlay" ]; then
    printf '  %-16s %s\n' "gtk-4.0 overlay" "present, not a Monolith link"
  else
    printf '  %-16s %s\n' "gtk-4.0 overlay" "none (libadwaita apps unthemed)"
  fi
  printf '  %-16s %s\n' "themes" "$(installed_themes | wc -l) installed"
  if command -v flatpak >/dev/null; then
    [ -n "$(flatpak override --user --show 2>/dev/null)" ] \
      && printf '  %-16s %s\n' "flatpak" "access granted" \
      || printf '  %-16s %s\n' "flatpak" "no access"
  fi
  if icons_installed; then
    printf '  %-16s %s\n' "icon theme" "$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null)"
  else
    printf '  %-16s %s\n' "icon theme" "not installed"
  fi
  if schemes_installed; then
    printf '  %-16s %s\n' "editor schemes" "installed"
  else
    printf '  %-16s %s\n' "editor schemes" "not installed"
  fi
}

# Re-running is how you update, so keep whatever is already selected.
default_theme() {
  local current
  [ -n "${MONOLITH_THEME:-}" ] && { echo "$MONOLITH_THEME"; return; }
  current="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")"
  case "$current" in
    Monolith-*) echo "$current" ;;
    *)          echo "Monolith-Classic" ;;
  esac
}

# ------------------------------------------------------------------ bootstrap
# One shot: install or update, then hand over to the manager. Never interactive,
# because piped from curl there is no dependable way to ask anything.
run_bootstrap() {
  local updating=0
  is_installed && updating=1

  if [ "$updating" -eq 1 ]; then
    printf '\n%sMonolith%s %supdating an existing install%s\n' "$B" "$R" "$D" "$R"
  else
    printf '\n%sMonolith%s %sa monochrome GTK and GNOME Shell theme%s\n' "$B" "$R" "$D" "$R"
  fi
  preflight

  local broken
  broken="$(incomplete_themes | tr '\n' ' ')"
  [ -n "$broken" ] && warn "incomplete install detected ($broken) — replacing it"

  install_payload || exit 1
  apply_theme "$(variant_for "$(default_theme)")" || exit 1

  # On a first install Flatpak access is granted by default; on an update the
  # existing choice is left alone.
  case "${MONOLITH_FLATPAK:-auto}" in
    1) flatpak_support on ;;
    0) ;;
    *) [ "$updating" -eq 0 ] && command -v flatpak >/dev/null && flatpak_support on ;;
  esac

  step "Manager"
  install_manager

  printf '\n  %s%s%s\n' "$GRN" "$([ "$updating" -eq 1 ] && echo Updated. || echo Installed.)" "$R"
  if [ "$manager_ok" -eq 1 ]; then
    printf '  %sRun %smonolith-theme%s%s to change theme, editor scheme, or Flatpak access.%s\n\n' \
      "$D" "$R$B" "$R" "$D" "$R"
  else
    printf '  %sRe-run this command to change theme or update.%s\n\n' "$D" "$R"
  fi
}

# -------------------------------------------------------------------- manager
flatpak_flow() {
  if ! command -v flatpak >/dev/null; then
    step "Flatpak"; warn "flatpak is not installed — nothing to configure."; return 0
  fi
  local state="not granted"
  [ -n "$(flatpak override --user --show 2>/dev/null)" ] && state="granted"
  menu "Flatpak sandbox access is currently $state." \
    "Enable|Let Flatpak apps read the themes and GTK config" \
    "Disable|Revoke that access again" \
    "Back|Return without changing anything"
  case "$CHOICE" in
    Enable)  flatpak_support on ;;
    Disable) flatpak_support off ;;
  esac
}

choose_theme_flow() {
  menu "Which theme?" \
    "Monolith-Classic|GNOME's neutrals, cast removed. Monochrome accent." \
    "Monolith-Black|True black. Monochrome accent." \
    "Back|Return without changing anything"
  [ "$CHOICE" = "Back" ] && return 0
  local style="$CHOICE" variant
  variant="$(variant_for "$style")"
  [ "$variant" != "$style" ] && printf '  %sDesktop is in %s mode → %s%s\n' "$D" "$(scheme_now)" "$variant" "$R"
  apply_theme "$variant"
}

# Updating means fetching a newer release, which is the installer's job, so it
# is handed back rather than duplicated here.
update_flow() {
  step "Update"
  local broken
  broken="$(incomplete_themes | tr '\n' ' ')"
  if [ -n "$broken" ]; then
    warn "incomplete install: $broken"
    printf '    %sthe update will replace it%s\n' "$D" "$R"
  else
    ok "current install is complete"
  fi
  confirm "Fetch the latest release and update?" y || { warn "Cancelled."; return 0; }

  if command -v curl >/dev/null; then curl -fsSL "$RAW_URL" | bash
  elif command -v wget >/dev/null; then wget -qO- "$RAW_URL" | bash
  else err "curl or wget is required to update."; return 1; fi
}

run_manager() {
  if ! is_installed; then
    printf '\n%sMonolith%s %sis not installed%s\n' "$B" "$R" "$D" "$R"
    printf '  %sInstall it with:%s\n  curl -fsSL %s | bash\n\n' "$D" "$R" "$RAW_URL"
    exit 1
  fi

  printf '\n%sMonolith%s %stheme manager%s\n' "$B" "$R" "$D" "$R"
  while true; do
    menu "What would you like to do?" \
      "Choose theme|Switch to a different theme" \
      "Flatpak|Grant or revoke sandbox access" \
      "Editor scheme|Match GtkSourceView editors to the theme" \
      "Status|Show what is currently active" \
      "Update|Fetch and install the latest release" \
      "Uninstall|Remove everything and revert" \
      "Quit|Leave the manager"

    case "$CHOICE" in
      "Choose theme")       choose_theme_flow ;;
      Flatpak)              flatpak_flow ;;
      "Editor scheme")      scheme_flow ;;
      Status)               step "Status"; show_status ;;
      Update)               update_flow; break ;;
      Uninstall)            do_uninstall && break ;;
      Quit)                 break ;;
    esac
  done
  echo
}

# ---------------------------------------------------------------------- flags
case "${1:-}" in
  --install)       assume_yes=1; preflight
                   install_payload && apply_theme "$(variant_for "${2:-$(default_theme)}")"; exit $? ;;
  --uninstall)     assume_yes=1; do_uninstall; exit $? ;;
  --flatpak)       flatpak_support on; exit $? ;;
  --no-flatpak)    flatpak_support off; exit $? ;;
  --schemes)       want="${2:-$(scheme_for "$(variant_for "$(default_theme)")")}"
                   [ -e "$SCHEMES_DIR/$want.xml" ] || die "Not an installed scheme: $want"
                   apply_schemes "$want"; exit $? ;;
  --no-schemes)    reset_schemes; ok "Editors reset to their default scheme"; exit 0 ;;
  --status)        show_status; exit 0 ;;
  --help|-h)       sed -n '2,27p' "${self:-$0}" 2>/dev/null | sed 's/^# \?//'; exit 0 ;;
  "")              ;;
  *)               die "Unknown option: $1  (try --help)" ;;
esac

case "$ROLE" in
  manager)   run_manager ;;
  bootstrap) run_bootstrap ;;
esac
