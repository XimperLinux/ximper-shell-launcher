namespace XimperShellTileMenu {

    [CCode (cname = "setsid", cheader_filename = "unistd.h")]
    private static extern int c_setsid ();

    public class AppEntry : Object {

        public string desktop_id { get; private set; }
        public string name { get; private set; }
        public string? generic_name { get; private set; }
        public Icon? icon { get; private set; }
        public string? categories { get; private set; }
        public string[]? keywords { get; private set; }

        private DesktopAppInfo app_info;

        public AppEntry (DesktopAppInfo info) {
            this.app_info = info;
            this.desktop_id = info.get_id () ?? info.get_filename ();
            this.name = info.get_display_name () ?? info.get_name ();
            this.generic_name = info.get_generic_name ();
            this.icon = info.get_icon ();
            this.categories = info.get_categories ();
            this.keywords = info.get_keywords ();
        }

        public bool launch () {
            // DBusActivatable — launch via D-Bus, process owned by dbus/systemd
            if (app_info.get_boolean ("DBusActivatable")) {
                try {
                    var bus_name = desktop_id.replace (".desktop", "");
                    var object_path = "/" + bus_name.replace (".", "/");
                    var conn = Bus.get_sync (BusType.SESSION, null);
                    conn.call_sync (
                        bus_name, object_path,
                        "org.freedesktop.Application", "Activate",
                        new Variant.tuple ({ new Variant ("a{sv}", null) }),
                        null, DBusCallFlags.NONE, 2000, null
                    );
                    return true;
                } catch (Error e) {
                    // D-Bus activation failed, fall through to spawn
                }
            }

            // Fallback — spawn with setsid so child survives panel death
            try {
                var context = Gdk.Display.get_default ().get_app_launch_context ();
                return app_info.launch_uris_as_manager (
                    null, context,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
                    () => { c_setsid (); },
                    null
                );
            } catch (Error e) {
                warning ("Failed to launch %s: %s", name, e.message);
                return false;
            }
        }

        public string[] list_actions () {
            return app_info.list_actions ();
        }

        public string get_action_name (string action_id) {
            return app_info.get_action_name (action_id);
        }

        public void launch_action (string action_id) {
            try {
                var keyfile = new KeyFile ();
                keyfile.load_from_file (app_info.get_filename (), KeyFileFlags.NONE);
                var group = "Desktop Action " + action_id;
                if (!keyfile.has_group (group)) return;

                var exec_line = keyfile.get_string (group, "Exec");
                exec_line = strip_field_codes (exec_line);

                string[] argv;
                Shell.parse_argv (exec_line, out argv);
                Process.spawn_async (
                    null, argv, null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
                    () => { c_setsid (); },
                    null
                );
            } catch (Error e) {
                warning ("Failed to launch action %s for %s: %s", action_id, name, e.message);
            }
        }

        private static string strip_field_codes (string exec) {
            var result = new StringBuilder ();
            for (int i = 0; i < exec.length; i++) {
                if (exec[i] == '%' && i + 1 < exec.length) {
                    var code = exec[i + 1];
                    if ("uUfFickdDnNvm".contains (code.to_string ())) {
                        i++;
                        continue;
                    }
                }
                result.append_c (exec[i]);
            }
            return result.str.strip ();
        }

        public bool matches (string query) {
            var q = query.down ();

            if (name.down ().contains (q)) return true;
            if (generic_name != null && generic_name.down ().contains (q)) return true;
            if (categories != null && categories.down ().contains (q)) return true;

            if (keywords != null) {
                foreach (var kw in keywords) {
                    if (kw.down ().contains (q)) return true;
                }
            }

            return false;
        }
    }
}
