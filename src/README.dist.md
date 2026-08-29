# Monolith @VERSION@

A clean monochrome GTK and GNOME Shell theme for GNOME ≥ 48.

**The easy way** — installs everything and sets up the `monolith-theme` manager:

```bash
curl -fsSL https://raw.githubusercontent.com/ztrahmet/gnome-theme-monolith/main/install.sh | bash
```

The rest of this file covers installing by hand from this archive.

## What's in here

```
themes/     Monolith-Classic, -Classic-dark, -Black, -Black-dark
icons/      Monolith icon theme (folder icons; inherits Adwaita)
schemes/    GtkSourceView editor schemes
```

## Manual installation

Copy each part into your home directory:

```bash
mkdir -p ~/.local/share/themes ~/.local/share/icons ~/.local/share/gtksourceview-5/styles

cp -r  themes/*        ~/.local/share/themes/
cp -a  icons/Monolith  ~/.local/share/icons/
cp     schemes/*.xml   ~/.local/share/gtksourceview-5/styles/
```

> Use `cp -a` for the icons — `icons/Monolith/scalable/status/folder-open.svg` is a symlink and must stay one.

Then select a variant — `Monolith-Classic` (light), `Monolith-Classic-dark`, `Monolith-Black`, or `Monolith-Black-dark`. Replace the name below with your choice:

```bash
gsettings set org.gnome.desktop.interface gtk-theme   'Monolith-Classic-dark'
gsettings set org.gnome.desktop.interface icon-theme  'Monolith'
gsettings set org.gnome.shell.extensions.user-theme name 'Monolith-Classic-dark'
```

Modern GNOME apps ignore theme directories, so link the libadwaita overlay too:

```bash
mkdir -p ~/.config/gtk-4.0
ln -sfn ~/.local/share/themes/Monolith-Classic-dark/gtk-4.0/libadwaita.css ~/.config/gtk-4.0/gtk.css
```

Restart running apps to pick up the change.

## Optional

**Editor colours** — in Text Editor or Builder, choose the `Monolith` scheme under Appearance.

**Flatpak apps** need read access to your themes:

```bash
flatpak override --user --filesystem=xdg-data/themes:ro \
                        --filesystem=xdg-config/gtk-4.0:ro \
                        --filesystem=xdg-config/gtk-3.0:ro
```

## Uninstalling

```bash
rm -rf ~/.local/share/themes/Monolith-* ~/.local/share/icons/Monolith
rm -f  ~/.local/share/gtksourceview-5/styles/Monolith*.xml ~/.config/gtk-4.0/gtk.css
gsettings reset org.gnome.desktop.interface gtk-theme
gsettings reset org.gnome.desktop.interface icon-theme
gsettings reset org.gnome.shell.extensions.user-theme name
```

## Notes

- GNOME Shell theming requires the [User Themes](https://extensions.gnome.org/extension/19/user-themes/) extension.
- GTK 3 support is based on [adw-gtk3](https://github.com/lassekongo83/adw-gtk3) (LGPL-2.1-only); see `LICENSE.adw-gtk3` inside each theme.
- Monolith is licensed **GPL-3.0-or-later** — see `LICENSE`.
