grid_deps = [
  dependency('gtk4', version: '>= 4.12'),
  dependency('libadwaita-1', version: '>= 1.4'),
  dependency('gtk4-layer-shell-0', version: '>= 1.0'),
  dependency('json-glib-1.0'),
  dependency('gio-unix-2.0'),
  dependency('manette-0.2'),
]

grid_sources = files(
  'config.vapi',
  'main.vala',
  'application.vala',
  'config.vala',
  'config-types.vala',
  'describe.vala',
  'dbus-service.vala',

  'window/grid-window.vala',
  'window/window-geometry.vala',
  'window/popover-navigator.vala',
  'window/non-measuring-background.vala',

  'tiles/tile.vala',
  'tiles/folder-tile.vala',
  'tiles/tile-board.vala',
  'tiles/tile-grid.vala',
  'tiles/tile-model.vala',
  'tiles/tile-placement.vala',
  'tiles/folder-animator.vala',

  'search/search-bar.vala',
  'search/search-model.vala',
  'search/search-provider.vala',

  'integration/dock-dbus-client.vala',
  'integration/app-info.vala',
  'integration/app-provider.vala',

  'compositor/compositor-helper.vala',
  'compositor/hyprland-helper.vala',
  'compositor/niri-helper.vala',

  'input/gamepad-controller.vala',

  'tools/layer-shell-helper.vala',
)

executable('ximper-shell-launcher', grid_sources,
  dependencies: grid_deps,
  include_directories: include_directories('..'),
  c_args: ['-DGETTEXT_PACKAGE="ximper-shell-launcher"', '-w'],
  install: true,
)
