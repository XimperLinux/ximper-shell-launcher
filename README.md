# ximper-shell-tile-menu

Tile launcher.
A component of the Ximper Shell.

Fullscreen app launcher with tile grid inspired by Windows Phone 8.1. Tiles of different sizes, folders with animation, drag-and-drop, fuzzy search across all .desktop fields with GNOME Search Providers integration, gamepad support. Built with Vala, GTK4, libadwaita, gtk4-layer-shell, libmanette.

Supports Hyprland and Niri through compositor helpers.

## Build

```sh
meson setup _build
ninja -C _build
./_build/src/ximper-shell-tile-menu
```

## CLI

```sh
ximper-shell-tile-menu --toggle
```

## Compositor Support

The tile menu uses compositor helpers for compositor-specific behavior:

- Hyprland: floating mode can place the menu on the active workspace monitor via `hyprctl activeworkspace -j`.
- Niri: floating mode can place the menu on the focused workspace output via `niri msg --json workspaces`.

## Config

`~/.config/ximper-shell/tile-menu/config.json`

```json
{
  "max_columns": 0,
  "cell_size": 0,
  "layer": "overlay",
  "wallpaper_path": "",
  "wallpaper_fit": 2,
  "wallpaper_opacity": 100,
  "wallpaper_dim": 0,
  "groups": [{
    "name": "",
    "tiles": [
      { "desktop_id": "firefox.desktop", "size": "small" },
      { "desktop_id": "folder:Internet", "size": "folder",
        "folder_name": "Internet",
        "folder_items": ["firefox.desktop", "org.gnome.Epiphany.desktop"] }
    ]
  }]
}
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `max_columns` | int | `0` | Max tile columns (0 = auto, up to 18) |
| `cell_size` | int | `0` | Tile size in pixels (0 = auto from screen width) |
| `layer` | string | `"overlay"` | Layer shell layer: `"background"`, `"bottom"`, `"top"`, or `"overlay"`. Numeric values from older configurations are migrated automatically when saved. |
| `wallpaper_path` | string | `""` | Absolute path to a local wallpaper image shown behind the menu; empty disables it |
| `wallpaper_fit` | int | `2` | Image fit: 0=fill, 1=contain, 2=cover, 3=scale down |
| `wallpaper_opacity` | int | `100` | Wallpaper opacity, 0–100% |
| `wallpaper_dim` | int | `0` | Black dimmer above wallpaper, 0–100% |
| `groups` | array | | Tile groups with tiles and folders |

## Gamepad

Gamepad support via libmanette. A toast notification appears when a gamepad is connected.

| Button | Action |
|--------|--------|
| D-pad / Left stick | Navigate tiles |
| A (South) | Activate tile / select menu item |
| B (East) | Back (close folder / close popover / close menu) |
| X (North) | Open context menu on focused tile |
| Xbox / Guide | Toggle tile menu |
| LB / RB | Scroll up / down |

Hold D-pad or stick for continuous navigation.

## D-Bus

`ru.ximperlinux.shell.TileMenu` at `/ru/ximperlinux/shell/TileMenu`:
- `Toggle()` — show/hide tile menu

## License

GPLv3 — see [LICENSE](LICENSE).
