namespace XimperShellTileMenu {

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

    public class SearchProviderManager : Object {

        public GenericArray<SearchProviderInfo> providers;

        private const string PROVIDERS_DIR = "/usr/share/gnome-shell/search-providers";
        private const int SEARCH_TIMEOUT_MS = 500;

        public SearchProviderManager () {
            providers = new GenericArray<SearchProviderInfo> ();
        }

        public void scan_providers () {
            providers = new GenericArray<SearchProviderInfo> ();

            try {
                var dir = Dir.open (PROVIDERS_DIR);
                string? filename;
                while ((filename = dir.read_name ()) != null) {
                    if (filename.has_suffix (".ini")) {
                        load_provider (Path.build_filename (PROVIDERS_DIR, filename));
                    }
                }
            } catch (Error e) {
                warning ("Failed to scan search providers: %s", e.message);
            }
        }

        private void load_provider (string path) {
            try {
                var keyfile = new KeyFile ();
                keyfile.load_from_file (path, KeyFileFlags.NONE);

                var group = "Shell Search Provider";

                var bus_name = keyfile.get_string (group, "BusName");
                var object_path = keyfile.get_string (group, "ObjectPath");
                var desktop_id = keyfile.get_string (group, "DesktopId");

                var info = new SearchProviderInfo (bus_name, object_path, desktop_id);

                // Try to get the provider name from its desktop file
                var app_info = new DesktopAppInfo (desktop_id);
                if (app_info != null) {
                    info.name = app_info.get_display_name ();
                    info.icon = app_info.get_icon ();
                } else {
                    info.name = bus_name;
                }

                providers.add (info);
            } catch (Error e) {
                warning ("Failed to load search provider %s: %s", path, e.message);
            }
        }

        // Cache previous results per provider for subsearch
        private HashTable<string, GenericArray<string>> prev_results =
            new HashTable<string, GenericArray<string>> (str_hash, str_equal);
        private string? prev_query = null;

        public async GenericArray<SearchResult> search (string query, Cancellable? cancellable = null) {
            var all_results = new GenericArray<SearchResult> ();
            var terms = query.split (" ");
            bool is_subsearch = prev_query != null && query.has_prefix (prev_query) && query != prev_query;

            for (uint i = 0; i < providers.length; i++) {
                var provider = providers[i];

                if (cancellable != null && cancellable.is_cancelled ()) break;

                try {
                    GenericArray<string>? prev_ids = null;
                    if (is_subsearch) {
                        prev_ids = prev_results.lookup (provider.bus_name);
                    }

                    var results = yield search_provider (provider, terms, prev_ids, cancellable);
                    for (uint j = 0; j < results.length; j++) {
                        all_results.add (results[j]);
                    }
                } catch (Error e) {
                    // Provider unavailable or timed out, skip
                }
            }

            prev_query = query;
            return all_results;
        }

        public void reset_search () {
            prev_results.remove_all ();
            prev_query = null;
        }

        private async GenericArray<SearchResult> search_provider (
            SearchProviderInfo provider,
            string[] terms,
            GenericArray<string>? previous_ids,
            Cancellable? cancellable
        ) throws Error {
            var results = new GenericArray<SearchResult> ();

            var conn = yield Bus.get (BusType.SESSION, cancellable);

            Variant? ids_variant;

            if (previous_ids != null && previous_ids.length > 0) {
                // GetSubsearchResultSet — refine previous results
                var prev_builder = new VariantBuilder (new VariantType ("as"));
                for (uint i = 0; i < previous_ids.length; i++) {
                    if (previous_ids[i] != null)
                        prev_builder.add ("s", previous_ids[i]);
                }
                var terms_builder = new VariantBuilder (new VariantType ("as"));
                foreach (var t in terms) {
                    if (t != null) terms_builder.add ("s", t);
                }

                var subsearch_params = new Variant.tuple ({
                    prev_builder.end (),
                    terms_builder.end ()
                });

                ids_variant = yield call_with_timeout (
                    conn, provider.bus_name, provider.object_path,
                    "org.gnome.Shell.SearchProvider2",
                    "GetSubsearchResultSet",
                    subsearch_params,
                    cancellable
                );
            } else {
                // GetInitialResultSet
                var terms_builder = new VariantBuilder (new VariantType ("as"));
                foreach (var t in terms) {
                    if (t != null) terms_builder.add ("s", t);
                }
                var terms_tuple = new Variant.tuple ({terms_builder.end ()});

                ids_variant = yield call_with_timeout (
                    conn, provider.bus_name, provider.object_path,
                    "org.gnome.Shell.SearchProvider2",
                    "GetInitialResultSet",
                    terms_tuple,
                    cancellable
                );
            }

            if (ids_variant == null) return results;

            var ids_iter = ids_variant.get_child_value (0).iterator ();
            var ids = new GenericArray<string> ();
            string id;
            while (ids_iter.next ("s", out id)) {
                if (id == null) continue;
                ids.add (id.validate () ? id : id.make_valid ());
                if (ids.length >= 5) break;
            }

            // Cache for subsearch
            prev_results.insert (provider.bus_name, ids);

            if (ids.length == 0) return results;

            // GetResultMetas — build (as) tuple
            var ids_builder = new VariantBuilder (new VariantType ("as"));
            for (uint i = 0; i < ids.length; i++) {
                if (ids[i] != null) ids_builder.add ("s", ids[i]);
            }
            var ids_tuple = new Variant.tuple ({ids_builder.end ()});

            var metas_variant = yield call_with_timeout (
                conn, provider.bus_name, provider.object_path,
                "org.gnome.Shell.SearchProvider2",
                "GetResultMetas",
                ids_tuple,
                cancellable
            );

            if (metas_variant == null) return results;

            var metas_array = metas_variant.get_child_value (0);
            for (size_t i = 0; i < metas_array.n_children (); i++) {
                var meta = metas_array.get_child_value (i);

                string? result_id = null;
                string? result_name = null;
                string? result_desc = null;
                string? result_clipboard = null;
                Icon? result_icon = null;

                var meta_iter = meta.iterator ();
                string key;
                Variant val;
                while (meta_iter.next ("{sv}", out key, out val)) {
                    switch (key) {
                        case "id":
                            if (val.is_of_type (VariantType.STRING))
                                result_id = safe_string (val.get_string ());
                            break;
                        case "name":
                            if (val.is_of_type (VariantType.STRING))
                                result_name = safe_string (val.get_string ());
                            break;
                        case "description":
                            if (val.is_of_type (VariantType.STRING))
                                result_desc = safe_string (val.get_string ());
                            break;
                        case "clipboardText":
                            if (val.is_of_type (VariantType.STRING))
                                result_clipboard = safe_string (val.get_string ());
                            break;
                        case "gicon":
                        case "icon":
                            if (val.is_of_type (VariantType.STRING)) {
                                var icon_str = val.get_string ();
                                if (icon_str != null && icon_str.validate ()) {
                                    try {
                                        result_icon = Icon.new_for_string (icon_str);
                                    } catch (Error e) {}
                                }
                            }
                            break;
                    }
                }

                if (result_id != null && result_name != null) {
                    var result = new SearchResult (result_id, result_name, provider);
                    result.description = result_desc;
                    result.clipboard_text = result_clipboard;
                    result.icon = result_icon ?? provider.icon;
                    results.add (result);
                }
            }

            return results;
        }

        public async void launch_search (SearchProviderInfo provider, string[] terms) {
            try {
                var conn = yield Bus.get (BusType.SESSION, null);

                var terms_builder = new VariantBuilder (new VariantType ("as"));
                foreach (var t in terms) {
                    if (t != null) terms_builder.add ("s", t);
                }

                var params = new Variant.tuple ({
                    terms_builder.end (),
                    new Variant.uint32 ((uint32) Gdk.CURRENT_TIME)
                });

                yield conn.call (
                    provider.bus_name,
                    provider.object_path,
                    "org.gnome.Shell.SearchProvider2",
                    "LaunchSearch",
                    params,
                    null,
                    DBusCallFlags.NONE,
                    SEARCH_TIMEOUT_MS,
                    null
                );
            } catch (Error e) {
                var app_info = new DesktopAppInfo (provider.desktop_id);
                if (app_info != null) {
                    try { app_info.launch (null, null); } catch (Error e2) {}
                }
            }
        }

        public async void activate_result (SearchResult result, string[] terms) {
            try {
                var conn = yield Bus.get (BusType.SESSION, null);

                var terms_builder = new VariantBuilder (new VariantType ("as"));
                foreach (var t in terms) {
                    if (t != null) terms_builder.add ("s", t);
                }

                var params = new Variant.tuple ({
                    safe_variant_string (result.id),
                    terms_builder.end (),
                    new Variant.uint32 ((uint32) Gdk.CURRENT_TIME)
                });

                yield conn.call (
                    result.provider.bus_name,
                    result.provider.object_path,
                    "org.gnome.Shell.SearchProvider2",
                    "ActivateResult",
                    params,
                    null,
                    DBusCallFlags.NONE,
                    SEARCH_TIMEOUT_MS,
                    null
                );
            } catch (Error e) {
                yield launch_search (result.provider, terms);
            }
        }

        private static string? safe_string (string? s) {
            if (s == null) return null;
            if (s.validate ()) return s;
            return s.make_valid ();
        }

        private static Variant safe_variant_string (string? s) {
            if (s == null || !s.validate ()) {
                return new Variant.string (s != null ? s.make_valid () : "");
            }
            return new Variant.string (s);
        }

        private async Variant? call_with_timeout (
            DBusConnection conn,
            string bus_name,
            string object_path,
            string interface_name,
            string method_name,
            Variant parameters,
            Cancellable? cancellable
        ) throws Error {
            return yield conn.call (
                bus_name,
                object_path,
                interface_name,
                method_name,
                parameters,
                null,
                DBusCallFlags.NONE,
                SEARCH_TIMEOUT_MS,
                cancellable
            );
        }
    }
}
