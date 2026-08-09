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
            search_entry.placeholder_text = _("Search applications…");
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
                add_result_section (_("Applications"), null);
                for (uint i = 0; i < local_results.length && i < 8; i++) {
                    add_app_result (local_results[i]);
                }
            }

            // GNOME Search Providers
            var my_cancellable = search_cancellable;
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
                    add_result_section (
                        provider_name,
                        results[0].provider.icon,
                        results[0].provider
                    );

                    for (uint j = 0; j < results.length; j++) {
                        add_provider_result (results[j]);
                    }
                }
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

        private void add_result_section (string title, Icon? icon, SearchProviderInfo? provider = null) {
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

            if (provider == null) {
                results_box.append (header);
                return;
            }

            var header_button = new Gtk.Button ();
            header_button.add_css_class ("search-section-header-button");
            header_button.add_css_class ("flat");
            header_button.set_child (header);
            header_button.tooltip_text = "Открыть в приложении";

            header_button.clicked.connect (() => {
                launch_provider_search.begin (
                    provider,
                    current_search_terms (),
                    fallback_event_time ()
                );
            });
            results_box.append (header_button);
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

        private void add_provider_result (SearchResult result) {
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
                } else if (result.id.has_prefix ("open-in-")) {
                    // Some providers expose a synthetic “open in application”
                    // row. It is not a content result, so forward the search
                    // terms through LaunchSearch instead of ActivateResult.
                    launch_provider_search.begin (
                        result.provider,
                        current_search_terms (),
                        fallback_event_time ()
                    );
                } else {
                    activate_provider_result.begin (
                        result,
                        current_search_terms (),
                        fallback_event_time ()
                    );
                }
            });

            results_box.append (row);
        }

        private async void launch_provider_search (
            SearchProviderInfo provider,
            owned string[] terms,
            uint32 timestamp
        ) {
            yield provider_manager.launch_search (provider, terms, timestamp);
            result_activated ();
        }

        private async void activate_provider_result (
            SearchResult result,
            owned string[] terms,
            uint32 timestamp
        ) {
            yield provider_manager.activate_result (result, terms, timestamp);
            result_activated ();
        }

        private string[] current_search_terms () {
            return search_entry.text.strip ().split (" ");
        }

        private static uint32 fallback_event_time () {
            // Keyboard activation has no pointer event. GDK event timestamps
            // are monotonic milliseconds and wrap at uint32, just like this.
            return (uint32) (get_monotonic_time () / 1000);
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
