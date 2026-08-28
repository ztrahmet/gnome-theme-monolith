# Palette Reference

Monolith defines its color palettes directly as flat Sass variables under `src/colors/`.

## Styles

- **Classic**: De-tints GNOME Adwaita neutral tokens, removing the subtle blue cast to produce clean neutral grays. Available in light (`_classic-light.scss`) and dark (`_classic-dark.scss`).
- **Black**: A true black dark palette (`#000000` canvas) with layered dark surfaces and high contrast text/borders (`_black.scss`).

## Structure

Every file in `src/colors/` defines the same flat variables, grouped by where they land:

- **GTK named colors**: Surface and foreground tokens (`$window-bg-color`, `$view-bg-color`, `$headerbar-bg-color`, `$sidebar-bg-color`, `$card-bg-color`, `$dialog-bg-color`, etc.).
- **Custom properties**: Toggles, overview background, and border opacity.
- **Palette tokens**: De-tinted neutral values for GNOME's numbered scales (`$light-1` .. `$light-5`, `$dark-1` .. `$dark-5`).
- **Chrome overrides**: Hardcoded libadwaita element colors (toasts, tooltips, window outlines).
- **GTK 3 specifics**: Borders and insensitive state colors.
- **GNOME Shell bases**: Base colors for the Shell panel, cards, and overlay surfaces.

## Invariants

- **Monochrome Accent**: `$accent-fg-color` always equals `$window-bg-color`, so whatever sits on an accented surface matches the window behind it. Verified by `tools/check.sh`.
- **Native Status Colors**: Error, warning, and success colors remain native — nothing under `src/` emits them.
- **Direct Hand-Editing**: Colors are maintained directly in their respective files under `src/colors/` without nested maps or helper functions.
