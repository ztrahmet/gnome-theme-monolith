# Architecture

Monolith uses flat, hand-editable Sass variables per color variant and simple entry points for each desktop subsystem.

## Source Tree

```
src/
  colors/
    _classic-light.scss     Flat variables for Classic light
    _classic-dark.scss      Flat variables for Classic dark
    _black.scss             Flat variables for Pitch Black
  _emit.scss                GTK 4 token emission mixin
  gtk-4.0/                  GTK 4 entry points
  gtk-3.0/                  GTK 3 base and entry points
  gnome-shell/              GNOME Shell base and entry points
  icons/                    Monochrome folder icons + icon theme metadata
  index.theme.in            Theme metadata template
install.sh                  Dual-role installer & CLI manager
tools/
  build.sh                  Sass compilation & theme tree assembly
  check.sh                  Pure Bash QA check script
  schemes.sh                GtkSourceView scheme generation
  preview.sh                Renders docs/previews/ from the compiled palette
  fetch-upstream.sh         Fetches pinned upstream sources
  package.sh                Builds release packages
```

## Build Pipeline

The build script compiles 3 CSS variants and assembles 4 theme packages (`Monolith-Classic`, `Monolith-Classic-dark`, `Monolith-Black`, `Monolith-Black-dark`):

- **GTK 4**: Compiles each variant with `sassc`. Assembles `gtk.css` (with Default base import) for plain GTK 4 apps, and `libadwaita.css` overlay (with prefers-color-scheme media queries for paired themes) for libadwaita apps.
- **GTK 3**: Bundles upstream `adw-gtk3` directly and layers our named-color overrides from `src/gtk-3.0/_base.scss`.
- **Icon theme**: Copied verbatim into `build/icons/Monolith/`. The set is neutral and variant-independent, so one theme serves all four; `Inherits=Adwaita` covers everything it does not override.
- **Editor schemes**: Rewrites upstream's Adwaita GtkSourceView schemes with our neutral greys and editor surfaces, leaving syntax colors untouched. Output lands in `build/schemes/`.
- **GNOME Shell**: Compiles from upstream Shell Sass, applying neutral base variables and substituting runtime accent keywords. The User Themes extension loads the resulting `gnome-shell.css` directly.

## Key Rules

1. **User Overlay for libadwaita**: Modern GNOME apps ignore theme directories; `install.sh` symlinks `~/.config/gtk-4.0/gtk.css` to the active theme's `libadwaita.css`.
2. **Self-Contained GTK 3**: Bundling `adw-gtk3` avoids runtime import failures and system dependency issues.
3. **Native Status Colors**: Status colors (error, warning, success) are preserved native across all themes.
4. **Editor Schemes Adopt Only Defaults**: Schemes install with the themes and replace an app's untouched Adwaita default. Any scheme the user chose themselves is left alone.
