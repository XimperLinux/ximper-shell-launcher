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

    public enum FloatingPosition {
        CUSTOM,
        TOP_LEFT,
        TOP,
        TOP_RIGHT,
        LEFT,
        CENTER,
        RIGHT,
        BOTTOM_LEFT,
        BOTTOM,
        BOTTOM_RIGHT;

        public static FloatingPosition from_string (string value) {
            switch (value) {
                case "top-left": return TOP_LEFT;
                case "top": return TOP;
                case "top-right": return TOP_RIGHT;
                case "left": return LEFT;
                case "center": return CENTER;
                case "right": return RIGHT;
                case "bottom-left": return BOTTOM_LEFT;
                case "bottom": return BOTTOM;
                case "bottom-right": return BOTTOM_RIGHT;
                default: return CUSTOM;
            }
        }

        public string to_string () {
            switch (this) {
                case TOP_LEFT: return "top-left";
                case TOP: return "top";
                case TOP_RIGHT: return "top-right";
                case LEFT: return "left";
                case CENTER: return "center";
                case RIGHT: return "right";
                case BOTTOM_LEFT: return "bottom-left";
                case BOTTOM: return "bottom";
                case BOTTOM_RIGHT: return "bottom-right";
                default: return "custom";
            }
        }

        public int horizontal_alignment () {
            switch (this) {
                case TOP_LEFT: case LEFT: case BOTTOM_LEFT: return -1;
                case TOP_RIGHT: case RIGHT: case BOTTOM_RIGHT: return 1;
                default: return 0;
            }
        }

        public int vertical_alignment () {
            switch (this) {
                case TOP_LEFT: case TOP: case TOP_RIGHT: return -1;
                case BOTTOM_LEFT: case BOTTOM: case BOTTOM_RIGHT: return 1;
                default: return 0;
            }
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
