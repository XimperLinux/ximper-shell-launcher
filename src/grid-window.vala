namespace XimperShellTileMenu {

    private class NonMeasuringBackground : Gtk.Widget {
        private Gtk.Picture picture;

        public NonMeasuringBackground (Gtk.Picture picture) {
            this.picture = picture;
            picture.set_parent (this);
        }

        public override void measure (Gtk.Orientation orientation, int for_size,
                                     out int minimum, out int natural,
                                     out int minimum_baseline, out int natural_baseline) {
            minimum = 0;
            natural = 0;
            minimum_baseline = -1;
            natural_baseline = -1;
        }

        public override void size_allocate (int width, int height, int baseline) {
            picture.allocate (width, height, baseline, null);
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            snapshot_child (picture, snapshot);
        }
    }

    public class GridWindow : Gtk.Window {

        private weak Application app;
        private SearchBar search_bar;
        private TileGrid tile_grid;
        private Gtk.ScrolledWindow scrolled;
        private Gtk.Stack content_stack;
        private Adw.ToastOverlay toast_overlay;
        private Gtk.Box background;
        private Gtk.Picture wallpaper;
        private Gtk.Box wallpaper_dimmer;
        private Gtk.Overlay top_overlay;
        private Gtk.Overlay root_overlay;
        private Gtk.Button settings_btn;
        private bool settings_in_root_overlay = false;
        private bool wofi_mode = false;
        private bool ignore_next_focus_leave = false;
        private bool focus_leave_armed = false;
        private Gdk.Monitor? floating_monitor;

        private int popover_focus_index = -1;
        private GenericArray<Gtk.Button>? popover_buttons;

        public GridWindow (Application app) {
            this.app = app;
            this.title = "Ximper Shell Tile Menu";
            this.decorated = false;

            add_css_class ("grid-overlay");

            LayerShellHelper.setup_overlay (this, LayerShellHelper.parse_layer (app.config.layer));

            build_ui ();
            setup_keys ();
            setup_click_close ();
            setup_config_updates ();
            setup_focus_close ();
            apply_window_mode ();
        }

        private void build_ui () {
            var main_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            // Top bar: search + settings button
            top_overlay = new Gtk.Overlay ();

            search_bar = new SearchBar (app);
            search_bar.result_activated.connect (() => {
                close_grid ();
            });
            search_bar.search_changed.connect ((is_searching) => {
                content_stack.visible_child_name = is_searching ? "search" : "tiles";
            });
            top_overlay.set_child (search_bar);

            settings_btn = new Gtk.Button.from_icon_name ("emblem-system-symbolic");
            settings_btn.add_css_class ("flat");
            settings_btn.add_css_class ("circular");
            settings_btn.tooltip_text = _("Settings");
            settings_btn.halign = Gtk.Align.END;
            settings_btn.valign = Gtk.Align.START;
            settings_btn.margin_top = 24;
            settings_btn.margin_end = 24;
            settings_btn.clicked.connect (() => {
                close_grid ();
                var settings = new SettingsWindow (app);
                settings.present ();
            });
            top_overlay.add_overlay (settings_btn);

            main_box.append (top_overlay);

            // Stack: tiles ↔ search results with crossfade
            content_stack = new Gtk.Stack ();
            content_stack.transition_type = Gtk.StackTransitionType.CROSSFADE;
            content_stack.transition_duration = 200;
            content_stack.vexpand = true;
            content_stack.hexpand = true;

            scrolled = new Gtk.ScrolledWindow ();
            scrolled.vexpand = true;
            scrolled.hexpand = true;
            scrolled.hscrollbar_policy = Gtk.PolicyType.NEVER;

            tile_grid = new TileGrid (app);
            tile_grid.tile_activated.connect ((entry) => {
                entry.launch ();
                close_grid ();
            });
            tile_grid.pin_requested.connect ((desktop_id) => {
                pin_to_dock (desktop_id);
            });
            tile_grid.unpin_requested.connect ((desktop_id) => {
                app.unpin_from_dock (desktop_id);
            });

            scrolled.set_child (tile_grid);
            content_stack.add_named (scrolled, "tiles");
            content_stack.add_named (search_bar.results_widget, "search");
            content_stack.visible_child_name = "tiles";

            main_box.append (content_stack);

            // Drop on empty area — extract from folder
            var empty_drop = new Gtk.DropTarget (typeof (string), Gdk.DragAction.MOVE);
            empty_drop.drop.connect ((val, x, y) => {
                var src_id = (string) val;
                if (src_id == null || src_id.has_prefix ("folder:")) return false;
                tile_grid.extract_from_open_folder (src_id);
                return true;
            });
            scrolled.add_controller (empty_drop);

            toast_overlay = new Adw.ToastOverlay ();
            toast_overlay.set_child (main_box);
            toast_overlay.hexpand = true;
            toast_overlay.vexpand = true;

            wallpaper = new Gtk.Picture ();
            wallpaper.content_fit = Gtk.ContentFit.COVER;
            wallpaper.hexpand = true;
            wallpaper.vexpand = true;
            wallpaper.can_target = false;
            wallpaper.add_css_class ("wallpaper");

            var wallpaper_layer = new NonMeasuringBackground (wallpaper);

            background = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            background.hexpand = true;
            background.vexpand = true;
            background.can_target = false;
            background.add_css_class ("window-background");

            wallpaper_dimmer = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            wallpaper_dimmer.hexpand = true;
            wallpaper_dimmer.vexpand = true;
            wallpaper_dimmer.can_target = false;
            wallpaper_dimmer.add_css_class ("wallpaper-dimmer");
            update_wallpaper ();

            root_overlay = new Gtk.Overlay ();
            root_overlay.set_child (background);
            root_overlay.add_overlay (wallpaper_layer);
            root_overlay.add_overlay (wallpaper_dimmer);
            root_overlay.add_overlay (toast_overlay);
            root_overlay.set_measure_overlay (toast_overlay, true);
            set_child (root_overlay);
        }

        private void update_wallpaper () {
            var path = app.config.wallpaper_path;
            if (path.length == 0) {
                wallpaper.file = null;
                wallpaper_dimmer.opacity = 0;
                remove_css_class ("has-wallpaper");
                update_background_opacity ();
                return;
            }

            if (!Path.is_absolute (path) || !FileUtils.test (path, FileTest.IS_REGULAR)) {
                warning ("Wallpaper path must be an absolute regular local file: %s", path);
                wallpaper.file = null;
                wallpaper_dimmer.opacity = 0;
                remove_css_class ("has-wallpaper");
                update_background_opacity ();
                return;
            }

            wallpaper.file = File.new_for_path (path);
            wallpaper.content_fit = (Gtk.ContentFit) app.config.wallpaper_fit.clamp (0, 3);
            wallpaper.opacity = app.config.wallpaper_opacity.clamp (0, 100) / 100.0;
            wallpaper_dimmer.opacity = app.config.wallpaper_dim.clamp (0, 100) / 100.0;
            add_css_class ("has-wallpaper");
            update_background_opacity ();
        }

        private void update_background_opacity () {
            background.opacity = has_css_class ("has-wallpaper")
                ? 0
                : app.config.background_opacity.clamp (0, 100) / 100.0;
        }

        private void update_wallpaper_appearance () {
            if (!has_css_class ("has-wallpaper")) return;
            wallpaper.content_fit = (Gtk.ContentFit) app.config.wallpaper_fit.clamp (0, 3);
            wallpaper.opacity = app.config.wallpaper_opacity.clamp (0, 100) / 100.0;
            wallpaper_dimmer.opacity = app.config.wallpaper_dim.clamp (0, 100) / 100.0;
        }

        private void setup_keys () {
            var key_controller = new Gtk.EventControllerKey ();
            key_controller.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
            key_controller.key_pressed.connect ((keyval, keycode, state) => {
                if (keyval == Gdk.Key.Escape) {
                    close_grid ();
                    return true;
                }
                if ((keyval == Gdk.Key.Down || keyval == Gdk.Key.Up) &&
                    search_bar.is_searching () && content_stack.visible_child_name == "search") {
                    return search_bar.navigate_results (keyval == Gdk.Key.Down ? 1 : -1);
                }
                if ((keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) &&
                    search_bar.is_searching () && content_stack.visible_child_name == "search") {
                    return search_bar.activate_selected_result ();
                }
                // Arrow down from search → focus first tile
                if (keyval == Gdk.Key.Down && search_bar.search_entry.has_focus &&
                    !search_bar.is_searching () && content_stack.visible_child_name == "tiles") {
                    tile_grid.focus_first_tile ();
                    return true;
                }
                // Arrow up from tiles → back to search
                if (keyval == Gdk.Key.Up) {
                    if (tile_grid.is_at_top_row ()) {
                        search_bar.search_entry.grab_focus ();
                        return true;
                    }
                }
                return false;
            });
            ((Gtk.Widget) this).add_controller (key_controller);
        }

        private void setup_click_close () {
            var gesture = new Gtk.GestureClick ();
            gesture.pressed.connect ((n, x, y) => {
                if (app.config.window_mode != WindowMode.FULLSCREEN) return;
                var widget = pick (x, y, Gtk.PickFlags.DEFAULT);
                if (widget == this || widget == scrolled || widget is Gtk.Viewport) {
                    close_grid ();
                }
            });
            ((Gtk.Widget) this).add_controller (gesture);
        }

        private void setup_config_updates () {
            app.config.notify["wallpaper-path"].connect (() => {
                update_wallpaper ();
            });
            app.config.notify["wallpaper-fit"].connect (() => { update_wallpaper_appearance (); });
            app.config.notify["wallpaper-opacity"].connect (() => { update_wallpaper_appearance (); });
            app.config.notify["wallpaper-dim"].connect (() => { update_wallpaper_appearance (); });
            app.config.notify["background-opacity"].connect (() => { update_background_opacity (); });
            app.config.notify["layer"].connect (() => {
                apply_window_mode ();
            });
            app.config.notify["window-mode"].connect (() => {
                apply_window_mode ();
            });
            app.config.notify["monitor-index"].connect (() => {
                floating_monitor = null;
                apply_window_mode ();
            });
            app.config.notify["floating-x"].connect (() => {
                apply_window_mode ();
            });
            app.config.notify["floating-y"].connect (() => {
                apply_window_mode ();
            });
            app.config.notify["floating-width"].connect (() => {
                apply_window_mode ();
            });
            app.config.notify["floating-height"].connect (() => {
                apply_window_mode ();
            });
            app.config.notify["wofi-width"].connect (() => {
                apply_window_mode ();
            });
            app.config.notify["wofi-height"].connect (() => {
                apply_window_mode ();
            });
            app.config.notify["floating-x-percent"].connect (() => {
                apply_window_mode ();
            });
            app.config.notify["floating-y-percent"].connect (() => {
                apply_window_mode ();
            });
        }

        private void setup_focus_close () {
            var focus = new Gtk.EventControllerFocus ();
            focus.enter.connect (() => {
                if (app.config.window_mode != WindowMode.FLOATING && !wofi_mode) return;
                focus_leave_armed = true;
            });
            focus.leave.connect (() => {
                if (!visible) return;
                if (!app.config.close_on_focus_loss) return;
                if (app.config.window_mode != WindowMode.FLOATING && !wofi_mode) return;
                if (!focus_leave_armed) return;
                if (ignore_next_focus_leave) {
                    ignore_next_focus_leave = false;
                    return;
                }
                close_grid ();
            });
            ((Gtk.Widget) this).add_controller (focus);
        }

        private void apply_window_mode () {
            var effective_mode = wofi_mode ? WindowMode.FLOATING : app.config.window_mode;
            if (effective_mode == WindowMode.FLOATING) {
                var monitor = get_floating_monitor ();
                if (monitor != null) {
                    GtkLayerShell.set_monitor (this, monitor);
                }
            }

            int floating_x;
            int floating_y;
            int floating_width;
            int floating_height;
            get_floating_geometry (out floating_x, out floating_y, out floating_width, out floating_height);

            LayerShellHelper.apply_window_mode (
                this,
                effective_mode,
                LayerShellHelper.parse_layer (app.config.layer),
                floating_x,
                floating_y
            );

            if (effective_mode == WindowMode.FLOATING) {
                toast_overlay.width_request = floating_width;
                toast_overlay.height_request = floating_height;
            } else {
                toast_overlay.width_request = -1;
                toast_overlay.height_request = -1;
            }

            queue_resize ();
        }

        private void get_floating_geometry (
            out int x,
            out int y,
            out int width,
            out int height
        ) {
            int screen_width = 1920;
            int screen_height = 1080;

            var monitor = get_floating_monitor ();
            if (monitor != null) {
                var geometry = monitor.geometry;
                screen_width = geometry.width;
                screen_height = geometry.height;
            }

            width = (wofi_mode ? app.config.wofi_width : app.config.floating_width).clamp (320, 4096);
            height = (wofi_mode ? app.config.wofi_height : app.config.floating_height).clamp (240, 4096);

            int available_width = screen_width - width;
            int available_height = screen_height - height;
            if (available_width < 0) available_width = 0;
            if (available_height < 0) available_height = 0;

            x = available_width * app.config.floating_x_percent.clamp (0, 100) / 100;
            y = available_height * app.config.floating_y_percent.clamp (0, 100) / 100;
        }

        private Gdk.Monitor? get_floating_monitor () {
            if (floating_monitor != null) return floating_monitor;

            if (app.config.monitor_index < 0) {
                floating_monitor = get_compositor_active_monitor ();
                if (floating_monitor != null) return floating_monitor;

                floating_monitor = get_pointer_monitor ();
                if (floating_monitor != null) return floating_monitor;
            }

            var display = Gdk.Display.get_default ();
            if (display == null) return null;

            var monitors = display.get_monitors ();
            if (monitors.get_n_items () == 0) return null;

            var index = app.config.monitor_index.clamp (0, (int) monitors.get_n_items () - 1);
            floating_monitor = (Gdk.Monitor) monitors.get_item (index);
            return floating_monitor;
        }

        private Gdk.Monitor? get_pointer_monitor () {
            var display = Gdk.Display.get_default ();
            if (display == null) return null;

            var seat = display.get_default_seat ();
            if (seat == null) return null;

            var pointer = seat.get_pointer ();
            if (pointer == null) return null;

            double x;
            double y;
            var surface = pointer.get_surface_at_position (out x, out y);
            if (surface == null) return null;

            return display.get_monitor_at_surface (surface);
        }

        private Gdk.Monitor? get_compositor_active_monitor () {
            var connector = app.compositor_helper.get_active_monitor_connector ();
            if (connector == null || connector.length == 0) return null;
            return get_monitor_by_connector (connector);
        }

        private Gdk.Monitor? get_monitor_by_connector (string connector) {
            var display = Gdk.Display.get_default ();
            if (display == null) return null;

            var monitors = display.get_monitors ();
            for (uint i = 0; i < monitors.get_n_items (); i++) {
                var monitor = (Gdk.Monitor) monitors.get_item (i);
                var current_connector = monitor.get_connector ();
                if (current_connector == connector) return monitor;
            }

            return null;
        }

        public void open_grid () {
            wofi_mode = false;
            move_settings_button (false);
            remove_css_class ("wofi-mode");
            settings_btn.visible = true;
            search_bar.set_wofi_mode (false);
            search_bar.reset ();
            tile_grid.build_from_config ();
            content_stack.visible_child_name = "tiles";
            ignore_next_focus_leave = true;
            focus_leave_armed = false;
            floating_monitor = null;
            apply_window_mode ();

            set_visible (true);
            present ();

            search_bar.search_entry.grab_focus ();
        }

        public void open_wofi () {
            wofi_mode = true;
            move_settings_button (true);
            add_css_class ("wofi-mode");
            settings_btn.visible = true;
            search_bar.set_wofi_mode (true);
            search_bar.reset ();
            content_stack.visible_child_name = "search";
            ignore_next_focus_leave = true;
            focus_leave_armed = false;
            floating_monitor = null;
            apply_window_mode ();

            set_visible (true);
            present ();
            search_bar.search_entry.grab_focus ();
        }

        private void move_settings_button (bool to_bottom_corner) {
            if (to_bottom_corner == settings_in_root_overlay) return;

            if (to_bottom_corner) {
                top_overlay.remove_overlay (settings_btn);
                root_overlay.add_overlay (settings_btn);
                settings_btn.halign = Gtk.Align.END;
                settings_btn.valign = Gtk.Align.END;
                settings_btn.margin_top = 0;
                settings_btn.margin_end = 16;
                settings_btn.margin_bottom = 16;
            } else {
                root_overlay.remove_overlay (settings_btn);
                top_overlay.add_overlay (settings_btn);
                settings_btn.halign = Gtk.Align.END;
                settings_btn.valign = Gtk.Align.START;
                settings_btn.margin_top = 24;
                settings_btn.margin_end = 24;
                settings_btn.margin_bottom = 0;
            }
            settings_in_root_overlay = to_bottom_corner;
        }

        private void pin_to_dock (string desktop_id) {
            app.pin_to_dock (desktop_id);
        }

        private void close_grid () {
            ignore_next_focus_leave = false;
            focus_leave_armed = false;
            set_visible (false);
        }

        private void setup_popover_buttons (Gtk.Popover popover) {
            popover_buttons = new GenericArray<Gtk.Button> ();
            popover_focus_index = 0;

            var menu_box = popover.get_child ();
            if (menu_box == null) return;

            var child = menu_box.get_first_child ();
            while (child != null) {
                if (child is Gtk.Button && child.sensitive) {
                    popover_buttons.add ((Gtk.Button) child);
                }
                child = child.get_next_sibling ();
            }

            update_popover_highlight ();

            popover.closed.connect (() => {
                if (popover_buttons != null) {
                    clear_popover_highlight ();
                    popover_buttons = null;
                    popover_focus_index = -1;
                }
            });
        }

        private void update_popover_highlight () {
            if (popover_buttons == null) return;
            for (uint i = 0; i < popover_buttons.length; i++) {
                if ((int) i == popover_focus_index) {
                    popover_buttons[i].add_css_class ("popover-item-focused");
                } else {
                    popover_buttons[i].remove_css_class ("popover-item-focused");
                }
            }
        }

        private void clear_popover_highlight () {
            if (popover_buttons == null) return;
            for (uint i = 0; i < popover_buttons.length; i++) {
                popover_buttons[i].remove_css_class ("popover-item-focused");
            }
        }

        private void navigate_popover (int dy) {
            if (popover_buttons == null || popover_buttons.length == 0) return;
            popover_focus_index += dy;
            if (popover_focus_index < 0) popover_focus_index = (int) popover_buttons.length - 1;
            if (popover_focus_index >= (int) popover_buttons.length) popover_focus_index = 0;
            update_popover_highlight ();
        }

        private void activate_popover_focused () {
            if (popover_buttons == null || popover_focus_index < 0) return;
            if (popover_focus_index >= (int) popover_buttons.length) return;

            var btn = popover_buttons[popover_focus_index];

            // Clean up state BEFORE activation — activation may trigger rebuild
            clear_popover_highlight ();
            popover_buttons = null;
            popover_focus_index = -1;

            btn.activate ();
        }

        public void show_toast (string message) {
            var toast = new Adw.Toast (message);
            toast.timeout = 3;
            toast_overlay.add_toast (toast);
        }

        // --- Gamepad ---

        public void gamepad_navigate (int dx, int dy) {
            if (!visible) return;

            if (popover_buttons != null) {
                if (dy != 0) navigate_popover (dy);
                return;
            }

            if (content_stack.visible_child_name == "tiles") {
                if (dy < 0 && tile_grid.is_at_top_row ()) {
                    search_bar.search_entry.grab_focus ();
                } else {
                    tile_grid.gamepad_navigate (dx, dy);
                }
            }
        }

        public void gamepad_activate () {
            if (!visible) return;

            if (popover_buttons != null) {
                activate_popover_focused ();
                return;
            }

            tile_grid.gamepad_activate ();
        }

        public void gamepad_context_menu () {
            if (!visible || popover_buttons != null) return;
            tile_grid.gamepad_context_menu ();
            var popover = tile_grid.get_active_popover ();
            if (popover != null) {
                setup_popover_buttons (popover);
            }
        }

        public void gamepad_back () {
            if (!visible) return;

            if (popover_buttons != null) {
                var popover = tile_grid.get_active_popover ();
                if (popover != null) popover.popdown ();
                popover_buttons = null;
                popover_focus_index = -1;
                return;
            }

            if (tile_grid.has_open_folder ()) {
                tile_grid.gamepad_close_folder ();
            } else {
                close_grid ();
            }
        }

        public void gamepad_toggle () {
            if (popover_buttons != null) return;
            if (visible) {
                close_grid ();
            } else {
                open_grid ();
            }
        }

        public void gamepad_scroll (int direction) {
            if (!visible) return;
            if (popover_buttons != null) return;
            var adj = scrolled.vadjustment;
            adj.value += direction * adj.page_size * 0.3;
        }
    }
}
