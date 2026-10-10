namespace XimperShellLauncher {

    private class ProviderSearchBatch : Object {
        public string query;
        public string[] terms;
        public uint64 generation;
        public Cancellable cancellable = new Cancellable ();
        public GenericArray<ProviderSearchJob> jobs = new GenericArray<ProviderSearchJob> ();
        public uint pending = 0;
        public signal void finished ();
        public ProviderSearchBatch (string query, uint64 generation) {
            this.query = query;
            this.terms = query.split (" ");
            this.generation = generation;
        }
    }

    private class ProviderSearchJob : Object {
        public ProviderSearchBatch batch;
        public SearchProviderInfo provider;
        public GenericArray<string>? previous_ids;
        public GenericArray<string> ids = new GenericArray<string> ();
        public GenericArray<SearchResult> results = new GenericArray<SearchResult> ();
        public bool succeeded = false;
        public ProviderSearchJob (ProviderSearchBatch batch, SearchProviderInfo provider) {
            this.batch = batch;
            this.provider = provider;
        }
    }

    public class SearchProviderManager : Object {

        public GenericArray<SearchProviderInfo> providers;

        private const string PROVIDERS_SUBDIR = "gnome-shell/search-providers";
        private const int SEARCH_TIMEOUT_MS = 500;
        private weak ConfigManager config;

        public SearchProviderManager (ConfigManager config) {
            this.config = config;
            providers = new GenericArray<SearchProviderInfo> ();
        }

        public void scan_providers (bool force = false) {
            providers = new GenericArray<SearchProviderInfo> ();
            if (!force && !config.search_providers_enabled) return;

            var data_dirs = new GenericArray<string> ();
            data_dirs.add (Environment.get_user_data_dir ());
            foreach (var dir in Environment.get_system_data_dirs ()) data_dirs.add (dir);

            for (uint i = 0; i < data_dirs.length; i++) {
                scan_directory (Path.build_filename (data_dirs[i], PROVIDERS_SUBDIR));
            }
            sort_providers ();
        }

        private void scan_directory (string path) {
            try {
                var dir = Dir.open (path);
                string? filename;
                while ((filename = dir.read_name ()) != null) {
                    if (filename.has_suffix (".ini")) load_provider (Path.build_filename (path, filename));
                }
            } catch (FileError e) {
                // The directory is optional in each XDG data directory.
            }
        }

        private void sort_providers () {
            var ordered = new GenericArray<SearchProviderInfo> ();
            for (uint pos = 0; pos < config.search_providers.length; pos++) {
                for (uint i = 0; i < providers.length; i++) {
                    if (providers[i].desktop_id == config.search_providers[pos].id)
                        ordered.add (providers[i]);
                }
            }
            uint first_unconfigured = ordered.length;
            for (uint i = 0; i < providers.length; i++) {
                var provider = providers[i];
                if (config.search_provider_position (provider.desktop_id) >= 0) continue;

                uint insert_at = ordered.length;
                var provider_name = provider.name ?? provider.desktop_id;
                for (uint j = first_unconfigured; j < ordered.length; j++) {
                    var other_name = ordered[j].name ?? ordered[j].desktop_id;
                    if (strcmp (provider_name, other_name) < 0) {
                        insert_at = j;
                        break;
                    }
                }
                ordered.insert ((int) insert_at, provider);
            }
            providers = ordered;
        }

        private void load_provider (string path) {
            try {
                var keyfile = new KeyFile ();
                keyfile.load_from_file (path, KeyFileFlags.NONE);

                var group = "Shell Search Provider";

                var bus_name = keyfile.get_string (group, "BusName");
                var object_path = keyfile.get_string (group, "ObjectPath");
                var desktop_id = keyfile.get_string (group, "DesktopId");

                for (uint i = 0; i < providers.length; i++) {
                    if (providers[i].desktop_id == desktop_id) return;
                }

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

        private const uint MAX_ACTIVE_JOBS = 4;
        private uint active_jobs = 0;
        private uint64 generation = 0;
        private ProviderSearchBatch? current_batch;
        private GenericArray<ProviderSearchJob> queue = new GenericArray<ProviderSearchJob> ();
        private bool pumping = false;

        private bool is_current (ProviderSearchBatch batch) {
            return batch.generation == generation && !batch.cancellable.is_cancelled ();
        }

        private void settle_job (ProviderSearchJob job) {
            if (--job.batch.pending == 0) {
                var batch = job.batch;
                // Defer even synchronous completion until search reaches yield.
                Idle.add (() => { batch.finished (); return Source.REMOVE; });
            }
        }

        private void pump_queue () {
            if (pumping) return;
            pumping = true;
            uint i = 0;
            while (i < queue.length) {
                var job = queue[i];
                if (!is_current (job.batch)) {
                    queue.remove_index (i);
                    settle_job (job);
                    continue;
                }
                if (active_jobs >= MAX_ACTIVE_JOBS) { i++; continue; }
                queue.remove_index (i);
                active_jobs++;
                search_provider.begin (job, (obj, res) => {
                    try {
                        job.results = search_provider.end (res);
                        job.succeeded = true;
                    } catch (Error e) {
                        // Provider unavailable or timed out, skip.
                    }
                    active_jobs--;
                    settle_job (job);
                    pump_queue ();
                });
            }
            pumping = false;
        }

        public async GenericArray<SearchResult> search (string query, Cancellable? cancellable = null) {
            if (current_batch != null) current_batch.cancellable.cancel ();
            var batch = new ProviderSearchBatch (query, ++generation);
            current_batch = batch;
            ulong cancel_handler = 0;
            if (cancellable != null) {
                cancel_handler = cancellable.connect (() => {
                    batch.cancellable.cancel ();
                    // External cancellation may originate off the main thread.
                    Idle.add (() => { pump_queue (); return Source.REMOVE; });
                });
            }
            bool is_subsearch = prev_query != null && query.has_prefix (prev_query) && query != prev_query;
            if (config.search_providers_enabled) {
                for (uint i = 0; i < providers.length; i++) {
                    var provider = providers[i];
                    if (!config.is_search_provider_enabled (provider.desktop_id)) continue;
                    var job = new ProviderSearchJob (batch, provider);
                    if (is_subsearch) {
                        var cached = prev_results.lookup (provider.bus_name);
                        if (cached != null) {
                            job.previous_ids = new GenericArray<string> ();
                            for (uint j = 0; j < cached.length; j++) job.previous_ids.add (cached[j]);
                        }
                    }
                    batch.jobs.add (job);
                    queue.add (job);
                    batch.pending++;
                }
            }
            ulong finished_handler = batch.finished.connect (() => { search.callback (); });
            if (batch.pending == 0)
                Idle.add (() => { batch.finished (); return Source.REMOVE; });
            pump_queue ();
            yield;
            batch.disconnect (finished_handler);
            if (cancellable != null && cancel_handler != 0) cancellable.disconnect (cancel_handler);
            var all_results = new GenericArray<SearchResult> ();
            if (is_current (batch)) {
                prev_results.remove_all ();
                // Aggregate by configured slots rather than response order.
                for (uint i = 0; i < batch.jobs.length; i++) {
                    var job = batch.jobs[i];
                    if (!job.succeeded) continue;
                    prev_results.insert (job.provider.bus_name, job.ids);
                    for (uint j = 0; j < job.results.length; j++) all_results.add (job.results[j]);
                }
                prev_query = batch.query;
            }
            if (current_batch == batch) current_batch = null;
            // Break ownership cycles after all callbacks have settled.
            batch.jobs.remove_range (0, batch.jobs.length);
            return all_results;
        }

        public void reset_search () {
            generation++;
            if (current_batch != null) current_batch.cancellable.cancel ();
            current_batch = null;
            prev_results.remove_all ();
            prev_query = null;
            pump_queue ();
        }

        private async GenericArray<SearchResult> search_provider (ProviderSearchJob job) throws Error {
            var provider = job.provider;
            var cancellable = job.batch.cancellable;
            var results = new GenericArray<SearchResult> ();

            var conn = yield Bus.get (BusType.SESSION, cancellable);

            Variant? ids_variant;

            if (job.previous_ids != null && job.previous_ids.length > 0) {
                // GetSubsearchResultSet — refine previous results
                var prev_builder = new VariantBuilder (new VariantType ("as"));
                for (uint i = 0; i < job.previous_ids.length; i++) {
                    if (job.previous_ids[i] != null)
                        prev_builder.add ("s", job.previous_ids[i]);
                }
                var terms_builder = new VariantBuilder (new VariantType ("as"));
                foreach (var t in job.batch.terms) {
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
                foreach (var t in job.batch.terms) {
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

            // Job-local until the current batch commits after metadata.
            job.ids = ids;

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
                    // Values in a{sv} are variant-wrapped. Unwrap them before
                    // checking their type so clipboardText is not ignored.
                    var actual_val = val;
                    if (actual_val.is_of_type (VariantType.VARIANT))
                        actual_val = actual_val.get_variant ();

                    switch (key) {
                        case "id":
                            if (actual_val.is_of_type (VariantType.STRING))
                                result_id = safe_string (actual_val.get_string ());
                            break;
                        case "name":
                            if (actual_val.is_of_type (VariantType.STRING))
                                result_name = safe_string (actual_val.get_string ());
                            break;
                        case "description":
                            if (actual_val.is_of_type (VariantType.STRING))
                                result_desc = safe_string (actual_val.get_string ());
                            break;
                        case "clipboardText":
                            if (actual_val.is_of_type (VariantType.STRING))
                                result_clipboard = safe_string (actual_val.get_string ());
                            break;
                        case "gicon":
                        case "icon":
                            if (actual_val.is_of_type (VariantType.STRING)) {
                                var icon_str = actual_val.get_string ();
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

        public async void launch_search (
            SearchProviderInfo provider,
            owned string[] terms,
            uint32 timestamp
        ) {
            try {
                var conn = yield Bus.get (BusType.SESSION, null);

                var terms_builder = new VariantBuilder (new VariantType ("as"));
                foreach (var t in terms) {
                    if (t != null) terms_builder.add ("s", t);
                }

                var params = new Variant.tuple ({
                    terms_builder.end (),
                    new Variant.uint32 (timestamp)
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
                warning ("Failed to launch provider search for %s: %s", provider.bus_name, e.message);
            }
        }

        public async void activate_result (
            SearchResult result,
            owned string[] terms,
            uint32 timestamp
        ) {
            try {
                var conn = yield Bus.get (BusType.SESSION, null);

                var terms_builder = new VariantBuilder (new VariantType ("as"));
                foreach (var t in terms) {
                    if (t != null) terms_builder.add ("s", t);
                }

                var params = new Variant.tuple ({
                    safe_variant_string (result.id),
                    terms_builder.end (),
                    new Variant.uint32 (timestamp)
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
                yield launch_search (result.provider, terms, timestamp);
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
