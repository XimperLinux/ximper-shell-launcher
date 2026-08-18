# ximper-shell-launcher

Application launcher.
A component of the Ximper Shell.

Fullscreen app launcher with a tiles mode inspired by Windows Phone 8.1. Tiles of different sizes, folders with animation, drag-and-drop, fuzzy search across all .desktop fields with GNOME Search Providers integration, gamepad support. Built with Vala, GTK4, libadwaita, gtk4-layer-shell, libmanette.

Supports Hyprland and Niri through compositor helpers.

## Features

- Fullscreen or floating launcher in both tiles and Wofi modes.
- Small, medium, and large application tiles; animated folders; drag-and-drop rearrangement and folder management.
- Keyboard navigation, fuzzy application search, and results from GNOME Search Providers.
- Optional per-menu wallpaper, background dimming, and opacity controls.
- Gamepad navigation through libmanette.
- Optional integration with Ximper Shell Dock to pin or unpin applications from a tile context menu.

## Build

```sh
meson setup _build
ninja -C _build
./_build/src/ximper-shell-launcher
```

## CLI

```sh
# Opens the launcher selected by launcher_mode
ximper-shell-launcher --toggle
ximper-shell-launcher --reload    # reread config from disk and apply it to the running launcher
ximper-shell-launcher --describe  # print the current configuration and supported parameters as JSON
```

## Compositor Support

The launcher uses compositor helpers for compositor-specific behavior:

- Hyprland: floating mode can place the menu on the active workspace monitor via `hyprctl activeworkspace -j`.
- Niri: floating mode can place the menu on the focused workspace output via `niri msg --json workspaces`.

## Config

`~/.config/ximper-shell/launcher/config.json`

```json
{
  "max_columns": 0,
  "cell_size": 0,
  "layer": "overlay",
  "launcher_mode": "tiles",
  "window_mode": "floating",
  "close_on_focus_loss": true,
  "floating_x": 0,
  "floating_y": 24,
  "floating_width": 1120,
  "floating_height": 880,
  "floating_x_percent": 50,
  "floating_y_percent": 50,
  "output": [],
  "wallpaper_path": "",
  "wallpaper_fit": 2,
  "wallpaper_opacity": 100,
  "wallpaper_dim": 0,
  "background_opacity": 100,
  "search": {
    "providers_enabled": true,
    "providers": [
      { "id": "org.gnome.Nautilus.desktop", "enabled": true },
      { "id": "org.gnome.Calculator.desktop", "enabled": false }
    ]
  },
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
| `launcher_mode` | string | `"tiles"` | Launcher interface: `"tiles"` or compact `"wofi"` |
| `window_mode` | string | `"floating"` | Window mode for both tiles and Wofi modes: `"fullscreen"` or `"floating"` |
| `close_on_focus_loss` | bool | `true` | Close the floating launcher when it loses focus |
| `floating_x` | int | `0` | Horizontal offset of the floating launcher in pixels |
| `floating_y` | int | `24` | Vertical offset of the floating launcher in pixels |
| `floating_width` | int | `1120` | Width of the floating launcher in pixels; used by both tiles and Wofi modes |
| `floating_height` | int | `880` | Height of the floating launcher in pixels; used by both tiles and Wofi modes |
| `floating_x_percent` | int | `50` | Horizontal position, 0–100% of available space; used by both tiles and Wofi modes |
| `floating_y_percent` | int | `50` | Vertical position, 0–100% of available space; used by both tiles and Wofi modes |
| `output` | string[] | `[]` | Target monitor connector; an empty array uses the compositor-selected active output |
| `wallpaper_path` | string | `""` | Absolute path to a local wallpaper image shown behind the menu; empty disables it |
| `wallpaper_fit` | int | `2` | Image fit: 0=fill, 1=contain, 2=cover, 3=scale down |
| `wallpaper_opacity` | int | `100` | Wallpaper opacity, 0–100% |
| `wallpaper_dim` | int | `0` | Black dimmer above wallpaper, 0–100% |
| `background_opacity` | int | `100` | Menu background opacity, 0–100% |
| `search.providers_enabled` | bool | `true` | Enable all external GNOME Search Providers globally; local application search stays enabled when this is `false` |
| `search.providers` | array | `[]` | Ordered search providers; each entry has a desktop-file `id` and an `enabled` flag |
| `groups` | array | | Tile groups with tiles and folders |

`monitor_index` is accepted only as a legacy setting and is migrated to `output` when the configuration is saved. Use the monitor connector name instead, because display indexes are not stable.

Search providers are discovered in the user and system `gnome-shell/search-providers` XDG data directories. Set `search.providers_enabled` to `false` to disable all external providers while keeping local application search. Their order in `search.providers` controls the order of result sections. Providers not listed there remain enabled and follow the configured entries alphabetically.


### Custom CSS

Create `~/.config/ximper-shell/launcher/style.css` to change the menu appearance without modifying installed files. This stylesheet is loaded with user priority, so its rules override the bundled stylesheet. Reload or restart the launcher after editing it.

The bundled [`data/ximper-shell-launcher.css`](data/ximper-shell-launcher.css) lists all available rules and is a useful starting point. On an installed system it is normally available as `/etc/xdg/ximper-shell/launcher/style.css`.

```sh
mkdir -p ~/.config/ximper-shell/launcher
cp /etc/xdg/ximper-shell/launcher/style.css \
  ~/.config/ximper-shell/launcher/style.css
```

For example, to adjust the menu background, tile corners, and floating-menu shadow:

```css
.window-background {
  background: @window_bg_color;
}

.tile {
  border-radius: 16px;
}

.grid-overlay.floating {
  box-shadow: 0 8px 24px @headerbar_shade_color;
}
```

Useful selectors include `.grid-overlay`, `.grid-overlay.floating`, `.window-background`, `.tile`, `.tile-name`, `.search-entry`, `.search-result-row`, `.folder-expanded`, and `.wallpaper-dimmer`. GTK/libadwaita theme colors such as `@window_bg_color`, `@card_bg_color`, and `@accent_bg_color` follow the active system theme.

## Gamepad

Gamepad support via libmanette. A toast notification appears when a gamepad is connected.

| Button | Action |
|--------|--------|
| D-pad / Left stick | Navigate tiles |
| A (South) | Activate tile / select menu item |
| B (East) | Back (close folder / close popover / close menu) |
| X (North) | Open context menu on focused tile |
| Xbox / Guide | Toggle launcher |
| LB / RB | Scroll up / down |

Hold D-pad or stick for continuous navigation.

## D-Bus

`ru.ximperlinux.shell.Launcher` at `/ru/ximperlinux/shell/Launcher`:
- `Toggle()` — show/hide launcher
- `Reload()` — reread the configuration file and apply changes without restarting

## License

GPLv3 — see [LICENSE](LICENSE).
