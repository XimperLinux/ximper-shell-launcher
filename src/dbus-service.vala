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
            try {
                app.reload_config ();
            } catch (Error e) {
                throw new IOError.FAILED (e.message);
            }
        }
    }
}
