namespace XimperShellLauncher {

    [CCode (cname = "setsid", cheader_filename = "unistd.h")]
    private static extern int c_setsid ();

    public class AppEntry : Object {

        public string desktop_id { get; private set; }
        public string name { get; private set; }
        public string? generic_name { get; private set; }
        public string? description { get; private set; }
        public Icon? icon { get; private set; }
        public string? categories { get; private set; }
        public string[]? keywords { get; private set; }

        private DesktopAppInfo app_info;

        public AppEntry (DesktopAppInfo info) {
            this.app_info = info;
            this.desktop_id = info.get_id () ?? info.get_filename ();
            this.name = info.get_display_name () ?? info.get_name ();
            this.generic_name = info.get_generic_name ();
            this.description = info.get_description ();
            this.icon = info.get_icon ();
            this.categories = info.get_categories ();
            this.keywords = info.get_keywords ();
        }

        public bool launch () {
            // Use GIO's desktop-file parsing and the asynchronous D-Bus result
            // instead of constructing the bus name or object path ourselves.
            // For Exec launches retain setsid so apps survive the launcher.
            if (has_dbus_activation ()) {
                activate_dbus_async.begin ();
                return true;
            }
            return launch_with_gio (app_info);
        }

        private bool has_dbus_activation () {
            if (!app_info.get_boolean ("DBusActivatable")) return false;
            var filename = app_info.get_filename ();
            if (filename == null) return false;
            var basename = Path.get_basename (filename);
            if (!basename.has_suffix (".desktop")) return false;
            var bus_name = basename.substring (0, basename.length - ".desktop".length);
            return !bus_name.has_prefix (":") && DBus.is_name (bus_name);
        }

        private bool launch_with_gio (DesktopAppInfo info) {
            try {
                var display = Gdk.Display.get_default ();
                AppLaunchContext? context = display != null ? display.get_app_launch_context () : null;
                return info.launch_uris_as_manager (
                    new List<string> (), context, SpawnFlags.SEARCH_PATH,
                    () => { c_setsid (); }, null
                );
            } catch (Error e) {
                warning ("Failed to launch %s: %s", name, e.message);
                return false;
            }
        }

        private async void activate_dbus_async () {
            try {
                var display = Gdk.Display.get_default ();
                AppLaunchContext? context = display != null ? display.get_app_launch_context () : null;
                yield app_info.launch_uris_async (new List<string> (), context);
            } catch (Error e) {
                warning ("D-Bus activation failed for %s: %s; falling back to Exec", desktop_id, e.message);
                launch_exec_fallback ();
            }
        }

        private bool launch_exec_fallback () {
            var filename = app_info.get_filename ();
            if (filename == null) {
                warning ("Cannot fall back to Exec for %s: no desktop file", desktop_id);
                return false;
            }
            try {
                var keyfile = new KeyFile ();
                keyfile.load_from_file (filename, KeyFileFlags.NONE);
                // from_keyfile() has no filename, so GIO would drop %k.
                // Expand only that field code against the original desktop file.
                if (keyfile.has_key ("Desktop Entry", "Exec")) {
                    var exec = keyfile.get_string ("Desktop Entry", "Exec");
                    keyfile.set_string ("Desktop Entry", "Exec", expand_desktop_filename (exec, filename));
                }
                keyfile.set_boolean ("Desktop Entry", "DBusActivatable", false);
                var exec_info = new DesktopAppInfo.from_keyfile (keyfile);
                if (exec_info == null || exec_info.get_commandline () == null) {
                    warning ("Cannot fall back to Exec for %s: Exec is empty", desktop_id);
                    return false;
                }
                return launch_with_gio (exec_info);
            } catch (Error e) {
                warning ("Failed to launch %s via Exec fallback: %s", name, e.message);
                return false;
            }
        }

        private static string expand_desktop_filename (string exec, string filename) {
            var result = new StringBuilder ();
            for (int i = 0; i < exec.length; i++) {
                if (exec[i] == '%' && i + 1 < exec.length) {
                    if (exec[i + 1] == '%') {
                        result.append ("%%");
                        i++;
                        continue;
                    }
                    if (exec[i + 1] == 'k') {
                        result.append (Shell.quote (filename));
                        i++;
                        continue;
                    }
                }
                result.append_c (exec[i]);
            }
            return result.str;
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
                    SpawnFlags.SEARCH_PATH,
                    () => { c_setsid (); },
                    null
                );
            } catch (Error e) {
                warning ("Failed to launch action %s for %s: %s", action_id, name, e.message);
            }
        }

        public static string strip_field_codes (string exec) {
            var result = new StringBuilder ();
            for (int i = 0; i < exec.length; i++) {
                if (exec[i] == '%' && i + 1 < exec.length) {
                    var code = exec[i + 1];
                    if (code == '%') {
                        result.append_c ('%');
                        i++;
                        continue;
                    }
                    if ("uUfFickdDnNvm".contains (code.to_string ())) {
                        i++;
                        continue;
                    }
                }
                result.append_c (exec[i]);
            }
            return result.str.strip ();
        }

        // Returns relevance score (0 = no match, higher = better).
        public int match_score (string query) {
            var q = query.down ();
            int best = 0;

            // Name — highest weight
            best = int.max (best, fuzzy_score (name.down (), q) * 10);
            // Generic name
            if (generic_name != null)
                best = int.max (best, fuzzy_score (generic_name.down (), q) * 6);
            // Description (Comment field)
            if (description != null)
                best = int.max (best, fuzzy_score (description.down (), q) * 4);
            // Desktop ID (e.g. "org.gnome.Nautilus.desktop")
            best = int.max (best, fuzzy_score (desktop_id.down (), q) * 3);
            // Keywords
            if (keywords != null) {
                foreach (var kw in keywords) {
                    best = int.max (best, fuzzy_score (kw.down (), q) * 5);
                }
            }
            // Categories
            if (categories != null)
                best = int.max (best, fuzzy_score (categories.down (), q) * 2);

            return best;
        }

        // Fuzzy score: 0 = no match.
        // 100 = exact match, 90 = prefix, 70 = contains,
        // 1..60 = subsequence (higher = more consecutive).
        private static int fuzzy_score (string text, string query) {
            if (text == query) return 100;
            if (text.has_prefix (query)) return 90;
            if (text.contains (query)) return 70;

            // Subsequence match: all query chars must appear in order
            int qi = 0;
            int consecutive = 0;
            int max_consecutive = 0;
            int ql = query.length;

            for (int ti = 0; ti < text.length && qi < ql; ti++) {
                if (text[ti] == query[qi]) {
                    qi++;
                    consecutive++;
                    if (consecutive > max_consecutive)
                        max_consecutive = consecutive;
                } else {
                    consecutive = 0;
                }
            }

            if (qi < ql) return 0; // not all chars matched

            // Score based on how consecutive the matches are
            int score = 10 + (max_consecutive * 50 / ql);
            if (score > 60) score = 60;
            return score;
        }

        public bool matches (string query) {
            return match_score (query) > 0;
        }
    }
}
