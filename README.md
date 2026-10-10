# ximper-shell-launcher

Application launcher. A component of the Ximper Shell.

[Русская документация](README_ru.md)

Wayland app launcher with a tiles mode inspired by Windows Phone 8.1. Tiles of different sizes, folders with animation, drag-and-drop, fuzzy search across application metadata with GNOME Search Providers integration, gamepad support. Built with Vala, GTK4, libadwaita, gtk4-layer-shell, libmanette.

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

## Build and installation

Requires Meson ≥ 0.62, Ninja, Vala, a C compiler, gettext tools, and development packages for GTK ≥ 4.12, libadwaita ≥ 1.4, gtk4-layer-shell ≥ 1.0, json-glib, gio-unix, gdk-pixbuf, and manette-0.2. Gamepad support is a required build dependency; Dock and search providers are optional runtime integrations. Run in a Wayland session with layer-shell support and a session D-Bus.

```sh
meson setup _build --prefix=/usr --sysconfdir=/etc
ninja -C _build
meson test -C _build --print-errorlogs
./_build/src/ximper-shell-launcher --toggle
# Optional system installation (requires permission to write system directories):
meson install -C _build
```

Meson installs the binary, CSS under `sysconfdir/xdg/ximper-shell/launcher/style.css`, and translations. Runtime system CSS lookup uses `/etc/xdg`, hence the explicit `--sysconfdir=/etc`. The ALT RPM recipe is [`ximper-shell-launcher.spec`](ximper-shell-launcher.spec); its `%check` runs Meson tests. The existing `desktop-entry-exec` test covers desktop-entry execution and D-Bus activation/fallback, not UI or drag-and-drop.

### Session startup

Running `ximper-shell-launcher` without options starts it with a hidden window. Configure your compositor/session to start it and bind `ximper-shell-launcher --toggle` to a key as needed. No autostart file, desktop entry, systemd unit, or D-Bus activation service file is shipped. It is a single-instance GApplication: subsequent CLI commands are forwarded to the running instance. `--toggle` shows **or hides** the menu.

Application tiles use GIO to launch `.desktop` entries. D-Bus activation is
asynchronous; if it fails, the launcher retries the entry's `Exec` via GIO.
Entries without a valid D-Bus name use GIO's normal `Exec` path with `setsid()`.

## CLI

```sh
# Shows/hides the launcher selected by launcher_mode (-t is the short form)
ximper-shell-launcher --toggle
ximper-shell-launcher --reload    # reread config from disk and apply it to the running launcher
ximper-shell-launcher --describe  # print the current configuration and supported parameters as JSON
```

`--reload` reloads configuration/applications and rebuilds the interface, not CSS. `--describe` prints `config`, `runtime`, `paths`, and parameter/provider `metadata`. It is not a pure headless schema tool: a new instance performs GUI startup, which can create or migrate configuration. Commands forwarded to a running instance use its configuration. Output differs from the on-disk schema: `config.search_providers` is flat, whereas the file uses `search.providers`. Do not copy the whole output to `config.json`. `runtime.running` is a constant, not an independent health probe. Combined flags take priority in this order: describe, toggle, reload.

### Command-line presets

```sh
ximper-shell-launcher --list-presets
ximper-shell-launcher --preset 8.1
ximper-shell-launcher --preset 10
ximper-shell-launcher --preset ximper
ximper-shell-launcher --preset wofi
# Apply and also toggle visibility:
ximper-shell-launcher --preset 8.1 --toggle
```

**Applying a preset replaces the manual layout with a newly generated one, without confirmation.** There are no saved preset profiles or automatic restoration. Generation uses installed visible `.desktop` apps and their categories. Select presets by command, not a config preset-name field; resulting ordinary settings are persisted automatically. Unrelated search, wallpaper and output settings are preserved.

| Name | Interface | Fresh layout |
|---|---|---|
| `8.1` | Fullscreen tiles, horizontal groups, pinned | All visible apps grouped by category, no folders |
| `10` | Bottom-left floating combined view, list left, vertical groups | Only System/Settings/TerminalEmulator/FileManager and Network apps in System and Internet groups; all other apps remain in the list/search |
| `ximper` | Fullscreen all-app tiles, groups disabled | Category folders plus standalone singleton and uncategorized apps |
| `wofi` | Compact centered floating list | A fresh categorized folder layout is saved but tiles are not displayed |

Only the four exact names above are accepted, without `win` prefixes. `--preset` cannot be combined with `--describe`, `--reload` or `--list-presets`; invalid requests return nonzero before GUI startup. `--list-presets` exits without GUI startup. Applying during DnD is rejected. Without `--toggle`, the command itself does not change menu visibility; an existing interface is rebuilt immediately.

Approximate geometry at GTK's base scale, not a pixel-identical Windows theme:

| Preset | Square / wide / large tile | Icon |
|---|---|---|
| `8.1` | 150×150 / 306×150 / 306×306 | 64 px |
| `10` | 100×100 / 206×100 / 206×206 | 48 px, approximate |

Launcher `small / medium / large` map to Windows **medium-square**, wide and large; there is no separate Windows 70×70 small tile. These presets enable square-tile names. The existing 6 px cell gap is retained. Very short horizontal viewports shrink cells to fit.

Sources: Microsoft [desktop tile/icon dimensions and scaling](https://learn.microsoft.com/en-us/windows/win32/shell/desktop-app-tiles-on-the-start-screen), [nominal 70/150/310 tile sizes](https://learn.microsoft.com/en-us/uwp/api/windows.ui.startscreen.tilesize), [Windows 10 proportions: 1×1, 2×2, 4×2, 4×4](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/customize-the-start-screen). Windows 8.1's 150 square and 64 icon at 100% are documented; 310 wide/large implies a 10 px gap. Windows 10 proportions are documented, but our 100 px square and 48 icon are aesthetic approximations, not verified native menu measurements. Physical pixels depend on display scaling.

## Compositor Support

The launcher uses compositor helpers for compositor-specific behavior:

- Hyprland: floating mode can place the menu on the active workspace monitor via `hyprctl activeworkspace -j`.
- Niri: floating mode can place the menu on the focused workspace output via `niri msg --json workspaces`.

## Config

`$XDG_CONFIG_HOME/ximper-shell/launcher/config.json` (normally `~/.config/ximper-shell/launcher/config.json`). Edit the file and use `--reload`; there is no built-in settings window.

This example includes sample applications/providers, not a universal initial layout:

```json
{
  "max_columns": 0,
  "cell_size": 0,
  "layer": "overlay",
  "launcher_mode": "tiles",
  "tile_mode": "all",
  "group_layout": "vertical",
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
  "search_providers_enabled": true,
  "search": {
    "providers": [
      { "id": "org.gnome.Nautilus.desktop", "enabled": true },
      { "id": "org.gnome.Calculator.desktop", "enabled": false }
    ]
  },
  "groups": [{
    "name": "",
    "tiles": [
      { "desktop_id": "org.gnome.Nautilus.desktop", "size": "small" },
      { "desktop_id": "folder:Internet", "size": "folder",
        "folder_name": "Internet",
        "folder_items": ["firefox.desktop", "org.gnome.Epiphany.desktop"] }
    ]
  }]
}
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `max_columns` | int | `0` | Column limit in vertical layout (0 = automatic, capped at 18); actual grid has at least 4 columns and rounds odd counts down to an even count. Horizontal group growth is not capped by this setting |
| `cell_size` | int | `0` | Cell size in pixels (0 = automatic from board width in vertical layout, 70 in horizontal layout) |
| `layer` | string | `"overlay"` | Layer shell layer: `"background"`, `"bottom"`, `"top"`, or `"overlay"`. Numeric values from older configurations are migrated automatically when saved. |
| `launcher_mode` | string | `"tiles"` | Launcher interface: `"tiles"`, compact `"wofi"`, or `"combined"` (list + tiles) |
| `tile_mode` | string | `"all"` | Tile area: `"all"` applications or only launcher `"pinned"` entries. Independent of `launcher_mode`; applies to `tiles` and `combined` |
| `groups_enabled` | bool | `true` | Show group headers/actions. False gives one flat folder-capable board with no group DnD tail; edits save one unnamed group |
| `tile_icon_size` | int | `0` | Tile icon size: 0 uses existing automatic sizes, otherwise 1–128 px clamped to the cell |
| `tile_square_labels` | bool | `false` | Show square-tile names; enabled by `8.1` and `10` presets |
| `group_layout` | string | `"vertical"` | Groups stacked `"vertical"` or side by side `"horizontal"` with horizontal scrolling; independent of tile mode |
| `app_list_side` | string | `"left"` | Application list side in combined mode: `"left"` or `"right"` |
| `app_list_sort` | string | `"alphabetical"` | Empty-query list in Wofi/combined: `"alphabetical"` with letter headers, or `"relevance"` by launch frequency |
| `search_sort` | string | `"relevance"` | Local search results: `"relevance"` by match score and launch frequency, or `"alphabetical"`; provider order is unchanged |
| `window_mode` | string | `"floating"` | Window mode for all launcher interfaces: `"fullscreen"` or `"floating"` |
| `close_on_focus_loss` | bool | `true` | Close the floating launcher when it loses focus |
| `floating_position` | string | `"custom"` | Manual percentages (`"custom"`) or `"top-left"`, `"top"`, `"top-right"`, `"left"`, `"center"`, `"right"`, `"bottom-left"`, `"bottom"`, `"bottom-right"`; floating windows only |
| `floating_margin` | int | `16` | Edge margin in pixels for presets (0–512, limited by the monitor size); ignored in custom mode |
| `floating_x` | int | `0` | Legacy pixel offset retained for compatibility; manual placement uses percentages |
| `floating_y` | int | `24` | Legacy pixel offset retained for compatibility; manual placement uses percentages |
| `floating_width` | int | `1120` | Requested width in pixels; runtime clamps to 320–4096; shared by all interfaces |
| `floating_height` | int | `880` | Requested height in pixels; runtime clamps to 240–4096; shared by all interfaces |
| `floating_x_percent` | int | `50` | Horizontal position in custom mode, 0–100% of available space; retained when selecting presets |
| `floating_y_percent` | int | `50` | Vertical position in custom mode, 0–100% of available space; retained when selecting presets |
| `output` | string[] | `[]` | Floating target connectors; only the first is used. If absent/unavailable, try the compositor's active output, then the monitor of the pointer surface |
| `wallpaper_path` | string | `""` | Absolute path to a local wallpaper image shown behind the menu; empty disables it |
| `wallpaper_fit` | int | `2` | Image fit: 0=fill, 1=contain, 2=cover, 3=scale down |
| `wallpaper_opacity` | int | `100` | Wallpaper opacity, 0–100% |
| `wallpaper_dim` | int | `0` | Black dimmer above wallpaper, 0–100% |
| `background_opacity` | int | `100` | Menu background opacity, 0–100% |
| `search_providers_enabled` | bool | `true` | Enable all external GNOME Search Providers globally; local application search stays enabled when this is `false` |
| `search.providers` | array | `[]` | Ordered search providers; each entry has a desktop-file `id` and an `enabled` flag |
| `groups` | array | | Tile groups with tiles and folders |

To enable combined mode, set `"launcher_mode": "combined"` and run `ximper-shell-launcher --reload`. Set `"app_list_side": "right"` to place the list on the right. Existing tile/folder layouts are reused unchanged. Alphabetical grouping uses Unicode letters; names starting with digits or symbols appear under `#`.

Floating placement is independent of `launcher_mode`: it neither enables tiles nor replaces Wofi. For example, set `"floating_position": "bottom-left"` and `"floating_margin": 16`, then run `ximper-shell-launcher --reload`. Presets use native layer-shell anchors and limit the requested size to the selected monitor. Floating windows respect space reserved by panels such as Waybar; preset edge margins are relative to that available area. `"custom"` restores the existing percentage coordinates; fullscreen ignores positioning presets.

`monitor_index` is accepted only as a legacy setting and is migrated to `output` when the configuration is saved. Use the monitor connector name instead, because display indexes are not stable.

Search providers are discovered in the user and system `gnome-shell/search-providers` XDG data directories. Set `search_providers_enabled` to `false` to disable all external providers while keeping local application search. Their order in `search.providers` controls the order of result sections. Providers not listed there remain enabled and follow the configured entries alphabetically.


### Opening and closing animations

`animation_open` and `animation_hide` are independent profile objects. Each accepts `effect`: `"none"`, `"fade"`, `"slide"`, `"zoom"`, or `"pop"`. The default is Slide from the top on opening and back towards the top on closing (400 ms flight, followed by a short spring settling on opening). Missing profile members retain defaults; selecting another effect does not discard its saved tuning. Edit configuration and use `--reload`.

```json
{
  "animation_open": {
    "effect": "slide",
    "fade": { "duration_ms": 180 },
    "slide": { "direction": "top", "duration_ms": 400 },
    "zoom": { "scale_percent": 85, "duration_ms": 200 },
    "pop": { "scale_percent": 85, "damping_percent": 65, "stiffness": 300 }
  },
  "animation_hide": { "effect": "slide", "slide": { "direction": "top", "duration_ms": 400 } }
}
```

Merge these members into the existing configuration, not over the tile layout. Both profiles support the same fields. Durations are 0–2000 ms (0 is immediate), Slide travel is calculated automatically to the selected usable-screen edge; legacy `slide.distance` is preserved but ignored. Direction is `left`, `right`, `top`, or `bottom` (entry side on opening, exit side on closing). Zoom/Pop scale is 50–100 percent. Pop uses a real libadwaita spring: damping ratio is `damping_percent / 100` (30–200), stiffness is 50–1200, mass is fixed at 1; settling time follows the physics, not a duration setting. Integer bounds are enforced when loading; invalid member types keep defaults.

Slide moves the **whole menu from/to the selected usable-screen edge, without fading or scaling**. Opening finishes its timed flight up to 16 logical pixels past the destination, then a real libadwaita spring settles the translation (damping ratio 0.5, mass 1, stiffness 400). Settling adds time beyond `duration_ms`; closing is a timed flight without a spring. When a floating profile uses Slide, a transparent usable-output surface hosts the menu at its panel-aware resting position; the surrounding area passes clicks through. Other profiles keep their normal behavior. Switching mid-animation to Slide immediately restores full opacity/scale and continues from the current displacement. There is no cross-monitor flight or guaranteed overlap of Waybar: the usable edge excludes reserved panel space. Without a Slide profile, effects remain inside the native menu surface (spring overshoot can be clipped, and its native shadow is suppressed during transitions). System-disabled animations and `none` are immediate. Repeated toggles retarget current visuals without resetting the search or rebuilding tiles during reversal. `--describe` includes profile values and additive `metadata.object_properties`; external settings-editor support for nested profiles is not verified.

### Layout, migration, and limits

The first configuration is generated from installed visible applications: categories with at least two applications become folders. Other applications are added as small tiles. Groups retain their names, order, tiles and folders separately when saving. Missing/hidden apps are omitted and removed on the next layout save. Empty and single-item folders are retained.

In `all` mode, applications absent from saved groups appear as transient entries in the unnamed Applications group, without being pinned. Creating/renaming groups does not pin the entire catalog. Explicitly moving/resizing a tile or putting it in a folder saves (pins) it. In `pinned` mode only saved `groups` entries are displayed; the existing saved layout already counts as pinned. Tile and application-list context menus offer launcher pin/unpin separately from Dock. Unpinned apps remain in the catalog in `all`, disappear from tiles in `pinned`, and remain searchable/listed in either mode.

Groups are separated by titles and spacing, without their own backgrounds. Header actions appear on hover or keyboard focus: rename the group, create an empty folder, or add a group with `+`. In an empty layout `+` remains visible. Convert folder to group replaces a folder with a new group bearing its name and all its applications. Move to group context-menu actions move tiles/folders between groups. Drag-and-drop works within and across groups: move tiles and entire folders, insert apps into another group's folder, or extract apps from an open folder. Previews do not mutate config; successful drops commit both groups with one save, while cancellation preserves the baseline. Tile size and folder contents are retained. Moving the last entry automatically removes the emptied source group, including menu moves and converting its last folder into a group. Intentionally created empty groups are retained for later additions. Drops are rejected without changes if the destination already has a same-named folder or any of the moved apps. Folder names must be unique within a group. Dragging a launcher tile or folder reveals a New group drop zone after the last group. Dropping there creates a group and moves the entry without duplication; cancellation creates nothing. The new group is named Group and can be renamed using its header. An empty tail of approximately half the visible tile viewport is permanently reserved after the last group, so it can be scrolled into view before dragging. The zone label and border are only visible during dragging. Holding a dragged tile near the tile-area edge smoothly scrolls in that direction; dropping or leaving the area stops auto-scrolling.

For a Windows 10-like structure use `launcher_mode: "combined"`, `tile_mode: "pinned"`, `group_layout: "vertical"`, `app_list_side: "left"`. For Windows 8.1-inspired horizontal groups use `group_layout: "horizontal"` in either tile mode. Apply configuration edits with `--reload`. Horizontal groups fill downward within the actual allocated tile-area height, then grow columns to the right and shift later groups. Tile scrolling is horizontal only; the height accounts for search, headers and floating/fullscreen window geometry. In this layout `max_columns` does not cap group growth; `cell_size` controls cell size (shrinking in very short areas to fit a large tile). Open folders expand into a separate panel to the right of their group's tiles, also height-bounded and growing right. Vertical layout and its folder animations remain unchanged. These are structural options, not pixel-identical Windows themes.

If the launcher config is absent, legacy `ximper-shell/tile-menu/config.json` is copied. Numeric layers, `monitor_index`, and `wofi_width`/`wofi_height` are migrated and saved during loading. Defaults in the table describe scalar settings; `groups` depend on installed applications. Metadata ranges from `--describe` are advisory, not loader validation: `max_columns` metadata is 0–20, floating dimensions 1–10000, while the runtime limits above apply. Positive column limits are not capped at 18. Position presets additionally fit the requested size to the monitor; custom placement does not. `output` selection applies only to floating windows. Fullscreen uses whole-output anchoring; floating respects reserved panel space (exclusive zone 0 versus fullscreen -1).

A wallpaper must be an absolute path to a regular local file. When active, it replaces the ordinary background, so `background_opacity` has no effect; use wallpaper opacity/dimming instead.

### Search and application history

Local fuzzy matching examines display name, GenericName, Comment, desktop ID, Keywords, and Categories—not every desktop-file field or Exec. Search is debounced by 200 ms. Provider sections precede local applications; providers are queried concurrently, with at most four active jobs per search manager (including cancelled jobs still finishing). Remaining jobs wait in FIFO order. Within each job, ID and metadata requests remain sequential, with a 500 ms timeout per D-Bus call and up to five result IDs per provider. New queries cancel older batches and purge stale queued jobs; late cancelled responses cannot update the cache. Only the current uncancelled batch replaces the previous-query cache. Provider sections retain configured order rather than response order. List replacement remains atomic after the batch completes: results are not streamed, and the slowest provider can still delay final display. Tiles mode shows at most eight local search results; Wofi and combined do not impose that limit. Provider headers open the full provider search; activation uses SearchProvider2 with full-search fallback. Results with `clipboardText` copy that text to the clipboard.

Relevance combines match score and recorded launch frequency. Counts are stored in `$XDG_DATA_HOME/ximper-shell/launcher/launch-history.json` (normally `~/.local/share/...`). Launches and desktop actions from the application list are recorded; tile launches are not. This is not a log of all successfully launched applications. Local list rows, like tiles, offer desktop actions and Dock pin/unpin when available. The app catalog uses GIO's visibility rules and monitors installed entries; reopen or reload to refresh the displayed layout/list after changes.

### Custom CSS

Create `~/.config/ximper-shell/launcher/style.css` to change the menu appearance without modifying installed files. This stylesheet is loaded with user priority, so its rules override the bundled stylesheet. Restart the launcher after editing it; `--reload` does not reload stylesheets.

The bundled [`data/ximper-shell-launcher.css`](data/ximper-shell-launcher.css) is a useful starting point. Some legacy rules remain unused; the expanded-folder background uses `.folder-drop-zone`. On an installed system it is normally available as `/etc/xdg/ximper-shell/launcher/style.css`.

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

Useful selectors include `.grid-overlay`, `.grid-overlay.floating`, `.window-background`, `.tile`, `.tile-name`, `.search-entry`, `.search-result-row`, `.folder-drop-zone`, and `.wallpaper-dimmer`. GTK/libadwaita theme colors such as `@window_bg_color`, `@card_bg_color`, and `@accent_bg_color` follow the active system theme.

Base CSS lookup order is `$XDG_DATA_HOME/ximper-shell-launcher/ximper-shell-launcher.css`, `/etc/xdg/ximper-shell/launcher/style.css`, then source-tree CSS resolved through `/proc/self/exe`. User config CSS overrides it; legacy `~/.config/ximper-shell/tile-menu/style.css` is used only if launcher user CSS is absent.

## Architecture

- [`src/application.vala`](src/application.vala): GApplication lifecycle, CLI/D-Bus, configuration and integrations.
- [`src/config.vala`](src/config.vala), [`src/config-types.vala`](src/config-types.vala), [`src/describe.vala`](src/describe.vala): persistence, models, and metadata.
- `src/window/`: shared window, combined list/tiles view, geometry, wallpaper background and popover navigation.
- `src/tiles/`: custom TileBoard allocation, ordered occupancy packing (mixed spans), TileModel mutations, drag candidate previews, folder animation and tile widgets. Drag targets exclude source/gap, previews deep-copy layout, drag icons are frozen, and rebuilding waits for drag completion.
- `src/search/`: shared virtualized Gtk.ListView, ordering/Unicode headings, query orchestration, SearchProvider2 and loading indicator.
- `src/integration/`: GIO app catalog/launching, bounded asynchronous icon loading, Dock client and launch counts.
- `src/compositor/`, `src/tools/`, `src/input/`: monitor lookup, layer-shell and gamepad support.
- `data/` and `po/`: GTK CSS and gettext translations (Russian supplied).

## Gamepad

Gamepad support via libmanette. A toast notification appears when a gamepad is connected.

| Button | Action |
|--------|--------|
| D-pad / Left stick | Navigate tiles, lists, or context menus |
| A (South) | Activate tile / select menu item |
| B (East) | Back (close folder / close popover / close menu) |
| X (North) | Open context menu on focused tile/local application row |
| Xbox / Guide | Toggle launcher |
| LB / RB | Scroll up / down |

Hold D-pad or stick for continuous navigation. Guide does not toggle the launcher while a process named `steam` is running. Start and Y have no assigned action. The connection toast is emitted for newly connected devices, not devices already present at startup.

## D-Bus

`ru.ximperlinux.shell.Launcher` at `/ru/ximperlinux/shell/Launcher`:
- `Toggle()` — show/hide launcher
- `Reload()` — reread the configuration file and apply changes without restarting

## License

GPLv3 — see [LICENSE](LICENSE).
