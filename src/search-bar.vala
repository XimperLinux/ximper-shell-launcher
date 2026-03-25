namespace XimperShellTileMenu {

    public class SearchBar : Gtk.Box {

        public Gtk.SearchEntry search_entry { get; private set; }
        public Gtk.ScrolledWindow results_widget { get; private set; }

        private weak Application app;
        private SearchProviderManager provider_manager;
        private Gtk.Box results_box;
        private Cancellable? search_cancellable;
        private uint search_timeout_id = 0;

        private const uint DEBOUNCE_MS = 200;

        public signal void result_activated ();
        public signal void search_changed (bool is_searching);

        public SearchBar (Application app) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 12);
            this.app = app;

            add_css_class ("search-bar-container");

            provider_manager = new SearchProviderManager ();
            provider_manager.scan_providers ();

            build_ui ();
        }

        private void build_ui () {
            var clamp = new Adw.Clamp ();
            clamp.maximum_size = 600;
            clamp.margin_top = 24;
            clamp.margin_start = 24;
            clamp.margin_end = 24;

            search_entry = new Gtk.SearchEntry ();
            search_entry.placeholder_text = "Search applications…";
            search_entry.add_css_class ("search-entry");
            search_entry.hexpand = true;

            search_entry.search_changed.connect (() => {
                debounce_search ();
            });

            clamp.set_child (search_entry);
            append (clamp);

            // Results widget — will be added to the stack in GridWindow
            results_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            results_box.add_css_class ("search-results");

            var results_clamp = new Adw.Clamp ();
            results_clamp.maximum_size = 600;
            results_clamp.margin_start = 24;
            results_clamp.margin_end = 24;
            results_clamp.set_child (results_box);

            results_widget = new Gtk.ScrolledWindow ();
            results_widget.vexpand = true;
            results_widget.hscrollbar_policy = Gtk.PolicyType.NEVER;
            results_widget.set_child (results_clamp);
        }

        private void debounce_search () {
            if (search_timeout_id != 0) {
                Source.remove (search_timeout_id);
            }

            search_timeout_id = Timeout.add (DEBOUNCE_MS, () => {
                search_timeout_id = 0;
                perform_search.begin ();
                return Source.REMOVE;
            });
        }

        private async void perform_search () {
            var query = search_entry.text.strip ();

            // Cancel previous search
            if (search_cancellable != null) {
                search_cancellable.cancel ();
            }
            search_cancellable = new Cancellable ();

            clear_results ();

            if (query.length == 0) {
                search_changed (false);
                return;
            }

            search_changed (true);

            // Local app search
            var local_results = app.app_provider.search (query);
            if (local_results.length > 0) {
                add_result_section ("Applications", null);
                for (uint i = 0; i < local_results.length && i < 8; i++) {
                    add_app_result (local_results[i]);
                }
            }

            // GNOME Search Providers
            var my_cancellable = search_cancellable;
            try {
                var provider_results = yield provider_manager.search (query, my_cancellable);

                // Drop stale results if a newer search has started
                if (my_cancellable.is_cancelled ()) return;

                // Group results by provider
                var provider_groups = new GenericArray<GenericArray<SearchResult>> ();
                var provider_keys = new GenericArray<string> ();

                for (uint i = 0; i < provider_results.length; i++) {
                    var result = provider_results[i];
                    var key = result.provider.bus_name;

                    int group_idx = -1;
                    for (uint j = 0; j < provider_keys.length; j++) {
                        if (provider_keys[j] == key) { group_idx = (int) j; break; }
                    }

                    if (group_idx < 0) {
                        provider_keys.add (key);
                        provider_groups.add (new GenericArray<SearchResult> ());
                        group_idx = (int) provider_keys.length - 1;
                    }

                    provider_groups[group_idx].add (result);
                }

                for (uint i = 0; i < provider_groups.length; i++) {
                    var results = provider_groups[i];
                    if (results.length > 0) {
                        var provider_name = results[0].provider.name ?? provider_keys[i];
                        add_result_section (provider_name, results[0].provider.icon);

                        for (uint j = 0; j < results.length; j++) {
                            add_provider_result (results[j], query);
                        }
                    }
                }
            } catch (Error e) {
                // Search cancelled or failed, ignore
            }
        }

        private void clear_results () {
            var child = results_box.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                results_box.remove (child);
                child = next;
            }
        }

        private void add_result_section (string title, Icon? icon) {
            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            header.add_css_class ("search-section-header");
            header.margin_top = 8;

            if (icon != null) {
                var img = new Gtk.Image ();
                img.gicon = icon;
                img.pixel_size = 16;
                header.append (img);
            }

            var label = new Gtk.Label (title);
            label.add_css_class ("search-section-title");
            label.halign = Gtk.Align.START;
            header.append (label);

            results_box.append (header);
        }

        private void add_app_result (AppEntry entry) {
            var row = new Gtk.Button ();
            row.add_css_class ("search-result-row");
            row.add_css_class ("flat");

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            box.margin_start = 8;
            box.margin_end = 8;
            box.margin_top = 6;
            box.margin_bottom = 6;

            var img = new Gtk.Image ();
            if (entry.icon != null) {
                img.gicon = entry.icon;
            } else {
                img.icon_name = "application-x-executable";
            }
            img.pixel_size = 32;
            box.append (img);

            var text_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            text_box.hexpand = true;

            var name_label = new Gtk.Label (entry.name);
            name_label.halign = Gtk.Align.START;
            name_label.ellipsize = Pango.EllipsizeMode.END;
            name_label.add_css_class ("search-result-name");
            text_box.append (name_label);

            var subtitle = entry.generic_name ?? entry.description;
            if (subtitle != null) {
                var desc_label = new Gtk.Label (subtitle);
                desc_label.halign = Gtk.Align.START;
                desc_label.ellipsize = Pango.EllipsizeMode.END;
                desc_label.add_css_class ("search-result-desc");
                desc_label.add_css_class ("dim-label");
                text_box.append (desc_label);
            }

            box.append (text_box);
            row.set_child (box);

            row.clicked.connect (() => {
                entry.launch ();
                result_activated ();
            });

            results_box.append (row);
        }

        private void add_provider_result (SearchResult result, string query) {
            var row = new Gtk.Button ();
            row.add_css_class ("search-result-row");
            row.add_css_class ("flat");

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            box.margin_start = 8;
            box.margin_end = 8;
            box.margin_top = 6;
            box.margin_bottom = 6;

            var img = new Gtk.Image ();
            if (result.icon != null) {
                img.gicon = result.icon;
            } else {
                img.icon_name = "application-x-executable";
            }
            img.pixel_size = 32;
            box.append (img);

            var text_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            text_box.hexpand = true;

            var name_label = new Gtk.Label (result.name);
            name_label.halign = Gtk.Align.START;
            name_label.ellipsize = Pango.EllipsizeMode.END;
            name_label.add_css_class ("search-result-name");
            text_box.append (name_label);

            if (result.description != null) {
                var desc_label = new Gtk.Label (result.description);
                desc_label.halign = Gtk.Align.START;
                desc_label.add_css_class ("search-result-desc");
                desc_label.add_css_class ("dim-label");
                desc_label.ellipsize = Pango.EllipsizeMode.END;
                text_box.append (desc_label);
            }

            box.append (text_box);
            row.set_child (box);

            row.clicked.connect (() => {
                if (result.clipboard_text != null && result.clipboard_text.length > 0) {
                    var clipboard = Gdk.Display.get_default ().get_clipboard ();
                    clipboard.set_text (result.clipboard_text);
                    result_activated ();
                } else {
                    // Capture query as owned string for the timeout closure
                    var saved_query = query + "";
                    var saved_provider = result.provider;
                    // Launch app first to ensure window is created
                    var launch_info = new DesktopAppInfo (saved_provider.desktop_id);
                    if (launch_info != null) {
                        try {
                            var ctx = Gdk.Display.get_default ().get_app_launch_context ();
                            launch_info.launch (null, ctx);
                        } catch (Error e) {}
                    }
                    result_activated ();
                    // Call LaunchSearch directly via synchronous D-Bus
                    try {
                        var conn = Bus.get_sync (BusType.SESSION, null);
                        var terms_builder = new VariantBuilder (new VariantType ("as"));
                        foreach (var t in saved_query.split (" ")) {
                            terms_builder.add ("s", t);
                        }
                        var call_params = new Variant.tuple ({
                            terms_builder.end (),
                            new Variant.uint32 (0)
                        });
                        conn.call_sync (
                            saved_provider.bus_name,
                            saved_provider.object_path,
                            "org.gnome.Shell.SearchProvider2",
                            "LaunchSearch",
                            call_params,
                            null,
                            DBusCallFlags.NONE,
                            2000,
                            null
                        );
                    } catch (Error e) {
                        print ("DEBUG sync LaunchSearch failed: %s\n", e.message);
                    }
                }
            });

            results_box.append (row);
        }

        public bool is_searching () {
            return search_entry.text.strip ().length > 0;
        }

        public void reset () {
            search_entry.text = "";
            clear_results ();
            provider_manager.reset_search ();
        }
    }
}
