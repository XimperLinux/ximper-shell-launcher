namespace XimperShellLauncher {

    public class SearchBar : Gtk.Box {
        public Gtk.SearchEntry search_entry { get; private set; }
        public ApplicationList results_widget { get; private set; }
        private weak Application app;
        private SearchProviderManager provider_manager;
        private Cancellable? search_cancellable;
        private uint search_timeout_id = 0;
        private bool browse_mode = false;
        private AppListSort browse_sort = AppListSort.RELEVANCE;
        private const uint DEBOUNCE_MS = 200;

        public signal void result_activated ();
        // This signal describes the query, not whether the all-apps list is visible.
        public signal void search_changed (bool is_searching);

        public SearchBar (Application app) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 12);
            this.app = app;
            add_css_class ("search-bar-container");
            provider_manager = new SearchProviderManager (app.config);
            if (app.config.search_providers_enabled) provider_manager.scan_providers ();
            var clamp = new Adw.Clamp ();
            clamp.maximum_size = 600;
            clamp.margin_top = clamp.margin_start = clamp.margin_end = 24;
            search_entry = new Gtk.SearchEntry ();
            search_entry.placeholder_text = _("Search applications…");
            search_entry.add_css_class ("search-entry");
            search_entry.hexpand = true;
            // Switch content and cancel stale work immediately, before debounce.
            search_entry.notify["text"].connect (debounce_search);
            clamp.set_child (search_entry);
            var search_overlay = new Gtk.Overlay ();
            search_overlay.set_child (clamp);
            var loading_indicator = new LoadingIndicator ();
            loading_indicator.valign = Gtk.Align.START;
            loading_indicator.halign = Gtk.Align.FILL;
            loading_indicator.margin_top = 4;
            loading_indicator.margin_start = loading_indicator.margin_end = 24;
            search_overlay.add_overlay (loading_indicator);
            append (search_overlay);
            results_widget = new ApplicationList (app);
            results_widget.loading_changed.connect (loading_indicator.set_loading);
            results_widget.item_activated.connect (activate_item);
            results_widget.action_activated.connect (() => result_activated ());
            results_widget.provider_search_requested.connect ((provider) => {
                launch_provider_search.begin (provider, current_search_terms (), fallback_event_time ());
            });
        }

        private void cancel_search () {
            if (search_timeout_id != 0) {
                Source.remove (search_timeout_id);
                search_timeout_id = 0;
            }
            if (search_cancellable != null) search_cancellable.cancel ();
        }

        private void debounce_search () {
            cancel_search ();
            bool searching = is_searching ();
            results_widget.set_pending (searching);
            search_changed (searching);
            if (!searching) {
                show_browse_results ();
                return;
            }
            search_timeout_id = Timeout.add (DEBOUNCE_MS, () => {
                search_timeout_id = 0;
                perform_search.begin ();
                return Source.REMOVE;
            });
        }

        private void show_browse_results () {
            var replacement = new GLib.ListStore (typeof (GLib.ListModel));
            if (browse_mode) {
                results_widget.append_applications (replacement, app.app_provider.apps, "", browse_sort);
            }
            results_widget.replace_sections (replacement);
        }

        private async void perform_search () {
            var query = search_entry.text.strip ();
            if (search_cancellable != null) search_cancellable.cancel ();
            search_cancellable = new Cancellable ();
            results_widget.set_pending (query.length > 0);
            if (query.length == 0) {
                show_browse_results ();
                return;
            }
            var current_cancellable = search_cancellable;
            var provider_results = new GenericArray<SearchResult> ();
            if (app.config.search_providers_enabled) {
                provider_manager.scan_providers ();
                provider_results = yield provider_manager.search (query, current_cancellable);
            }
            if (current_cancellable.is_cancelled ()) return;

            var provider_keys = new GenericArray<string> ();
            var provider_groups = new GenericArray<GenericArray<SearchResult>> ();
            for (uint i = 0; i < provider_results.length; i++) {
                var result = provider_results[i];
                int group_index = -1;
                for (uint j = 0; j < provider_keys.length; j++) {
                    if (provider_keys[j] == result.provider.desktop_id) {
                        group_index = (int) j;
                        break;
                    }
                }
                if (group_index < 0) {
                    provider_keys.add (result.provider.desktop_id);
                    provider_groups.add (new GenericArray<SearchResult> ());
                    group_index = (int) provider_keys.length - 1;
                }
                provider_groups[group_index].add (result);
            }
            var replacement = new GLib.ListStore (typeof (GLib.ListModel));
            for (uint i = 0; i < provider_groups.length; i++) {
                var group = provider_groups[i];
                var section = new GLib.ListStore (typeof (ApplicationListItem));
                for (uint j = 0; j < group.length; j++) {
                    var item = new ApplicationListItem.remote (group[j]);
                    item.section_end = j + 1 == group.length;
                    section.append (item);
                }
                if (section.get_n_items () > 0) replacement.append (section);
            }
            results_widget.append_applications (replacement, app.app_provider.search (query), query,
                app.config.search_sort, browse_mode ? 0 : 8);
            if (current_cancellable.is_cancelled ()) return;
            results_widget.replace_sections (replacement);
        }

        private void activate_item (ApplicationListItem item) {
            if (item.app_entry != null) {
                if (item.app_entry.launch ()) app.launch_history.record_launch (item.app_entry.desktop_id);
                result_activated ();
            } else if (item.provider_result != null) {
                var result = item.provider_result;
                if (result.clipboard_text != null && result.clipboard_text.length > 0) {
                    Gdk.Display.get_default ().get_clipboard ().set_text (result.clipboard_text);
                    result_activated ();
                } else if (result.id.has_prefix ("open-in-")) {
                    launch_provider_search.begin (result.provider, current_search_terms (), fallback_event_time ());
                } else {
                    activate_provider_result.begin (result, current_search_terms (), fallback_event_time ());
                }
            }
        }

        private async void launch_provider_search (SearchProviderInfo provider, owned string[] terms, uint32 timestamp) {
            yield provider_manager.launch_search (provider, terms, timestamp);
            result_activated ();
        }

        private async void activate_provider_result (SearchResult result, owned string[] terms, uint32 timestamp) {
            yield provider_manager.activate_result (result, terms, timestamp);
            result_activated ();
        }

        private string[] current_search_terms () { return search_entry.text.strip ().split (" "); }
        private static uint32 fallback_event_time () { return (uint32) (get_monotonic_time () / 1000); }
        public bool is_searching () { return search_entry.text.strip ().length > 0; }

        public void set_browse_mode (bool enabled, AppListSort sort) {
            browse_mode = enabled;
            browse_sort = sort;
        }

        public bool navigate_results (int direction) { return results_widget.navigate (direction); }
        public bool activate_selected_result () { return results_widget.activate_selected (); }

        public void reset () {
            cancel_search ();
            search_entry.text = "";
            cancel_search ();
            provider_manager.reset_search ();
            show_browse_results ();
            search_changed (false);
        }

        public void refresh () {
            cancel_search ();
            results_widget.set_pending (is_searching ());
            provider_manager.reset_search ();
            search_changed (is_searching ());
            if (is_searching ()) perform_search.begin ();
            else show_browse_results ();
        }
    }
}
