namespace XimperShellTileMenu {

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

                if (root.has_member ("max_columns"))
                    max_columns = (int) root.get_int_member ("max_columns");

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
            category_map.insert ("Game", "Games");
            category_map.insert ("Network", "Internet");
            category_map.insert ("WebBrowser", "Internet");
            category_map.insert ("Email", "Internet");
            category_map.insert ("Chat", "Internet");
            category_map.insert ("InstantMessaging", "Internet");
            category_map.insert ("Graphics", "Graphics");
            category_map.insert ("Photography", "Graphics");
            category_map.insert ("Audio", "Multimedia");
            category_map.insert ("Video", "Multimedia");
            category_map.insert ("AudioVideo", "Multimedia");
            category_map.insert ("Music", "Multimedia");
            category_map.insert ("Player", "Multimedia");
            category_map.insert ("Development", "Development");
            category_map.insert ("IDE", "Development");
            category_map.insert ("TextEditor", "Development");
            category_map.insert ("Office", "Office");
            category_map.insert ("WordProcessor", "Office");
            category_map.insert ("Spreadsheet", "Office");
            category_map.insert ("Presentation", "Office");
            category_map.insert ("System", "System");
            category_map.insert ("Settings", "System");
            category_map.insert ("Monitor", "System");
            category_map.insert ("TerminalEmulator", "System");
            category_map.insert ("FileManager", "System");
            category_map.insert ("Utility", "Utilities");
            category_map.insert ("Accessibility", "Utilities");
            category_map.insert ("Calculator", "Utilities");
            category_map.insert ("Archiving", "Utilities");
            category_map.insert ("Education", "Education");
            category_map.insert ("Science", "Education");

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

            var main_group = new GroupConfig ("Apps");

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
