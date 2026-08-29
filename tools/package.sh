#!/usr/bin/env bash
# Monolith — build release archives from assembled theme trees.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
themes="$root/build/themes"
dist="$root/dist"
version="$(tr -d '[:space:]' < "$root/VERSION")"

[ -d "$themes" ] || { echo "error: build/themes missing, run tools/build.sh" >&2; exit 1; }

rm -rf "$dist"
mkdir -p "$dist"

# The archive unpacks to a single directory holding the themes. The installer
# is not shipped inside it — it is the thing that fetches this archive, and it
# also works from an unpacked copy by finding themes/ beside itself.
stage="$dist/Monolith-$version"
mkdir -p "$stage"
cp -r "$themes" "$stage/themes"
[ -d "$root/build/schemes" ] && cp -r "$root/build/schemes" "$stage/schemes"
[ -d "$root/build/icons" ] && cp -a "$root/build/icons" "$stage/icons"
# The archive gets its own README: manual install steps, not repo docs.
sed "s|@VERSION@|$version|g" "$root/src/README.dist.md" > "$stage/README.md"
chmod 644 "$stage/README.md"
install -m644 "$root/LICENSE" "$stage/LICENSE"

tar -C "$dist" -cJf "$dist/Monolith-$version.tar.xz" "Monolith-$version"
( cd "$dist" && zip -qr "Monolith-$version.zip" "Monolith-$version" )
rm -rf "$stage"

# Published alongside the archives so the network installer can tell a corrupt
# download from a good one.
( cd "$dist" && sha256sum ./*.tar.xz ./*.zip | sed 's|\./||' > SHA256SUMS )

echo "archives in dist/"
for f in "$dist"/*; do
  printf '  %-28s %s\n' "$(basename "$f")" "$(du -h "$f" | cut -f1)"
done
