namespace XimperShellLauncher {
    public class ApplicationOrdering : Object {
        public static string heading (string name) {
            var trimmed = name.strip ();
            if (trimmed.length == 0) return "#";
            unichar first = trimmed.get_char ();
            return first.isalpha () ? first.toupper ().to_string () : "#";
        }

        public static GenericArray<AppEntry> sorted (GenericArray<AppEntry> apps,
                                                    string query, AppListSort sort,
                                                    LaunchHistory history) {
            var copy = new GenericArray<AppEntry> ();
            for (uint i = 0; i < apps.length; i++) copy.add (apps[i]);
            copy.sort_with_data ((a, b) => {
                if (sort == AppListSort.RELEVANCE) {
                    int pa = priority (a, query, history);
                    int pb = priority (b, query, history);
                    if (pa != pb) return pa > pb ? -1 : 1;
                } else {
                    // Sort by bucket first so a letter always forms one section.
                    int group_order = heading (a.name).collate (heading (b.name));
                    if (group_order != 0) return group_order;
                }
                int by_name = a.name.casefold ().collate (b.name.casefold ());
                return by_name != 0 ? by_name : strcmp (a.desktop_id, b.desktop_id);
            });
            return copy;
        }

        private static int priority (AppEntry entry, string query, LaunchHistory history) {
            int launches = history.get_count (entry.desktop_id).clamp (0, 999);
            return query.length == 0 ? launches : entry.match_score (query) * 1000 + launches;
        }
    }
}
