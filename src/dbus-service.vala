namespace XimperShellLauncher {

    [DBus (name = "ru.ximperlinux.shell.Launcher")]
    public class LauncherDBusService : Object {

        private weak Application app;

        public LauncherDBusService (Application app) {
            this.app = app;
        }

        public void toggle () throws DBusError, IOError {
            app.toggle_grid ();
        }

        public void reload () throws DBusError, IOError {
            app.reload_config ();
        }
    }
}
