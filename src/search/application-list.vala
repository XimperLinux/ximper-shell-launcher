namespace XimperShellLauncher {

    public class ApplicationListItem : Object {
        public string title;
        public string? subtitle;
        public Icon? icon;
        public AppEntry? app_entry;
        public SearchResult? provider_result;
        public SearchProviderInfo? provider;
        public string? heading;
        public bool section_end = false;

        public ApplicationListItem.local (AppEntry entry, string? heading = null) {
            title = entry.name;
            subtitle = entry.generic_name ?? entry.description;
            icon = entry.icon;
            app_entry = entry;
            this.heading = heading;
        }

        public ApplicationListItem.remote (SearchResult result) {
            title = result.name;
            subtitle = result.description;
            icon = result.icon;
            provider_result = result;
            provider = result.provider;
        }
    }

    // One virtualized list for browsing applications and displaying search results.
    // Query/provider orchestration deliberately stays outside this widget.
    public class ApplicationList : Gtk.Box {
        private weak Application app;
        private GLib.ListStore sections;
        private Gtk.FlattenListModel model;
        private Gtk.SingleSelection selection;
        private Gtk.ListView view;
        private Gtk.ScrolledWindow scrolled;
        private Adw.ClampScrollable clamp;
        private weak Gtk.Popover? active_popover;
        public bool has_open_popover { get { return active_popover != null && active_popover.visible; } }
        public Gtk.Adjustment vadjustment { get { return scrolled.vadjustment; } }
        private bool pending = false;
        private uint scroll_tick = 0;
        private int scroll_frames = 0;

        public signal void item_activated (ApplicationListItem item);
        public signal void provider_search_requested (SearchProviderInfo provider);
        public signal void action_activated ();
        public signal void loading_changed (bool loading);
        public uint item_count { get { return model.get_n_items (); } }

        public ApplicationList (Application app) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.app = app;
            vexpand = true;
            hexpand = true;
            sections = new GLib.ListStore (typeof (GLib.ListModel));
            model = new Gtk.FlattenListModel (sections);
            selection = new Gtk.SingleSelection (model);
            selection.autoselect = false;
            selection.can_unselect = true;

            var factory = new Gtk.SignalListItemFactory ();
            weak ApplicationList weak_self = this;
            factory.setup.connect ((object) => {
                var self = weak_self;
                if (self != null) self.setup_item ((Gtk.ListItem) object);
            });
            factory.bind.connect ((object) => {
                var self = weak_self;
                if (self != null) self.bind_item ((Gtk.ListItem) object);
            });
            factory.unbind.connect ((object) => {
                var self = weak_self;
                if (self != null) self.unbind_item ((Gtk.ListItem) object);
            });
            view = new Gtk.ListView (selection, factory);
            view.header_factory = create_header_factory ();
            view.add_css_class ("search-results");
            view.single_click_activate = false;
            view.activate.connect ((position) => {
                var item = model.get_item (position) as ApplicationListItem;
                if (item != null && !pending) item_activated (item);
            });
            clamp = new Adw.ClampScrollable ();
            clamp.maximum_size = 600;
            clamp.margin_start = 24;
            clamp.margin_end = 24;
            clamp.margin_bottom = 16;
            clamp.set_child (view);
            scrolled = new Gtk.ScrolledWindow ();
            scrolled.vexpand = true;
            scrolled.hexpand = true;
            scrolled.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scrolled.set_child (clamp);
            append (scrolled);
        }

        public void set_column_mode (bool compact, bool wide) {
            clamp.maximum_size = compact ? 260 : (wide ? 10000 : 600);
            // The compact column should not claim its labels' unconstrained width.
            scrolled.propagate_natural_width = false;
        }

        public void set_pending (bool pending) {
            if (this.pending == pending) return;
            this.pending = pending;
            update_state (Gtk.AccessibleState.BUSY, pending, -1);
            loading_changed (pending);
            // Retain the old rows without dimming them, but don't activate stale results.
            view.can_target = !pending;
            if (pending && active_popover != null) active_popover.popdown ();
        }

        public void replace_sections (GLib.ListStore replacement) {
            if (active_popover != null) active_popover.popdown ();
            selection.unselect_all ();
            sections = replacement;
            // One model change: the visible list never passes through an empty store.
            model.set_model (sections);
            set_pending (false);
            select_first ();
        }

        public void append_applications (GLib.ListStore destination,
                                         GenericArray<AppEntry> apps, string query,
                                         AppListSort sort, uint limit = 0) {
            var ordered = ApplicationOrdering.sorted (apps, query, sort, app.launch_history);
            GLib.ListStore? section = null;
            string? previous_heading = null;
            for (uint i = 0; i < ordered.length && (limit == 0 || i < limit); i++) {
                string? heading = sort == AppListSort.ALPHABETICAL
                    ? ApplicationOrdering.heading (ordered[i].name) : null;
                if (section == null || heading != previous_heading) {
                    if (section != null) destination.append (section);
                    section = new GLib.ListStore (typeof (ApplicationListItem));
                    previous_heading = heading;
                }
                section.append (new ApplicationListItem.local (ordered[i], heading));
            }
            if (section != null) destination.append (section);
        }

        public void select_first () {
            if (selection.selected == Gtk.INVALID_LIST_POSITION && item_count > 0)
                selection.selected = 0;
            if (scroll_tick != 0) view.remove_tick_callback (scroll_tick);
            scroll_frames = 0;
            scroll_tick = view.add_tick_callback ((widget, clock) => {
                if (item_count > 0) view.scroll_to (0, Gtk.ListScrollFlags.NONE, null);
                vadjustment.value = vadjustment.lower;
                if (++scroll_frames < 3) return Source.CONTINUE;
                scroll_tick = 0;
                return Source.REMOVE;
            });
        }

        public bool navigate (int direction) {
            if (pending || item_count == 0 || direction == 0) return false;
            int current = selection.selected == Gtk.INVALID_LIST_POSITION
                ? (direction > 0 ? -1 : 0) : (int) selection.selected;
            uint position = (uint) ((current + direction + (int) item_count) % (int) item_count);
            selection.selected = position;
            view.scroll_to (position, Gtk.ListScrollFlags.FOCUS, null);
            return true;
        }

        public Gtk.Popover? get_active_popover () { return active_popover; }

        public void open_selected_context_menu () {
            if (pending) return;
            if (selection.selected == Gtk.INVALID_LIST_POSITION) return;
            var selected = model.get_item (selection.selected) as ApplicationListItem;
            if (selected == null || selected.app_entry == null) return;
            var row = find_item_row (view, selected);
            if (row != null) show_context_menu (row);
        }

        private Gtk.Widget? find_item_row (Gtk.Widget widget, ApplicationListItem item) {
            if (widget.get_data<ApplicationListItem> ("search-item") == item) return widget;
            for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
                var row = find_item_row (child, item);
                if (row != null) return row;
            }
            return null;
        }

        public bool activate_selected () {
            if (pending) return false;
            if (selection.selected == Gtk.INVALID_LIST_POSITION) return false;
            var item = model.get_item (selection.selected) as ApplicationListItem;
            if (item == null) return false;
            item_activated (item);
            return true;
        }

        private Gtk.ListItemFactory create_header_factory () {
            var factory = new Gtk.SignalListItemFactory ();
            weak ApplicationList weak_self = this;
            factory.setup.connect ((object) => {
                var header = (Gtk.ListHeader) object;
                var button = new Gtk.Button ();
                button.add_css_class ("flat");
                button.add_css_class ("search-section-header");
                button.hexpand = true;
                var content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                var image = new Gtk.Image ();
                image.pixel_size = 20;
                content.append (image);
                var label = new Gtk.Label ("");
                label.xalign = 0;
                label.hexpand = true;
                label.ellipsize = Pango.EllipsizeMode.END;
                label.add_css_class ("search-section-title");
                content.append (label);
                content.append (new Gtk.Image.from_icon_name ("go-next-symbolic"));
                button.child = content;
                header.child = button;
                weak Gtk.Button weak_button = button;
                button.clicked.connect (() => {
                    var self = weak_self;
                    var current = weak_button;
                    if (self == null || current == null || self.pending) return;
                    var provider = current.get_data<SearchProviderInfo> ("search-provider");
                    if (provider != null) self.provider_search_requested (provider);
                });
            });
            factory.bind.connect ((object) => {
                var header = (Gtk.ListHeader) object;
                var item = header.item as ApplicationListItem;
                var button = header.child as Gtk.Button;
                if (item == null || button == null) return;
                var image = button.child.get_first_child () as Gtk.Image;
                var label = image.get_next_sibling () as Gtk.Label;
                bool remote = item.provider != null;
                image.visible = remote;
                label.get_next_sibling ().visible = remote;
                button.can_target = remote;
                button.focusable = remote;
                button.set_data<SearchProviderInfo> ("search-provider", item.provider);
                button.tooltip_text = remote ? _("Open in application") : null;
                button.margin_start = remote ? 8 : 0;
                button.margin_end = remote ? 8 : 0;
                button.margin_bottom = remote ? 0 : 4;
                button.remove_css_class ("search-provider-header");
                if (remote) button.add_css_class ("search-provider-header");
                label.remove_css_class ("application-letter-heading");
                if (!remote && item.heading != null)
                    label.add_css_class ("application-letter-heading");
                label.label = remote ? (item.provider.name ?? item.provider.bus_name)
                    : (item.heading ?? _("Applications"));
                IconLoader.cancel_and_clear (image);
                if (remote) IconLoader.set_image_icon (image, item.provider.icon, 20, false);
            });
            factory.unbind.connect ((object) => {
                var button = ((Gtk.ListHeader) object).child as Gtk.Button;
                if (button == null) return;
                button.steal_data<SearchProviderInfo> ("search-provider");
                button.tooltip_text = null;
                button.remove_css_class ("search-provider-header");
                var image = button.child.get_first_child () as Gtk.Image;
                image.get_next_sibling ().remove_css_class ("application-letter-heading");
                IconLoader.cancel_and_clear (image);
            });
            return factory;
        }

        private void setup_item (Gtk.ListItem item) {
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            row.hexpand = true;
            row.margin_start = row.margin_end = 8;
            row.margin_top = row.margin_bottom = 4;
            var image = new Gtk.Image ();
            image.pixel_size = 32;
            row.append (image);
            var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            text.hexpand = true;
            var name = new Gtk.Label ("");
            name.halign = Gtk.Align.START;
            name.ellipsize = Pango.EllipsizeMode.END;
            name.add_css_class ("search-result-name");
            text.append (name);
            var description = new Gtk.Label ("");
            description.halign = Gtk.Align.START;
            description.ellipsize = Pango.EllipsizeMode.END;
            description.add_css_class ("search-result-desc");
            text.append (description);
            row.append (text);
            var surface = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            surface.append (row);
            item.child = surface;
            weak ApplicationList weak_self = this;
            weak Gtk.Box weak_row = row;
            var click = new Gtk.GestureClick ();
            click.button = Gdk.BUTTON_SECONDARY;
            click.pressed.connect (() => {
                var self = weak_self;
                var current = weak_row;
                if (self != null && current != null) self.show_context_menu (current);
            });
            row.add_controller (click);
            var long_press = new Gtk.GestureLongPress ();
            long_press.pressed.connect (() => {
                var self = weak_self;
                var current = weak_row;
                if (self != null && current != null) self.show_context_menu (current);
            });
            row.add_controller (long_press);
        }

        private void bind_item (Gtk.ListItem list_item) {
            var item = list_item.item as ApplicationListItem;
            if (item == null) return;
            var surface = list_item.child as Gtk.Box;
            var row = surface.get_first_child () as Gtk.Box;
            bool remote = item.provider != null;
            surface.remove_css_class ("search-provider-surface");
            surface.remove_css_class ("search-provider-end");
            surface.margin_start = surface.margin_end = remote ? 8 : 0;
            surface.margin_bottom = remote && item.section_end ? 12 : 0;
            if (remote) {
                surface.add_css_class ("search-provider-surface");
                if (item.section_end) surface.add_css_class ("search-provider-end");
            }
            row.set_data<ApplicationListItem> ("search-item", item);
            row.add_css_class ("search-result-row");
            var image = row.get_first_child () as Gtk.Image;
            var name = image.get_next_sibling ().get_first_child () as Gtk.Label;
            var description = name.get_next_sibling () as Gtk.Label;
            name.label = item.title;
            description.label = item.subtitle ?? "";
            description.visible = true;
            IconLoader.cancel_and_clear (image);
            IconLoader.set_image_icon (image, item.icon, 32, true);
        }

        private void unbind_item (Gtk.ListItem item) {
            var surface = item.child as Gtk.Box;
            var row = surface.get_first_child () as Gtk.Box;
            row.steal_data<ApplicationListItem> ("search-item");
            row.remove_css_class ("search-result-row");
            var image = row.get_first_child () as Gtk.Image;
            IconLoader.cancel_and_clear (image);
            var name = image.get_next_sibling ().get_first_child () as Gtk.Label;
            name.label = "";
            ((Gtk.Label) name.get_next_sibling ()).label = "";
        }

        private void show_context_menu (Gtk.Widget row) {
            if (pending) return;
            var item = row.get_data<ApplicationListItem> ("search-item");
            if (item == null || item.app_entry == null) return;
            var entry = item.app_entry;
            var popover = new Gtk.Popover ();
            popover.set_parent (row);
            popover.has_arrow = true;
            popover.autohide = true;
            popover.add_css_class ("menu");
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            foreach (var action_id in entry.list_actions ()) {
                var captured = action_id;
                var button = new Gtk.Button.with_label (entry.get_action_name (action_id));
                button.add_css_class ("flat");
                button.clicked.connect (() => {
                    popover.popdown ();
                    entry.launch_action (captured);
                    app.launch_history.record_launch (entry.desktop_id);
                    action_activated ();
                });
                box.append (button);
            }
            if (app.is_dock_running ()) {
                if (box.get_first_child () != null)
                    box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
                bool pinned = app.is_pinned_in_dock (entry.desktop_id);
                var button = new Gtk.Button.with_label (pinned ? _("Unpin from Dock") : _("Pin to Dock"));
                button.add_css_class ("flat");
                button.clicked.connect (() => {
                    popover.popdown ();
                    if (pinned) app.unpin_from_dock (entry.desktop_id);
                    else app.pin_to_dock (entry.desktop_id);
                });
                box.append (button);
            }
            if (box.get_first_child () == null) { popover.unparent (); return; }
            popover.set_child (box);
            active_popover = popover;
            popover.closed.connect (() => {
                active_popover = null;
                popover.unparent ();
            });
            popover.popup ();
            box.get_first_child ().grab_focus ();
        }
    }
}
