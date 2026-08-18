namespace XimperShellLauncher {

    public class SearchProviderInfo {
        public string bus_name;
        public string object_path;
        public string desktop_id;
        public string? name;
        public Icon? icon;

        public SearchProviderInfo (string bus_name, string object_path, string desktop_id) {
            this.bus_name = bus_name;
            this.object_path = object_path;
            this.desktop_id = desktop_id;
        }
    }

    public class SearchResult {
        public string id;
        public string name;
        public string? description;
        public string? clipboard_text;
        public Icon? icon;
        public SearchProviderInfo provider;

        public SearchResult (string id, string name, SearchProviderInfo provider) {
            this.id = id;
            this.name = name;
            this.provider = provider;
        }
    }
}
