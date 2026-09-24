project('ximper-shell-launcher', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.62.0',
)

i18n = import('i18n')

conf = configuration_data()
conf.set_quoted('GETTEXT_PACKAGE', meson.project_name())
conf.set_quoted('LOCALEDIR', get_option('prefix') / get_option('localedir'))
configure_file(output: 'config.h', configuration: conf)

subdir('src')

exec_test = executable('launcher-exec-test',
  files('tests/exec-test.vala', 'src/integration/app-info.vala'),
  dependencies: [dependency('gtk4'), dependency('gio-unix-2.0')],
)
test('desktop-entry-exec', exec_test)

subdir('data')
subdir('po')
