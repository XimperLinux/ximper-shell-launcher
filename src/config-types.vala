namespace XimperShellLauncher {

    public enum LauncherMode {
        TILES,
        WOFI,
        COMBINED;

        public static LauncherMode from_string (string val) {
            if (val == "combined") return COMBINED;
            return val == "wofi" ? WOFI : TILES;
        }

        public string to_string () {
            if (this == COMBINED) return "combined";
            return this == WOFI ? "wofi" : "tiles";
        }
    }

    public enum AppListSide {
        LEFT,
        RIGHT;

        public static AppListSide from_string (string value) {
            return value == "right" ? RIGHT : LEFT;
        }

        public string to_string () { return this == RIGHT ? "right" : "left"; }
    }

    public enum AppListSort {
        RELEVANCE,
        ALPHABETICAL;

        public static AppListSort from_string (string value) {
            return value == "alphabetical" ? ALPHABETICAL : RELEVANCE;
        }

        public string to_string () { return this == ALPHABETICAL ? "alphabetical" : "relevance"; }
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

    public class SearchProviderConfig {
        public string id;
        public bool enabled;

        public SearchProviderConfig (string id, bool enabled = true) {
            this.id = id;
            this.enabled = enabled;
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
}
