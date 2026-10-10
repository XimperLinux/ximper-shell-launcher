namespace XimperShellLauncher {
    // Static signal helpers capture this holder rather than an implicit Vala
    // method/async frame, which otherwise retains its owner (or a freed frame).
    internal class SidebarWeakReference : Object {
        private WeakRef reference;
        public SidebarWeakReference (Object owner) {
            reference = WeakRef (null);
            reference.set (owner);
        }
        public new Object? get () { return reference.get (); }
    }

    public enum SidebarPosition {
        LEFT, RIGHT, ABOVE_SEARCH, BELOW_SEARCH;

        public string to_string () {
            switch (this) {
                case RIGHT: return "right";
                case ABOVE_SEARCH: return "above-search";
                case BELOW_SEARCH: return "below-search";
                default: return "left";
            }
        }
        public static SidebarPosition from_string (string value) {
            switch (value) {
                case "right": return RIGHT;
                case "above-search": return ABOVE_SEARCH;
                case "below-search": return BELOW_SEARCH;
                default: return LEFT;
            }
        }
    }

    public enum SidebarItemKind { INVALID, COMMAND, APPLICATION, FOLDER, MENU, SEPARATOR }

    public class SidebarItem : Object {
        public SidebarItemKind kind = SidebarItemKind.INVALID;
        public string label = "";
        public string icon = "";
        public string desktop_id = "";
        public string path = "";
        public string cwd = "";
        public string[] argv = {};
        public bool confirm;
        public bool close_launcher;
        public bool valid;
        public GenericArray<SidebarItem> items = new GenericArray<SidebarItem> ();
        private Json.Node source;

        public static SidebarItem read (Json.Node node, int depth = 0) {
            var item = new SidebarItem ();
            item.source = node.copy ();
            if (node.get_node_type () != Json.NodeType.OBJECT) return item;
            var obj = node.get_object ();
            item.label = SidebarConfig.text (obj, "label", "");
            item.icon = SidebarConfig.text (obj, "icon", "");
            item.confirm = SidebarConfig.flag (obj, "confirm", false);
            item.close_launcher = SidebarConfig.flag (obj, "close_launcher", false);
            switch (SidebarConfig.text (obj, "type", "")) {
                case "command":
                    item.kind = SidebarItemKind.COMMAND;
                    item.cwd = SidebarConfig.text (obj, "cwd", "");
                    var args = SidebarConfig.member (obj, "argv");
                    if (args == null || args.get_node_type () != Json.NodeType.ARRAY) break;
                    var array = args.get_array ();
                    string[] argv = {};
                    bool correct = array.get_length () > 0;
                    for (uint i = 0; i < array.get_length (); i++) {
                        var arg = array.get_element (i);
                        if (arg.get_node_type () != Json.NodeType.VALUE || arg.get_value_type () != typeof (string)) {
                            correct = false;
                            break;
                        }
                        argv += arg.get_string ();
                    }
                    item.argv = argv;
                    item.valid = correct && argv.length > 0 && argv[0].strip ().length > 0 &&
                        (item.cwd == "" || local_path (item.cwd) != null);
                    break;
                case "application":
                    item.kind = SidebarItemKind.APPLICATION;
                    item.desktop_id = SidebarConfig.text (obj, "desktop_id", "");
                    item.valid = item.desktop_id.has_suffix (".desktop") && !item.desktop_id.contains ("/");
                    break;
                case "folder":
                    item.kind = SidebarItemKind.FOLDER;
                    item.path = SidebarConfig.text (obj, "path", "");
                    item.valid = local_path (item.path) != null;
                    break;
                case "menu":
                    item.kind = SidebarItemKind.MENU;
                    var children = SidebarConfig.member (obj, "items");
                    if (depth >= 8 || children == null || children.get_node_type () != Json.NodeType.ARRAY) break;
                    var entries = children.get_array ();
                    for (uint i = 0; i < entries.get_length (); i++)
                        item.items.add (read (entries.get_element (i), depth + 1));
                    item.valid = item.items.length > 0;
                    break;
                case "separator":
                    item.kind = SidebarItemKind.SEPARATOR;
                    item.valid = true;
                    break;
            }
            // An explicitly mistyped confirmation must not silently turn into
            // an unconfirmed command; fail closed while retaining the record.
            item.valid = item.valid && optional_type (obj, "label", typeof (string)) &&
                optional_type (obj, "icon", typeof (string)) &&
                optional_type (obj, "confirm", typeof (bool)) &&
                optional_type (obj, "close_launcher", typeof (bool)) &&
                (item.kind != SidebarItemKind.COMMAND || optional_type (obj, "cwd", typeof (string)));
            return item;
        }

        private static bool optional_type (Json.Object obj, string name, Type type) {
            var value = SidebarConfig.member (obj, name);
            return value == null || (value.get_node_type () == Json.NodeType.VALUE && value.get_value_type () == type);
        }

        public string display_label () {
            if (label != "") return label;
            if (kind == SidebarItemKind.APPLICATION) {
                var info = new DesktopAppInfo (desktop_id);
                if (info != null) return info.get_display_name ();
            }
            return _("Action");
        }

        public Icon get_icon () {
            if (icon != "") {
                if (Path.is_absolute (icon) || icon.has_prefix ("~/")) {
                    var local = local_path (icon);
                    if (local != null) return new FileIcon (File.new_for_path (local));
                } else return new ThemedIcon (icon);
            }
            if (kind == SidebarItemKind.APPLICATION) {
                var info = new DesktopAppInfo (desktop_id);
                if (info != null && info.get_icon () != null) return info.get_icon ();
            }
            if (kind == SidebarItemKind.FOLDER) return new ThemedIcon ("folder-symbolic");
            if (kind == SidebarItemKind.MENU) return new ThemedIcon ("view-more-symbolic");
            return new ThemedIcon ("system-run-symbolic");
        }

        public void serialize (Json.Builder builder) { builder.add_value (source.copy ()); }

        public static string? local_path (string value) {
            if (value == "~") return Environment.get_home_dir ();
            if (value.has_prefix ("~/")) return Path.build_filename (Environment.get_home_dir (), value.substring (2));
            return Path.is_absolute (value) ? value : null;
        }
    }

    public class SidebarConfig : Object {
        public bool enabled;
        public SidebarPosition position = SidebarPosition.LEFT;
        public bool show_labels;
        public int background_opacity;
        public int width;
        public int height;
        public int icon_size = 24;
        public int button_height = 44;
        public int spacing = 4;
        public int padding = 6;
        public GenericArray<SidebarItem> start_items = new GenericArray<SidebarItem> ();
        public GenericArray<SidebarItem> end_items = new GenericArray<SidebarItem> ();
        private Json.Node? source;
        public bool horizontal { get { return position == SidebarPosition.ABOVE_SEARCH || position == SidebarPosition.BELOW_SEARCH; } }
        public int thickness { get { return horizontal ? (height > 0 ? height : button_height + 2 * padding) :
            (width > 0 ? width : (show_labels ? 200 : 56)); } }

        internal static unowned Json.Node? member (Json.Object obj, string name) {
            return obj.has_member (name) ? obj.get_member (name) : null;
        }
        internal static string text (Json.Object obj, string name, string fallback) {
            var node = member (obj, name);
            return node != null && node.get_node_type () == Json.NodeType.VALUE && node.get_value_type () == typeof (string)
                ? node.get_string () : fallback;
        }
        internal static bool flag (Json.Object obj, string name, bool fallback) {
            var node = member (obj, name);
            return node != null && node.get_node_type () == Json.NodeType.VALUE && node.get_value_type () == typeof (bool)
                ? node.get_boolean () : fallback;
        }
        private static int number (Json.Object obj, string name, int fallback, int maximum) {
            var node = member (obj, name);
            if (node == null || node.get_node_type () != Json.NodeType.VALUE) return fallback;
            var type = node.get_value_type ();
            if (type != typeof (int64) && type != typeof (double)) return fallback;
            double value = type == typeof (double) ? node.get_double () : (double) node.get_int ();
            return (int) value.clamp (0, maximum);
        }

        public static SidebarConfig read (Json.Node? node) {
            var config = new SidebarConfig ();
            if (node == null) return config;
            config.source = node.copy ();
            if (node.get_node_type () != Json.NodeType.OBJECT) return config;
            var obj = node.get_object ();
            config.enabled = flag (obj, "enabled", false);
            config.position = SidebarPosition.from_string (text (obj, "position", "left"));
            config.show_labels = flag (obj, "show_labels", false);
            config.background_opacity = number (obj, "background_opacity", 0, 100);
            config.width = number (obj, "width", 0, 400);
            if (config.width > 0) config.width = int.max (40, config.width);
            config.height = number (obj, "height", 0, 160);
            if (config.height > 0) config.height = int.max (32, config.height);
            config.icon_size = int.max (8, number (obj, "icon_size", 24, 64));
            config.button_height = int.max (24, number (obj, "button_height", 44, 96));
            config.spacing = number (obj, "spacing", 4, 32);
            config.padding = number (obj, "padding", 6, 24);
            read_section (obj, "start", config.start_items);
            read_section (obj, "end", config.end_items);
            return config;
        }

        private static void read_section (Json.Object obj, string key, GenericArray<SidebarItem> items) {
            var node = member (obj, key);
            if (node == null || node.get_node_type () != Json.NodeType.ARRAY) return;
            var entries = node.get_array ();
            for (uint i = 0; i < entries.get_length (); i++) items.add (SidebarItem.read (entries.get_element (i)));
        }

        public void serialize (Json.Builder builder, bool preserve_source = true) {
            // Retain unrecognized and malformed user data, including sections,
            // when unrelated tile operations save the entire config.
            if (source != null && preserve_source) { builder.add_value (source.copy ()); return; }
            builder.begin_object ();
            builder.set_member_name ("enabled"); builder.add_boolean_value (enabled);
            builder.set_member_name ("position"); builder.add_string_value (position.to_string ());
            builder.set_member_name ("show_labels"); builder.add_boolean_value (show_labels);
            builder.set_member_name ("background_opacity"); builder.add_int_value (background_opacity);
            builder.set_member_name ("width"); builder.add_int_value (width);
            builder.set_member_name ("height"); builder.add_int_value (height);
            builder.set_member_name ("icon_size"); builder.add_int_value (icon_size);
            builder.set_member_name ("button_height"); builder.add_int_value (button_height);
            builder.set_member_name ("spacing"); builder.add_int_value (spacing);
            builder.set_member_name ("padding"); builder.add_int_value (padding);
            builder.set_member_name ("start"); builder.begin_array ();
            for (uint i = 0; i < start_items.length; i++) start_items[i].serialize (builder);
            builder.end_array ();
            builder.set_member_name ("end"); builder.begin_array ();
            for (uint i = 0; i < end_items.length; i++) end_items[i].serialize (builder);
            builder.end_array ();
            builder.end_object ();
        }
    }
}
