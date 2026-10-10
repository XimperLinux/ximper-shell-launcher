# ximper-shell-launcher

Application launcher.
A component of the Ximper Shell.

Fullscreen app launcher with a tiles mode inspired by Windows Phone 8.1. Tiles of different sizes, folders with animation, drag-and-drop, fuzzy search across all .desktop fields with GNOME Search Providers integration, gamepad support. Built with Vala, GTK4, libadwaita, gtk4-layer-shell, libmanette.

Supports Hyprland and Niri through compositor helpers.

## Features

- Fullscreen or floating launcher in tiles, Wofi, and combined (application list + tiles) modes.
- A loading capsule above search in every mode: an immediate looping left-to-right rounded segment, then a smooth return to the compact solid capsule before fading on completion. Respects disabled animations; previous results stay visible. Zen reference-source links are in `src/search/loading-indicator.vala`; GTK rendering and the completion transition are original.
- One shared virtualized application list for Wofi, combined mode, and search; optional alphabetical sorting with letter headers. Combined mode supports the list on either side and has no profile/power sidebar.
- In combined mode, typing smoothly expands the list over the tiles into full-width search results; clearing the query slides it back. The animation is mirrored for a right-side list. Alphabetical section letters are bold. The previous list stays visible while new results are prepared separately, then the complete model is replaced at once (no empty intermediate list). Stale results cannot be activated while a query is pending.
- Small, medium, and large application tiles; animated folders; insertion-based drag-and-drop with a highlighted landing slot and smoothly moving neighbors. Tiles wrap in order to the next row; wider/taller tiles retain their spans, and gaps may remain rather than backfilling earlier rows. Insertion targets are calculated without the dragged tile or preview gap; empty space is resolved row-first so the animated layout cannot chase its own changes.
- Drop on a folder's center to add an app, or near its edges to insert beside it. Open-folder items can be reordered or extracted into the main grid. Preview uses a separate candidate layout; only a successful drop saves it, and cancellation restores the original layout. Widgets are rebuilt only after the drag source finishes.
- Keyboard navigation, fuzzy application search, and results from GNOME Search Providers.
- Optional per-menu wallpaper, background dimming, and opacity controls.
- Gamepad navigation through libmanette.
- Optional integration with Ximper Shell Dock to pin or unpin applications from a tile context menu.

## Build

```sh
meson setup _build
ninja -C _build
./_build/src/ximper-shell-launcher
meson test -C _build --print-errorlogs
```

Application tiles use GIO to launch `.desktop` entries. D-Bus activation is
asynchronous; if it fails, the launcher retries the entry's `Exec` via GIO.
Entries without a valid D-Bus name use GIO's normal `Exec` path with `setsid()`.

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
  "app_list_side": "left",
  "app_list_sort": "alphabetical",
  "search_sort": "relevance",
  "window_mode": "floating",
  "close_on_focus_loss": true,
  "floating_position": "custom",
  "floating_margin": 16,
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
| `launcher_mode` | string | `"tiles"` | Launcher interface: `"tiles"`, compact `"wofi"`, or `"combined"` (list + tiles) |
| `app_list_side` | string | `"left"` | Application list side in combined mode: `"left"` or `"right"` |
| `app_list_sort` | string | `"alphabetical"` | Empty-query list in Wofi/combined: `"alphabetical"` with letter headers, or `"relevance"` by launch frequency |
| `search_sort` | string | `"relevance"` | Local search results: `"relevance"` by match score and launch frequency, or `"alphabetical"`; provider order is unchanged |
| `window_mode` | string | `"floating"` | Window mode for all launcher interfaces: `"fullscreen"` or `"floating"` |
| `close_on_focus_loss` | bool | `true` | Close the floating launcher when it loses focus |
| `floating_position` | string | `"custom"` | Manual percentages (`"custom"`) or `"top-left"`, `"top"`, `"top-right"`, `"left"`, `"center"`, `"right"`, `"bottom-left"`, `"bottom"`, `"bottom-right"`; floating windows only |
| `floating_margin` | int | `16` | Edge margin in pixels for presets (0–512, limited by the monitor size); ignored in custom mode |
| `floating_x` | int | `0` | Legacy pixel offset retained for compatibility; manual placement uses percentages |
| `floating_y` | int | `24` | Legacy pixel offset retained for compatibility; manual placement uses percentages |
| `floating_width` | int | `1120` | Width of the floating launcher in pixels; shared by all interfaces |
| `floating_height` | int | `880` | Height of the floating launcher in pixels; shared by all interfaces |
| `floating_x_percent` | int | `50` | Horizontal position in custom mode, 0–100% of available space; retained when selecting presets |
| `floating_y_percent` | int | `50` | Vertical position in custom mode, 0–100% of available space; retained when selecting presets |
| `output` | string[] | `[]` | Target monitor connector; an empty array uses the compositor-selected active output |
| `wallpaper_path` | string | `""` | Absolute path to a local wallpaper image shown behind the menu; empty disables it |
| `wallpaper_fit` | int | `2` | Image fit: 0=fill, 1=contain, 2=cover, 3=scale down |
| `wallpaper_opacity` | int | `100` | Wallpaper opacity, 0–100% |
| `wallpaper_dim` | int | `0` | Black dimmer above wallpaper, 0–100% |
| `background_opacity` | int | `100` | Menu background opacity, 0–100% |
| `search.providers_enabled` | bool | `true` | Enable all external GNOME Search Providers globally; local application search stays enabled when this is `false` |
| `search.providers` | array | `[]` | Ordered search providers; each entry has a desktop-file `id` and an `enabled` flag |
| `groups` | array | | Tile groups with tiles and folders |

To enable combined mode, set `"launcher_mode": "combined"` and run `ximper-shell-launcher --reload`. Set `"app_list_side": "right"` to place the list on the right. Existing tile/folder layouts are reused unchanged. Alphabetical grouping uses Unicode letters; names starting with digits or symbols appear under `#`.

Floating placement is independent of `launcher_mode`: it neither enables tiles nor replaces Wofi. For example, set `"floating_position": "bottom-left"` and `"floating_margin": 16`, then run `ximper-shell-launcher --reload`. Presets use native layer-shell anchors and limit the requested size to the selected monitor. Floating windows respect space reserved by panels such as Waybar; preset edge margins are relative to that available area. `"custom"` restores the existing percentage coordinates; fullscreen ignores positioning presets.

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
