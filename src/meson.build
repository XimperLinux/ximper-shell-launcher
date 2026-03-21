grid_deps = [
  dependency('gtk4', version: '>= 4.12'),
  dependency('libadwaita-1', version: '>= 1.4'),
  dependency('gtk4-layer-shell-0', version: '>= 1.0'),
  dependency('json-glib-1.0'),
  dependency('gio-unix-2.0'),
]

grid_sources = files(
  'main.vala',
  'application.vala',
  'config.vala',
  'app-info.vala',
  'app-provider.vala',
  'settings-window.vala',
  'grid-window.vala',
  'tile.vala',
  'tile-board.vala',
  'tile-grid.vala',
  'folder-tile.vala',
  'search-bar.vala',
  'search-provider.vala',
  'layer-shell-helper.vala',
  'dock-dbus-client.vala',
  'dbus-service.vala',
)

executable('ximper-shell-tile-menu', grid_sources,
  dependencies: grid_deps,

  install: true,
)
