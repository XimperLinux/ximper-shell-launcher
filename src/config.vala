namespace XimperShellTileMenu {

    public enum LauncherMode {
        TILES,
        WOFI;

        public static LauncherMode from_string (string val) {
            return val == "wofi" ? WOFI : TILES;
        }

        public string to_string () {
            return this == WOFI ? "wofi" : "tiles";
        }
    }

    public enum WindowMode {
        FULLSCREEN,
        FLOATING;

        public static WindowMode from_string (string val) {
            if (val == "floating") return FLOATING;
            return FULLSCREEN;
        }

        public string to_string () {
            if (this == FLOATING) return "floating";
            return "fullscreen";
        }
    }

    public enum TileSize {
        SMALL,
        MEDIUM,
        LARGE,
        FOLDER;

        public static TileSize from_string (string val) {
            switch (val) {
                case "medium": return MEDIUM;
                case "large": return LARGE;
                case "folder": return FOLDER;
                default: return SMALL;
            }
        }

        public string to_string () {
            switch (this) {
                case MEDIUM: return "medium";
                case LARGE: return "large";
                case FOLDER: return "folder";
                default: return "small";
            }
        }
    }

    public class TileConfig {
        public string desktop_id;
        public TileSize size;
        public GenericArray<string>? folder_items;
        public string? folder_name;

        public TileConfig (string desktop_id, TileSize size) {
            this.desktop_id = desktop_id;
            this.size = size;
        }

        public TileConfig.folder (string name, GenericArray<string> items) {
            this.desktop_id = "folder:" + name;
            this.size = TileSize.FOLDER;
            this.folder_name = name;
            this.folder_items = items;
        }
    }

    public class GroupConfig {
        public string name;
        public GenericArray<TileConfig> tiles;

        public GroupConfig (string name) {
            this.name = name;
            this.tiles = new GenericArray<TileConfig> ();
        }
    }

    public class ConfigManager : Object {

        public int max_columns { get; set; default = 0; }
        public int cell_size { get; set; default = 0; }
        public string layer { get; set; default = "overlay"; }
        public LauncherMode launcher_mode { get; set; default = LauncherMode.TILES; }
        public WindowMode window_mode { get; set; default = WindowMode.FULLSCREEN; }
        public int floating_x { get; set; default = 0; }
        public int floating_y { get; set; default = 24; }
        public int floating_width { get; set; default = 960; }
        public int floating_height { get; set; default = 720; }
        public int wofi_width { get; set; default = 600; }
        public int wofi_height { get; set; default = 640; }
        public int floating_x_percent { get; set; default = 0; }
        public int floating_y_percent { get; set; default = 0; }
        public int monitor_index { get; set; default = -1; }
        public string wallpaper_path { get; set; default = ""; }
        public int wallpaper_fit { get; set; default = 2; }
        public int wallpaper_opacity { get; set; default = 100; }
        public int wallpaper_dim { get; set; default = 0; }
        public int background_opacity { get; set; default = 100; }
        public GenericArray<GroupConfig> groups;

        private string config_path;

        public ConfigManager () {
            groups = new GenericArray<GroupConfig> ();

            config_path = Path.build_filename (
                Environment.get_user_config_dir (), "ximper-shell", "tile-menu", "config.json"
            );
        }

        public void load () {
            if (!FileUtils.test (config_path, FileTest.EXISTS)) {
                create_default ();
                return;
            }

            try {
                var parser = new Json.Parser ();
                parser.load_from_file (config_path);

                var root = parser.get_root ().get_object ();
                bool config_migrated = false;

                if (root.has_member ("max_columns"))
                    max_columns = (int) root.get_int_member ("max_columns");
                if (root.has_member ("cell_size"))
                    cell_size = (int) root.get_int_member ("cell_size");
                if (root.has_member ("layer")) {
                    var layer_node = root.get_member ("layer");
                    if (layer_node.get_value_type () == typeof (string))
                        layer = LayerShellHelper.normalize_layer_name (layer_node.get_string ());
                    else {
                        layer = LayerShellHelper.layer_name_from_legacy ((int) layer_node.get_int ());
                        config_migrated = true;
                    }
                }
                if (root.has_member ("launcher_mode"))
                    launcher_mode = LauncherMode.from_string (root.get_string_member ("launcher_mode"));
                if (root.has_member ("window_mode"))
                    window_mode = WindowMode.from_string (root.get_string_member ("window_mode"));
                if (root.has_member ("floating_x"))
                    floating_x = (int) root.get_int_member ("floating_x");
                if (root.has_member ("floating_y"))
                    floating_y = (int) root.get_int_member ("floating_y");
                if (root.has_member ("floating_width"))
                    floating_width = (int) root.get_int_member ("floating_width");
                if (root.has_member ("floating_height"))
                    floating_height = (int) root.get_int_member ("floating_height");
                if (root.has_member ("wofi_width"))
                    wofi_width = (int) root.get_int_member ("wofi_width");
                if (root.has_member ("wofi_height"))
                    wofi_height = (int) root.get_int_member ("wofi_height");
                if (root.has_member ("floating_x_percent"))
                    floating_x_percent = (int) root.get_int_member ("floating_x_percent");
                if (root.has_member ("floating_y_percent"))
                    floating_y_percent = (int) root.get_int_member ("floating_y_percent");
                if (root.has_member ("monitor_index"))
                    monitor_index = (int) root.get_int_member ("monitor_index");
                if (root.has_member ("wallpaper_path"))
                    wallpaper_path = root.get_string_member ("wallpaper_path");
                if (root.has_member ("wallpaper_fit"))
                    wallpaper_fit = (int) root.get_int_member ("wallpaper_fit");
                if (root.has_member ("wallpaper_opacity"))
                    wallpaper_opacity = (int) root.get_int_member ("wallpaper_opacity");
                if (root.has_member ("wallpaper_dim"))
                    wallpaper_dim = (int) root.get_int_member ("wallpaper_dim");
                if (root.has_member ("background_opacity"))
                    background_opacity = (int) root.get_int_member ("background_opacity");

                if (root.has_member ("groups")) {
                    groups = new GenericArray<GroupConfig> ();
                    var arr = root.get_array_member ("groups");
                    arr.foreach_element ((array, i, node) => {
                        var gobj = node.get_object ();
                        var group = new GroupConfig (gobj.get_string_member ("name"));

                        if (gobj.has_member ("tiles")) {
                            gobj.get_array_member ("tiles").foreach_element ((a2, j, tnode) => {
                                var tobj = tnode.get_object ();
                                var size = TileSize.from_string (tobj.get_string_member ("size"));
                                var tile = new TileConfig (
                                    tobj.get_string_member ("desktop_id"), size
                                );
                                if (tobj.has_member ("folder_name")) {
                                    tile.folder_name = tobj.get_string_member ("folder_name");
                                }
                                if (tobj.has_member ("folder_items")) {
                                    tile.folder_items = new GenericArray<string> ();
                                    tobj.get_array_member ("folder_items").foreach_element ((a3, k, fnode) => {
                                        tile.folder_items.add (fnode.get_string ());
                                    });
                                }
                                group.tiles.add (tile);
                            });
                        }

                        groups.add (group);
                    });
                }
                if (config_migrated) save ();
            } catch (Error e) {
                warning ("Failed to load config: %s", e.message);
                create_default ();
            }
        }

        public void save () {
            var builder = new Json.Builder ();

            builder.begin_object ();

            builder.set_member_name ("max_columns");
            builder.add_int_value (max_columns);
            builder.set_member_name ("cell_size");
            builder.add_int_value (cell_size);
            builder.set_member_name ("layer");
            builder.add_string_value (LayerShellHelper.normalize_layer_name (layer));
            builder.set_member_name ("launcher_mode");
            builder.add_string_value (launcher_mode.to_string ());
            builder.set_member_name ("window_mode");
            builder.add_string_value (window_mode.to_string ());
            builder.set_member_name ("floating_x");
            builder.add_int_value (floating_x);
            builder.set_member_name ("floating_y");
            builder.add_int_value (floating_y);
            builder.set_member_name ("floating_width");
            builder.add_int_value (floating_width);
            builder.set_member_name ("floating_height");
            builder.add_int_value (floating_height);
            builder.set_member_name ("wofi_width");
            builder.add_int_value (wofi_width);
            builder.set_member_name ("wofi_height");
            builder.add_int_value (wofi_height);
            builder.set_member_name ("floating_x_percent");
            builder.add_int_value (floating_x_percent);
            builder.set_member_name ("floating_y_percent");
            builder.add_int_value (floating_y_percent);
            builder.set_member_name ("monitor_index");
            builder.add_int_value (monitor_index);
            builder.set_member_name ("wallpaper_path");
            builder.add_string_value (wallpaper_path);
            builder.set_member_name ("wallpaper_fit");
            builder.add_int_value (wallpaper_fit);
            builder.set_member_name ("wallpaper_opacity");
            builder.add_int_value (wallpaper_opacity);
            builder.set_member_name ("wallpaper_dim");
            builder.add_int_value (wallpaper_dim);
            builder.set_member_name ("background_opacity");
            builder.add_int_value (background_opacity);
            builder.set_member_name ("groups");
            builder.begin_array ();
            if (groups == null) groups = new GenericArray<GroupConfig> ();
            for (uint i = 0; i < groups.length; i++) {
                var group = groups[i];
                builder.begin_object ();
                builder.set_member_name ("name");
                builder.add_string_value (group.name);
                builder.set_member_name ("tiles");
                builder.begin_array ();
                for (uint j = 0; j < group.tiles.length; j++) {
                    var tile = group.tiles[j];
                    builder.begin_object ();
                    builder.set_member_name ("desktop_id");
                    builder.add_string_value (tile.desktop_id);
                    builder.set_member_name ("size");
                    builder.add_string_value (tile.size.to_string ());
                    if (tile.folder_name != null) {
                        builder.set_member_name ("folder_name");
                        builder.add_string_value (tile.folder_name);
                    }
                    if (tile.folder_items != null) {
                        builder.set_member_name ("folder_items");
                        builder.begin_array ();
                        for (uint k = 0; k < tile.folder_items.length; k++) {
                            builder.add_string_value (tile.folder_items[k]);
                        }
                        builder.end_array ();
                    }
                    builder.end_object ();
                }
                builder.end_array ();
                builder.end_object ();
            }
            builder.end_array ();

            builder.end_object ();

            var generator = new Json.Generator ();
            generator.set_root (builder.get_root ());
            generator.pretty = true;
            generator.indent = 2;

            try {
                var dir = Path.get_dirname (config_path);
                DirUtils.create_with_parents (dir, 0755);
                generator.to_file (config_path);
            } catch (Error e) {
                warning ("Failed to save config: %s", e.message);
            }
        }

        private void create_default () {
            groups = new GenericArray<GroupConfig> ();

            var category_map = new HashTable<string, string> (str_hash, str_equal);
            category_map.insert ("Game", _("Games"));
            category_map.insert ("Network", _("Internet"));
            category_map.insert ("WebBrowser", _("Internet"));
            category_map.insert ("Email", _("Internet"));
            category_map.insert ("Chat", _("Internet"));
            category_map.insert ("InstantMessaging", _("Internet"));
            category_map.insert ("Graphics", _("Graphics"));
            category_map.insert ("Photography", _("Graphics"));
            category_map.insert ("Audio", _("Multimedia"));
            category_map.insert ("Video", _("Multimedia"));
            category_map.insert ("AudioVideo", _("Multimedia"));
            category_map.insert ("Music", _("Multimedia"));
            category_map.insert ("Player", _("Multimedia"));
            category_map.insert ("Development", _("Development"));
            category_map.insert ("IDE", _("Development"));
            category_map.insert ("TextEditor", _("Development"));
            category_map.insert ("Office", _("Office"));
            category_map.insert ("WordProcessor", _("Office"));
            category_map.insert ("Spreadsheet", _("Office"));
            category_map.insert ("Presentation", _("Office"));
            category_map.insert ("System", _("System"));
            category_map.insert ("Settings", _("System"));
            category_map.insert ("Monitor", _("System"));
            category_map.insert ("TerminalEmulator", _("System"));
            category_map.insert ("FileManager", _("System"));
            category_map.insert ("Utility", _("Utilities"));
            category_map.insert ("Accessibility", _("Utilities"));
            category_map.insert ("Calculator", _("Utilities"));
            category_map.insert ("Archiving", _("Utilities"));
            category_map.insert ("Education", _("Education"));
            category_map.insert ("Science", _("Education"));

            var folders = new HashTable<string, GenericArray<string>> (str_hash, str_equal);
            var assigned = new HashTable<string, bool> (str_hash, str_equal);

            var all_apps = AppInfo.get_all ();
            foreach (var info in all_apps) {
                if (!(info is DesktopAppInfo)) continue;
                var dinfo = (DesktopAppInfo) info;
                if (!dinfo.should_show ()) continue;

                var id = dinfo.get_id () ?? dinfo.get_filename ();
                if (id == null) continue;
                if (assigned.contains (id)) continue;

                var cats = dinfo.get_categories ();
                if (cats == null) continue;

                var cat_list = cats.split (";");
                foreach (var cat in cat_list) {
                    var trimmed = cat.strip ();
                    if (trimmed.length == 0) continue;

                    var folder_name = category_map.lookup (trimmed);
                    if (folder_name != null) {
                        if (!folders.contains (folder_name)) {
                            folders.insert (folder_name, new GenericArray<string> ());
                        }
                        folders.lookup (folder_name).add (id);
                        assigned.insert (id, true);
                        break;
                    }
                }
            }

            var main_group = new GroupConfig (_("Apps"));

            var folder_names = new GenericArray<string> ();
            folders.foreach ((name, items) => {
                if (items.length >= 2) {
                    folder_names.add (name);
                }
            });

            for (uint i = 0; i < folder_names.length; i++) {
                var fname = folder_names[i];
                var items = folders.lookup (fname);
                var tc = new TileConfig.folder (fname, items);
                main_group.tiles.add (tc);
            }

            groups.add (main_group);

            save ();
        }
    }
}
