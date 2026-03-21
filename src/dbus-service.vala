namespace XimperShellTileMenu {

    [DBus (name = "ru.ximperlinux.shell.TileMenu")]
    public class GridDBusService : Object {

        private weak Application app;

        public GridDBusService (Application app) {
            this.app = app;
        }

        public void toggle () throws DBusError, IOError {
            app.toggle_grid ();
        }
    }
}
