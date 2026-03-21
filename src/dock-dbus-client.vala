namespace XimperShellTileMenu {

    [DBus (name = "ru.ximperlinux.shell.Dock")]
    public interface DockDBusProxy : Object {
        public abstract string[] get_pinned_apps () throws DBusError, IOError;
        public abstract bool is_pinned (string desktop_id) throws DBusError, IOError;
        public abstract void pin (string desktop_id) throws DBusError, IOError;
        public abstract void unpin (string desktop_id) throws DBusError, IOError;
    }

    public class DockClient : Object {

        private DockDBusProxy? proxy;

        public DockClient () {
            try {
                proxy = Bus.get_proxy_sync (
                    BusType.SESSION,
                    "ru.ximperlinux.shell.Dock",
                    "/ru/ximperlinux/shell/Dock"
                );
            } catch (Error e) {
                proxy = null;
            }
        }

        public bool is_available () {
            return proxy != null;
        }

        public bool is_pinned (string desktop_id) {
            if (proxy == null) return false;
            try {
                return proxy.is_pinned (desktop_id);
            } catch (Error e) {
                return false;
            }
        }

        public void pin (string desktop_id) {
            if (proxy == null) return;
            try {
                proxy.pin (desktop_id);
            } catch (Error e) {
                warning ("Failed to pin via D-Bus: %s", e.message);
            }
        }

        public void unpin (string desktop_id) {
            if (proxy == null) return;
            try {
                proxy.unpin (desktop_id);
            } catch (Error e) {
                warning ("Failed to unpin via D-Bus: %s", e.message);
            }
        }

        public string[] get_pinned_apps () {
            if (proxy == null) return {};
            try {
                return proxy.get_pinned_apps ();
            } catch (Error e) {
                return {};
            }
        }
    }
}
