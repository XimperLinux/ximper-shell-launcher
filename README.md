# ximper-shell-tile-menu

Tile launcher.
A component of the Ximper Shell.

Fullscreen app launcher with tile grid inspired by Windows Phone 8.1. Tiles of different sizes, folders with animation, drag-and-drop, search with GNOME Search Providers integration. Built with Vala, GTK4, libadwaita, gtk4-layer-shell.

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

## D-Bus

`ru.ximperlinux.shell.TileMenu` at `/ru/ximperlinux/shell/TileMenu`:
- `Toggle()` — show/hide tile menu

## License

GPLv3 — see [LICENSE](LICENSE).
