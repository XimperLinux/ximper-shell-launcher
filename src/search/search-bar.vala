namespace XimperShellLauncher {

    private enum SearchItemKind {
        LOCAL,
        PROVIDER
    }

    private class SearchListItem : Object {
        public SearchItemKind kind;
        public string title;
        public string? subtitle;
        public Icon? icon;
        public AppEntry? app_entry;
        public SearchResult? provider_result;
        public SearchProviderInfo? provider;

        public SearchListItem.local (AppEntry entry) {
            kind = SearchItemKind.LOCAL;
            title = entry.name;
            subtitle = entry.generic_name ?? entry.description;
            icon = entry.icon;
            app_entry = entry;
        }

        public SearchListItem.remote (SearchResult result) {
            kind = SearchItemKind.PROVIDER;
            title = result.name;
            subtitle = result.description;
            icon = result.icon;
            provider_result = result;
            provider = result.provider;
        }
    }

    private class IconLoadState : Object {
        public Cancellable? cancellable;
        public uint generation;
    }

    private class IconCacheEntry : Object {
        public string key;
        public Gdk.Texture texture;

        public IconCacheEntry (string key, Gdk.Texture texture) {
            this.key = key;
            this.texture = texture;
        }
    }

    public class SearchBar : Gtk.Box {
        public Gtk.SearchEntry search_entry { get; private set; }
        public Gtk.ScrolledWindow results_widget { get; private set; }

        private weak Application app;
        private SearchProviderManager provider_manager;
        private GLib.ListStore section_store;
        private Gtk.FlattenListModel results_model;
        private Gtk.SingleSelection selection;
        private Gtk.ListView results_view;
        private Gtk.ListItemFactory section_header_factory;
        private Cancellable? search_cancellable;
        private uint search_timeout_id = 0;
        private uint scroll_to_top_tick_id = 0;
        private int scroll_to_top_frames = 0;
        private bool wofi_mode = false;

        private const uint DEBOUNCE_MS = 200;
        private const uint ICON_CACHE_LIMIT = 128;
        private GenericArray<IconCacheEntry> icon_cache =
            new GenericArray<IconCacheEntry> ();

        public signal void result_activated ();
        public signal void search_changed (bool is_searching);

        public SearchBar (Application app) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 12);
            this.app = app;

            add_css_class ("search-bar-container");

            provider_manager = new SearchProviderManager (app.config);
            if (app.config.search_providers_enabled) {
                provider_manager.scan_providers ();
            }

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
            search_entry.search_changed.connect (debounce_search);
            clamp.set_child (search_entry);
            append (clamp);

            // FlattenListModel preserves each child ListModel as a section.
            section_store = new GLib.ListStore (typeof (GLib.ListModel));
            results_model = new Gtk.FlattenListModel (section_store);
            selection = new Gtk.SingleSelection (results_model);
            selection.autoselect = false;
            selection.can_unselect = true;

            var factory = new Gtk.SignalListItemFactory ();
            weak SearchBar weak_self = this;
            factory.setup.connect ((object) => {
                var self = weak_self;
                if (self != null) {
                    self.setup_list_item ((Gtk.ListItem) object);
                }
            });
            factory.bind.connect ((object) => {
                var self = weak_self;
                if (self != null) {
                    self.bind_list_item ((Gtk.ListItem) object);
                }
            });
            factory.unbind.connect ((object) => {
                var self = weak_self;
                if (self != null) {
                    self.unbind_list_item ((Gtk.ListItem) object);
                }
            });

            section_header_factory = create_header_factory ();
            results_view = new Gtk.ListView (selection, factory);
            results_view.header_factory = section_header_factory;
            results_view.add_css_class ("search-results");
            results_view.margin_start = 24;
            results_view.margin_end = 24;
            results_view.single_click_activate = false;
            results_view.activate.connect ((position) => {
                var item = results_model.get_item (position) as SearchListItem;
                if (item != null) {
                    activate_item (item);
                }
            });

            // ClampScrollable is specifically designed to constrain a
            // Gtk.ListView without defeating its scrollable virtualization.
            var results_clamp = new Adw.ClampScrollable ();
            results_clamp.maximum_size = 600;
            results_clamp.set_child (results_view);

            results_widget = new Gtk.ScrolledWindow ();
            results_widget.vexpand = true;
            results_widget.hscrollbar_policy = Gtk.PolicyType.NEVER;
            results_widget.set_child (results_clamp);
        }

        private Gtk.ListItemFactory create_header_factory () {
            var factory = new Gtk.SignalListItemFactory ();
            weak SearchBar weak_self = this;

            factory.setup.connect ((object) => {
                var header = (Gtk.ListHeader) object;
                var button = new Gtk.Button ();
                button.add_css_class ("flat");
                button.add_css_class ("search-section-header");
                button.hexpand = true;
                button.halign = Gtk.Align.FILL;
                button.margin_top = 8;
                button.margin_bottom = 4;

                var content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                content.hexpand = true;
                content.halign = Gtk.Align.FILL;
                var image = new Gtk.Image ();
                image.pixel_size = 20;
                content.append (image);

                var label = new Gtk.Label ("");
                label.halign = Gtk.Align.FILL;
                label.xalign = 0;
                label.hexpand = true;
                label.add_css_class ("search-section-title");
                content.append (label);
                button.child = content;
                header.child = button;

                weak Gtk.Button weak_button = button;
                button.clicked.connect (() => {
                    var self = weak_self;
                    var current_button = weak_button;
                    if (self == null || current_button == null) {
                        return;
                    }
                    var provider = current_button.get_data<SearchProviderInfo> (
                        "search-provider"
                    );
                    if (provider != null) {
                        self.launch_provider_search.begin (
                            provider,
                            self.current_search_terms (),
                            fallback_event_time ()
                        );
                    }
                });
            });

            factory.bind.connect ((object) => {
                var header = (Gtk.ListHeader) object;
                var item = header.item as SearchListItem;
                var button = header.child as Gtk.Button;
                if (item == null || button == null) {
                    return;
                }

                var content = button.child as Gtk.Box;
                var image = content.get_first_child () as Gtk.Image;
                var label = image.get_next_sibling () as Gtk.Label;
                bool is_provider = item.kind == SearchItemKind.PROVIDER;

                button.visible = true;
                button.sensitive = true;
                button.can_target = is_provider;
                button.focusable = is_provider;
                button.set_data<SearchProviderInfo> ("search-provider", item.provider);
                button.tooltip_text = is_provider ? _("Open in application") : null;
                button.remove_css_class ("search-provider-header");
                if (is_provider) {
                    button.add_css_class ("search-provider-header");
                }

                label.label = is_provider
                    ? (item.provider.name ?? item.provider.bus_name)
                    : _("Applications");
                clear_image (image);
                if (is_provider) {
                    set_image_icon (image, item.provider.icon, 20, false);
                }
            });

            factory.unbind.connect ((object) => {
                var header = (Gtk.ListHeader) object;
                var button = header.child as Gtk.Button;
                if (button == null) {
                    return;
                }
                var content = button.child as Gtk.Box;
                var image = content.get_first_child () as Gtk.Image;
                var label = image.get_next_sibling () as Gtk.Label;

                button.steal_data<SearchProviderInfo> ("search-provider");
                button.tooltip_text = null;
                button.visible = true;
                button.sensitive = true;
                button.can_target = true;
                button.focusable = true;
                button.remove_css_class ("search-provider-header");
                cancel_image_load (image);
                clear_image (image);
                label.label = "";
            });

            return factory;
        }

        private void setup_list_item (Gtk.ListItem list_item) {
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            row.margin_start = 8;
            row.margin_end = 8;
            row.margin_top = 0;
            row.margin_bottom = 0;
            row.hexpand = true;

            var image = new Gtk.Image ();
            image.pixel_size = 32;
            row.append (image);

            var text_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            text_box.hexpand = true;

            var name_label = new Gtk.Label ("");
            name_label.halign = Gtk.Align.START;
            name_label.ellipsize = Pango.EllipsizeMode.END;
            name_label.add_css_class ("search-result-name");
            text_box.append (name_label);

            var desc_label = new Gtk.Label ("");
            desc_label.halign = Gtk.Align.START;
            desc_label.ellipsize = Pango.EllipsizeMode.END;
            desc_label.add_css_class ("search-result-desc");
            desc_label.add_css_class ("dim-label");
            text_box.append (desc_label);

            row.append (text_box);
            list_item.child = row;

            weak SearchBar weak_self = this;
            weak Gtk.Box weak_row = row;
            var secondary_click = new Gtk.GestureClick ();
            secondary_click.button = Gdk.BUTTON_SECONDARY;
            secondary_click.pressed.connect ((n_press, x, y) => {
                var self = weak_self;
                var current_row = weak_row;
                if (self == null || current_row == null) {
                    return;
                }

                var item = current_row.get_data<SearchListItem> ("search-item");
                if (item != null && item.app_entry != null) {
                    self.show_app_result_context_menu (current_row, item.app_entry);
                }
            });
            row.add_controller (secondary_click);

            var long_press = new Gtk.GestureLongPress ();
            long_press.pressed.connect ((x, y) => {
                var self = weak_self;
                var current_row = weak_row;
                if (self == null || current_row == null) {
                    return;
                }

                var item = current_row.get_data<SearchListItem> ("search-item");
                if (item != null && item.app_entry != null) {
                    self.show_app_result_context_menu (current_row, item.app_entry);
                }
            });
            row.add_controller (long_press);
        }

        private void bind_list_item (Gtk.ListItem list_item) {
            var item = list_item.item as SearchListItem;
            var row = list_item.child as Gtk.Box;
            if (item == null || row == null) {
                return;
            }

            var image = row.get_first_child () as Gtk.Image;
            var text_box = image.get_next_sibling () as Gtk.Box;
            var name_label = text_box.get_first_child () as Gtk.Label;
            var desc_label = name_label.get_next_sibling () as Gtk.Label;

            row.set_data<SearchListItem> ("search-item", item);
            row.add_css_class ("search-result-row");
            row.margin_start = 8;
            row.margin_end = 8;
            row.margin_top = 4;
            row.margin_bottom = 4;
            row.tooltip_text = null;

            name_label.label = item.title;
            desc_label.label = item.subtitle ?? "";
            // Keep the secondary line allocated even when a result has no
            // description, so every result row has the same measured height.
            desc_label.visible = true;

            clear_image (image);
            set_image_icon (image, item.icon, 32, true);
        }

        private void unbind_list_item (Gtk.ListItem list_item) {
            var row = list_item.child as Gtk.Box;
            if (row == null) {
                return;
            }

            var image = row.get_first_child () as Gtk.Image;
            var text_box = image.get_next_sibling () as Gtk.Box;
            var name_label = text_box.get_first_child () as Gtk.Label;
            var desc_label = name_label.get_next_sibling () as Gtk.Label;

            row.steal_data<SearchListItem> ("search-item");
            row.remove_css_class ("search-result-row");
            row.margin_start = 8;
            row.margin_end = 8;
            row.margin_top = 4;
            row.margin_bottom = 4;
            row.sensitive = true;
            row.tooltip_text = null;

            cancel_image_load (image);
            clear_image (image);
            image.pixel_size = 32;

            name_label.label = "";
            desc_label.label = "";
            desc_label.visible = false;
        }

        private IconLoadState image_state (Gtk.Image image) {
            var state = image.get_data<IconLoadState> ("icon-load-state");
            if (state == null) {
                state = new IconLoadState ();
                image.set_data<IconLoadState> ("icon-load-state", state);
            }
            return state;
        }

        private void cancel_image_load (Gtk.Image image) {
            var state = image_state (image);
            state.generation++;
            if (state.cancellable != null) {
                state.cancellable.cancel ();
                state.cancellable = null;
            }
        }

        private void clear_image (Gtk.Image image) {
            image.paintable = null;
            image.gicon = null;
            image.icon_name = null;
            image.visible = false;
        }

        private Gdk.Texture? lookup_cached_icon (string key) {
            for (uint i = 0; i < icon_cache.length; i++) {
                if (icon_cache[i].key == key) {
                    var entry = icon_cache[i];
                    icon_cache.remove_index (i);
                    icon_cache.add (entry);
                    return entry.texture;
                }
            }
            return null;
        }

        private void cache_icon (string key, Gdk.Texture texture) {
            icon_cache.add (new IconCacheEntry (key, texture));
            if (icon_cache.length > ICON_CACHE_LIMIT) {
                icon_cache.remove_index (0);
            }
        }

        private void set_image_icon (Gtk.Image image, Icon? icon,
                                     int logical_size, bool result_fallback) {
            cancel_image_load (image);
            clear_image (image);
            image.pixel_size = logical_size;

            if (icon == null) {
                if (result_fallback) {
                    image.icon_name = "application-x-executable-symbolic";
                    image.visible = true;
                }
                return;
            }

            int scale = int.max (1, image.scale_factor);
            var loadable = icon as LoadableIcon;
            if (loadable == null) {
                // Resolve regular themed icons to their backing file and feed
                // them through the same bounded decoder. Keep symbolic icons
                // on GTK's native path so theme color recoloring still works.
                var display = image.get_display ();
                var theme = Gtk.IconTheme.get_for_display (display);
                var paintable = theme.lookup_by_gicon (
                    icon,
                    logical_size,
                    scale,
                    image.get_direction (),
                    Gtk.IconLookupFlags.NONE
                );
                var themed_file = paintable.get_file ();
                var basename = themed_file != null ? themed_file.get_basename () : null;
                bool symbolic = basename != null && basename.contains ("-symbolic.");
                if (themed_file != null && themed_file.is_native () && !symbolic) {
                    loadable = new FileIcon (themed_file);
                } else {
                    image.gicon = icon;
                    image.visible = true;
                    return;
                }
            }

            string? uri = null;
            var file_icon = loadable as FileIcon;
            if (file_icon != null) {
                var file = file_icon.file;
                // Remote icon providers must not introduce network I/O into
                // scrolling or retain arbitrarily large remote responses.
                if (!file.is_native ()) {
                    if (result_fallback) {
                        image.icon_name = "application-x-executable-symbolic";
                        image.visible = true;
                    }
                    return;
                }
                uri = file.get_uri ();
            } else {
                uri = icon.to_string ();
            }

            if (uri == null) {
                if (result_fallback) {
                    image.icon_name = "application-x-executable-symbolic";
                    image.visible = true;
                }
                return;
            }

            int physical_size = logical_size * scale;
            string key = "%s|%d|%d".printf (uri, physical_size, scale);
            var cached = lookup_cached_icon (key);
            if (cached != null) {
                image.paintable = cached;
                image.visible = true;
                return;
            }

            var state = image_state (image);
            state.cancellable = new Cancellable ();
            uint generation = state.generation;
            load_icon_async.begin (loadable, physical_size, state.cancellable,
                (obj, res) => {
                    Gdk.Texture? texture = null;
                    try {
                        texture = load_icon_async.end (res);
                    } catch (Error e) {
                        // Cancellation and malformed icon files are expected.
                    }
                    if (state.generation != generation ||
                        state.cancellable == null ||
                        state.cancellable.is_cancelled ()) {
                        return;
                    }
                    state.cancellable = null;
                    if (texture != null) {
                        cache_icon (key, texture);
                        image.paintable = texture;
                        image.visible = true;
                    } else if (result_fallback) {
                        image.icon_name = "application-x-executable-symbolic";
                        image.visible = true;
                    }
                });
        }

        private async Gdk.Texture load_icon_async (LoadableIcon icon, int size,
                                                   Cancellable cancellable)
                                                   throws Error {
            string? content_type = null;
            InputStream stream = yield icon.load_async (
                size, cancellable, out content_type
            );
            var pixbuf = yield new Gdk.Pixbuf.from_stream_at_scale_async (
                stream, size, size, true, cancellable
            );
            try {
                yield stream.close_async (Priority.DEFAULT, cancellable);
            } catch (Error e) {
                // The decoded pixbuf is independent of the source stream.
            }
            return Gdk.Texture.for_pixbuf (pixbuf);
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
            if (search_cancellable != null) {
                search_cancellable.cancel ();
            }

            search_cancellable = new Cancellable ();
            clear_results ();

            if (query.length == 0) {
                if (wofi_mode) {
                    add_local_results (query, 0);
                    search_changed (true);
                } else {
                    search_changed (false);
                }
                return;
            }

            search_changed (true);
            if (app.config.search_providers_enabled) {
                provider_manager.scan_providers ();
            }

            var current_cancellable = search_cancellable;
            var provider_results = yield provider_manager.search (
                query,
                current_cancellable
            );
            if (current_cancellable.is_cancelled ()) {
                return;
            }

            var provider_keys = new GenericArray<string> ();
            var provider_groups = new GenericArray<GenericArray<SearchResult>> ();
            for (uint i = 0; i < provider_results.length; i++) {
                var result = provider_results[i];
                int group_index = -1;
                for (uint j = 0; j < provider_keys.length; j++) {
                    if (provider_keys[j] == result.provider.bus_name) {
                        group_index = (int) j;
                        break;
                    }
                }

                if (group_index < 0) {
                    provider_keys.add (result.provider.bus_name);
                    provider_groups.add (new GenericArray<SearchResult> ());
                    group_index = (int) provider_keys.length - 1;
                }
                provider_groups[group_index].add (result);
            }

            for (uint i = 0; i < provider_groups.length; i++) {
                var group = provider_groups[i];
                if (group.length == 0) {
                    continue;
                }

                var provider_section = create_section_store ();
                for (uint j = 0; j < group.length; j++) {
                    provider_section.append (new SearchListItem.remote (group[j]));
                }
                section_store.append (provider_section);
            }

            add_local_results (query, wofi_mode ? 0 : 8);
            select_first ();
        }

        private void add_local_results (string query, uint limit) {
            var local_results = query.length == 0
                ? copy_apps (app.app_provider.apps)
                : app.app_provider.search (query);
            if (local_results.length == 0) {
                return;
            }

            sort_local_results (local_results, query);
            var local_section = create_section_store ();
            for (uint i = 0; i < local_results.length && (limit == 0 || i < limit); i++) {
                local_section.append (new SearchListItem.local (local_results[i]));
            }
            if (local_section.get_n_items () > 0) {
                section_store.append (local_section);
            }
            select_first ();
        }

        private GLib.ListStore create_section_store () {
            return new GLib.ListStore (typeof (SearchListItem));
        }

        private GenericArray<AppEntry> copy_apps (GenericArray<AppEntry> apps) {
            var copy = new GenericArray<AppEntry> ();
            for (uint i = 0; i < apps.length; i++) {
                copy.add (apps[i]);
            }
            return copy;
        }

        private void sort_local_results (GenericArray<AppEntry> results, string query) {
            for (int i = 0; i < (int) results.length - 1; i++) {
                for (int j = i + 1; j < (int) results.length; j++) {
                    if (local_result_priority (results[j], query) >
                        local_result_priority (results[i], query)) {
                        var temporary = results[i];
                        results[i] = results[j];
                        results[j] = temporary;
                    }
                }
            }
        }

        private int local_result_priority (AppEntry entry, string query) {
            int launches = app.launch_history.get_count (entry.desktop_id).clamp (0, 999);
            if (query.length == 0) {
                return launches;
            }
            return entry.match_score (query) * 1000 + launches;
        }

        private void clear_results () {
            section_store.remove_all ();
            selection.unselect_all ();
        }

        private void select_first () {
            if (selection.selected == Gtk.INVALID_LIST_POSITION) {
                for (uint i = 0; i < results_model.get_n_items (); i++) {
                    var item = results_model.get_item (i) as SearchListItem;
                    if (item != null) {
                        selection.selected = i;
                        break;
                    }
                }
            }

            scroll_results_to_top ();
        }

        private void scroll_results_to_top () {
            if (scroll_to_top_tick_id != 0) {
                results_view.remove_tick_callback (scroll_to_top_tick_id);
            }

            scroll_to_top_frames = 0;
            scroll_to_top_tick_id = results_view.add_tick_callback ((widget, frame_clock) => {
                if (results_model.get_n_items () > 0) {
                    results_view.scroll_to (0, Gtk.ListScrollFlags.NONE, null);
                }
                var adjustment = results_widget.vadjustment;
                adjustment.value = adjustment.lower;

                scroll_to_top_frames++;
                if (scroll_to_top_frames < 3) {
                    return Source.CONTINUE;
                }

                scroll_to_top_tick_id = 0;
                return Source.REMOVE;
            });
        }

        private void activate_item (SearchListItem item) {
            if (item.kind == SearchItemKind.LOCAL && item.app_entry != null) {
                if (item.app_entry.launch ()) {
                    app.launch_history.record_launch (item.app_entry.desktop_id);
                }
                result_activated ();
            } else if (item.provider_result != null) {
                var result = item.provider_result;
                if (result.clipboard_text != null && result.clipboard_text.length > 0) {
                    var clipboard = Gdk.Display.get_default ().get_clipboard ();
                    clipboard.set_text (result.clipboard_text);
                    result_activated ();
                } else if (result.id.has_prefix ("open-in-")) {
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
            }
        }

        private Gtk.Button make_menu_item (string label) {
            var button = new Gtk.Button ();
            button.add_css_class ("flat");
            button.label = label;
            return button;
        }

        private void show_app_result_context_menu (Gtk.Widget row, AppEntry entry) {
            var popover = new Gtk.Popover ();
            popover.set_parent (row);
            popover.has_arrow = true;
            popover.autohide = true;
            popover.add_css_class ("menu");

            var menu_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var desktop_actions = entry.list_actions ();
            if (desktop_actions.length > 0) {
                foreach (var action_id in desktop_actions) {
                    var captured_action_id = action_id;
                    var button = make_menu_item (entry.get_action_name (action_id));
                    button.clicked.connect (() => {
                        popover.popdown ();
                        entry.launch_action (captured_action_id);
                        app.launch_history.record_launch (entry.desktop_id);
                        result_activated ();
                    });
                    menu_box.append (button);
                }
                menu_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            }

            if (app.is_dock_running ()) {
                bool pinned = app.is_pinned_in_dock (entry.desktop_id);
                var button = make_menu_item (
                    pinned ? _("Unpin from Dock") : _("Pin to Dock")
                );
                button.clicked.connect (() => {
                    popover.popdown ();
                    if (pinned) {
                        app.unpin_from_dock (entry.desktop_id);
                    } else {
                        app.pin_to_dock (entry.desktop_id);
                    }
                });
                menu_box.append (button);
            }

            if (menu_box.get_first_child () == null) {
                popover.unparent ();
                return;
            }

            popover.set_child (menu_box);
            popover.closed.connect (() => popover.unparent ());
            popover.popup ();

            var first_item = menu_box.get_first_child ();
            if (first_item != null) {
                first_item.grab_focus ();
            }
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
            return (uint32) (get_monotonic_time () / 1000);
        }

        public bool is_searching () {
            return wofi_mode || search_entry.text.strip ().length > 0;
        }

        public void set_wofi_mode (bool enabled) {
            wofi_mode = enabled;
        }

        public bool navigate_results (int direction) {
            uint item_count = results_model.get_n_items ();
            if (item_count == 0 || direction == 0) {
                return false;
            }

            int position = selection.selected == Gtk.INVALID_LIST_POSITION
                ? (direction > 0 ? -1 : 0)
                : (int) selection.selected;
            for (uint step = 0; step < item_count; step++) {
                position = (position + direction + (int) item_count) % (int) item_count;
                var item = results_model.get_item ((uint) position) as SearchListItem;
                if (item != null) {
                    selection.selected = (uint) position;
                    results_view.scroll_to (
                        (uint) position,
                        Gtk.ListScrollFlags.FOCUS,
                        null
                    );
                    return true;
                }
            }
            return false;
        }

        public bool activate_selected_result () {
            uint position = selection.selected;
            if (position == Gtk.INVALID_LIST_POSITION) {
                return false;
            }

            var item = results_model.get_item (position) as SearchListItem;
            if (item == null) {
                return false;
            }
            activate_item (item);
            return true;
        }

        public void reset () {
            // GridWindow may call reset repeatedly while Wofi mode is already
            // showing its empty-query cache. Do not trigger a duplicate search.
            if (wofi_mode && search_entry.text.strip ().length == 0 &&
                results_model.get_n_items () > 0) {
                select_first ();
                provider_manager.reset_search ();
                return;
            }

            search_entry.text = "";
            if (search_timeout_id != 0) {
                Source.remove (search_timeout_id);
                search_timeout_id = 0;
            }
            provider_manager.reset_search ();

            if (wofi_mode) {
                perform_search.begin ();
            } else {
                if (search_cancellable != null) {
                    search_cancellable.cancel ();
                }
                clear_results ();
            }
        }
    }
}
