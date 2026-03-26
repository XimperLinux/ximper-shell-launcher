# ximper-shell-tile-menu

Tile launcher.
A component of the Ximper Shell.

Fullscreen app launcher with tile grid inspired by Windows Phone 8.1. Tiles of different sizes, folders with animation, drag-and-drop, fuzzy search across all .desktop fields with GNOME Search Providers integration, gamepad support. Built with Vala, GTK4, libadwaita, gtk4-layer-shell, libmanette.

Supports Hyprland and (soon) other compositors.

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

## Config

`~/.config/ximper-shell/tile-menu/config.json`

```json
{
  "max_columns": 0,
  "cell_size": 0,
  "layer": 3,
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
| `layer` | int | `3` | Layer shell layer (0=background, 1=bottom, 2=top, 3=overlay) |
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
