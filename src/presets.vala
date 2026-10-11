namespace XimperShellLauncher {
    // Presets are one-shot layout generators, not stored profiles.
    public class Presets : Object {
        public static bool is_valid (string name) {
            return name == "8.1" || name == "10" || name == "ximper" || name == "wofi";
        }

        public static string list_description () {
            return _("8.1 — fullscreen category tiles\n10 — floating list with System and Internet tiles\nximper — fullscreen category folders\nwofi — compact floating application list\nApplying a preset replaces the current tile layout.\n");
        }

        private static bool has_category (AppEntry app, string category) {
            if (app.categories == null) return false;
            foreach (string item in app.categories.split (";"))
                if (item == category) return true;
            return false;
        }

        private static int category_index (AppEntry app) {
            // One first-match bucket per app, with System taking precedence.
            string[] system = { "System", "Settings", "TerminalEmulator", "FileManager" };
            foreach (string category in system)
                if (has_category (app, category)) return 0;
            string[] categories = { "Network", "Office", "Graphics", "AudioVideo", "Game", "Development", "Education", "Science", "Utility" };
            for (int i = 0; i < categories.length; i++)
                if (has_category (app, categories[i])) return i + 1;
            return 10;
        }

        private static Json.Object button (string type, string label, string icon) {
            var obj = new Json.Object ();
            obj.set_string_member ("type", type);
            obj.set_string_member ("label", label);
            obj.set_string_member ("icon", icon);
            return obj;
        }

        private static void add_button (Json.Array array, Json.Object obj) {
            var node = new Json.Node (Json.NodeType.OBJECT);
            node.set_object (obj);
            array.add_element (node);
        }

        private static Json.Object folder_button (string label, string icon, string path) {
            var obj = button ("folder", label, icon);
            obj.set_string_member ("path", path);
            obj.set_boolean_member ("close_launcher", true);
            return obj;
        }

        private static Json.Object command_button (string label, string icon, string[] argv) {
            var obj = button ("command", label, icon);
            var args = new Json.Array ();
            foreach (string arg in argv) args.add_string_element (arg);
            obj.set_array_member ("argv", args);
            obj.set_boolean_member ("confirm", true);
            obj.set_boolean_member ("close_launcher", true);
            return obj;
        }

        private static Json.Object? settings_button () {
            if (Environment.find_program_in_path ("tuner") == null) return null;
            var obj = button ("command", _("Settings"), "preferences-system-symbolic");
            var argv = new Json.Array ();
            argv.add_string_element ("tuner");
            obj.set_array_member ("argv", argv);
            obj.set_boolean_member ("close_launcher", true);
            return obj;
        }

        private static Json.Object profile_button (bool include_settings) {
            string label = Environment.get_real_name ();
            if (label == "" || label == "Unknown") label = Environment.get_user_name ();
            var obj = button ("menu", label, "avatar-default-symbolic");
            var items = new Json.Array ();
            add_button (items, folder_button (_("Home"), "user-home-symbolic", "~"));
            if (include_settings) {
                var settings = settings_button ();
                if (settings != null) add_button (items, settings);
            }
            if (Environment.find_program_in_path ("loginctl") != null) {
                add_button (items, command_button (_("Lock"), "system-lock-screen-symbolic", { "loginctl", "lock-session" }));
                // Resolve the session at activation, never freeze its ID in a
                // persistent preset or pass a shell variable as literal argv.
                add_button (items, command_button (_("Sign out"), "system-log-out-symbolic",
                    { "sh", "-c", ": \"${XDG_SESSION_ID:?}\"; exec loginctl terminate-session \"$XDG_SESSION_ID\"" }));
            }
            obj.set_array_member ("items", items);
            return obj;
        }

        private static Json.Object power_button () {
            var obj = button ("menu", _("Power"), "system-shutdown-symbolic");
            var items = new Json.Array ();
            add_button (items, command_button (_("Sleep"), "weather-clear-night-symbolic", { "systemctl", "suspend" }));
            add_button (items, command_button (_("Restart"), "system-reboot-symbolic", { "systemctl", "reboot" }));
            add_button (items, command_button (_("Power off"), "system-shutdown-symbolic", { "systemctl", "poweroff" }));
            obj.set_array_member ("items", items);
            return obj;
        }

        private static SidebarConfig preset_sidebar (string name) {
            if (name != "10" && name != "8.1") return new SidebarConfig ();
            var obj = new Json.Object ();
            obj.set_boolean_member ("enabled", true);
            obj.set_string_member ("position", name == "10" ? "left" : "in-search");
            obj.set_boolean_member ("show_labels", name == "8.1");
            obj.set_int_member ("background_opacity", 0);
            var start = new Json.Array ();
            var end = new Json.Array ();
            add_button (end, profile_button (name == "8.1"));
            if (name == "10") {
                var documents = Environment.get_user_special_dir (UserDirectory.DOCUMENTS);
                var pictures = Environment.get_user_special_dir (UserDirectory.PICTURES);
                if (documents != null) add_button (end, folder_button (_("Documents"), "folder-documents-symbolic", documents));
                if (pictures != null) add_button (end, folder_button (_("Pictures"), "folder-pictures-symbolic", pictures));
                var settings = settings_button ();
                if (settings != null) add_button (end, settings);
            }
            if (Environment.find_program_in_path ("systemctl") != null) add_button (end, power_button ());
            obj.set_array_member ("start", start);
            obj.set_array_member ("end", end);
            return SidebarConfig.preset_template (obj);
        }

        public static bool apply (string name, ConfigManager config, GenericArray<AppEntry> apps) {
            if (!is_valid (name)) return false;
            string[] labels = { _("System"), _("Internet"), _("Office"), _("Graphics"), _("Multimedia"), _("Games"), _("Development"), _("Education"), _("Science"), _("Utilities"), _("Other") };
            var sorted = new GenericArray<AppEntry> ();
            for (uint i = 0; i < apps.length; i++) sorted.add (apps[i]);
            sorted.sort ((a, b) => {
                int result = a.name.collate (b.name);
                return result != 0 ? result : strcmp (a.desktop_id, b.desktop_id);
            });
            var buckets = new GenericArray<GroupConfig> ();
            foreach (string label in labels) buckets.add (new GroupConfig (label));
            var seen = new HashTable<string, bool> (str_hash, str_equal);
            for (uint i = 0; i < sorted.length; i++) {
                var app = sorted[i];
                if (seen.contains (app.desktop_id)) continue;
                seen.insert (app.desktop_id, true);
                int bucket = category_index (app);
                if (name == "10" && bucket > 1) continue;
                buckets[bucket].tiles.add (new TileConfig (app.desktop_id, TileSize.SMALL));
            }
            var groups = new GenericArray<GroupConfig> ();
            bool folders = name == "ximper" || name == "wofi";
            var flat = new GroupConfig ("");
            for (uint i = 0; i < buckets.length; i++) {
                var bucket = buckets[i];
                if (bucket.tiles.length == 0) continue;
                if (!folders) {
                    groups.add (bucket);
                } else if (bucket.tiles.length >= 2 && i != 10) {
                    var items = new GenericArray<string> ();
                    for (uint j = 0; j < bucket.tiles.length; j++)
                        items.add (bucket.tiles[j].desktop_id);
                    flat.tiles.add (new TileConfig.folder (bucket.name, items));
                } else {
                    for (uint j = 0; j < bucket.tiles.length; j++) flat.tiles.add (bucket.tiles[j]);
                }
            }
            if (folders) groups.add (flat);
            config.groups = groups;
            config.groups_enabled = !folders;
            config.max_columns = 0;
            config.cell_size = name == "8.1" ? 150 : name == "10" ? 100 : 0;
            config.tile_icon_size = name == "8.1" ? 64 : name == "10" ? 48 : 0;
            config.tile_square_labels = name == "8.1" || name == "10";
            config.group_layout = name == "8.1" ? GroupLayout.HORIZONTAL : GroupLayout.VERTICAL;
            config.tile_mode = folders ? TileMode.ALL : TileMode.PINNED;
            config.launcher_mode = name == "10" ? LauncherMode.COMBINED : name == "wofi" ? LauncherMode.WOFI : LauncherMode.TILES;
            config.window_mode = name == "10" || name == "wofi" ? WindowMode.FLOATING : WindowMode.FULLSCREEN;
            if (name == "10" || name == "wofi") {
                config.floating_position = name == "10" ? FloatingPosition.BOTTOM_LEFT : FloatingPosition.CENTER;
                config.floating_width = name == "10" ? 1000 : 640;
                config.floating_height = name == "10" ? 760 : 520;
                config.floating_margin = 16;
                config.floating_x = 0;
                config.floating_y = 0;
                config.floating_x_percent = 50;
                config.floating_y_percent = 50;
            }
            if (name == "10") config.app_list_side = AppListSide.LEFT;
            if (config.sidebar.follows_preset ()) config.sidebar = preset_sidebar (name);
            return true;
        }
    }
}
