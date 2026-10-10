namespace XimperShellLauncher {

    public class GridWindow : Gtk.Window {

        private weak Application app;
        private MenuTransition transition;
        public bool desired_open { get; private set; }
        private bool interactive;
        private ListModel monitor_model;
        private ulong monitors_handler;

        private static ulong watch_monitors (GridWindow window, ListModel monitors) {
            weak GridWindow owner = window;
            return monitors.items_changed.connect (() => {
                if (owner == null) return;
                owner.settle_transition ();
                owner.window_geometry.invalidate_monitor ();
                owner.apply_window_mode ();
            });
        }

        protected override void dispose () {
            if (monitors_handler != 0) {
                SignalHandler.disconnect (monitor_model, monitors_handler);
                monitors_handler = 0;
            }
            if (transition != null) transition.cancel ();
            base.dispose ();
        }

        private void update_input () {
            GtkLayerShell.set_keyboard_mode (this, desired_open ? GtkLayerShell.KeyboardMode.ON_DEMAND : GtkLayerShell.KeyboardMode.NONE);
            var surface = get_surface ();
            if (surface != null) {
                if (!desired_open) surface.set_input_region (new Cairo.Region ());
                else if (transition.hosted) {
                    var rect = transition.menu_rect;
                    Cairo.RectangleInt input = { rect.x, rect.y, rect.width, rect.height };
                    surface.set_input_region (new Cairo.Region.rectangle (input));
                } else surface.set_input_region (null);
            }
            // Keep theme state unchanged while gating all pointer/DnD input.
            root_overlay.can_target = interactive;
        }

        private void transition_settled () {
            transition.finish (desired_open);
            interactive = desired_open;
            remove_css_class ("menu-transitioning");
            update_input ();
            if (!desired_open) set_visible (false);

        }

        public void settle_transition () {
            transition.finish (desired_open);
            transition_settled ();
        }

        public void toggle_menu () {
            if (desired_open) close_grid (); else open_grid ();
        }
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
        private Gtk.Box browse_box;
        private CombinedView combined_view;
        private bool wofi_mode = false;
        private bool combined_mode = false;
        private bool focus_leave_armed = false;
        private WindowGeometry window_geometry;
        private PopoverNavigator popover_navigator;

        public GridWindow (Application app) {
            this.app = app;
            window_geometry = new WindowGeometry (app);
            popover_navigator = new PopoverNavigator ();
            this.title = "Ximper Shell Launcher";
            this.decorated = false;

            add_css_class ("grid-overlay");

            LayerShellHelper.setup_overlay (this, LayerShellHelper.parse_layer (app.config.layer));

            build_ui ();
            // Capture queued pointer/scroll/touch events as well as native input
            // gating, without making the animated subtree insensitive.
            var input_gate = new Gtk.EventControllerLegacy ();
            input_gate.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            input_gate.event.connect ((event) => {
                if (interactive) return false;
                var type = event.get_event_type ();
                return type != Gdk.EventType.KEY_PRESS && type != Gdk.EventType.KEY_RELEASE &&
                    type != Gdk.EventType.FOCUS_CHANGE;
            });
            ((Gtk.Widget) this).add_controller (input_gate);
            setup_keys ();
            setup_click_close ();
            setup_config_updates ();
            setup_focus_close ();
            apply_window_mode ();
            monitor_model = get_display ().get_monitors ();
            monitors_handler = watch_monitors (this, monitor_model);
        }

        private void build_ui () {
            var main_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            // Top bar: search
            top_overlay = new Gtk.Overlay ();

            search_bar = new SearchBar (app);
            search_bar.result_activated.connect (() => {
                close_grid ();
            });
            search_bar.search_changed.connect ((is_searching) => {
                update_content (is_searching);
            });
            top_overlay.set_child (search_bar);


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
            browse_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            browse_box.add_css_class ("application-browser");
            browse_box.append (scrolled);
            content_stack.add_named (browse_box, "tiles");
            combined_view = new CombinedView ();
            content_stack.add_named (combined_view, "combined");
            content_stack.add_named (search_bar.results_widget, "search");
            content_stack.visible_child_name = "tiles";

            main_box.append (content_stack);

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
            // A layer-shell window itself is transparent.  Clip all stacked
            // background layers to one rounded surface to prevent rectangular
            // translucent corners around the floating menu.
            root_overlay.overflow = Gtk.Overflow.HIDDEN;
            root_overlay.add_css_class ("floating-surface");
            root_overlay.set_child (background);
            root_overlay.add_overlay (wallpaper_layer);
            root_overlay.add_overlay (wallpaper_dimmer);
            root_overlay.add_overlay (toast_overlay);
            root_overlay.set_measure_overlay (toast_overlay, true);
            transition = new MenuTransition (root_overlay);
            transition.settled.connect (transition_settled);
            transition.allocation_changed.connect (update_input);
            set_child (transition);
            map.connect (() => { update_input (); });
            unmap.connect (() => {
                transition.finish (false);
                desired_open = false;
                interactive = false;
            });
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
                if (!interactive) {
                    if (keyval == Gdk.Key.Escape && desired_open) close_grid ();
                    return true;
                }
                // Let popovers handle their own keyboard navigation and Escape.
                if (search_bar.results_widget.has_open_popover || tile_grid.get_active_popover () != null)
                    return false;
                if (keyval == Gdk.Key.Escape) {
                    close_grid ();
                    return true;
                }
                if ((keyval == Gdk.Key.Down || keyval == Gdk.Key.Up) &&
                    list_navigation_active ()) {
                    return search_bar.navigate_results (keyval == Gdk.Key.Down ? 1 : -1);
                }
                if ((keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) &&
                    list_navigation_active ()) {
                    return search_bar.activate_selected_result ();
                }
                // Arrow down from search → focus first tile
                if (keyval == Gdk.Key.Down && search_bar.search_entry.has_focus &&
                    !search_bar.is_searching () && (combined_mode || content_stack.visible_child_name == "tiles")) {
                    if (combined_mode) search_bar.navigate_results (1);
                    else tile_grid.focus_first_tile ();
                    return true;
                }
                if (combined_mode && !search_bar.is_searching () &&
                    !search_bar.search_entry.has_focus &&
                    (keyval == Gdk.Key.Left || keyval == Gdk.Key.Right)) {
                    bool towards_tiles = app.config.app_list_side == AppListSide.LEFT
                        ? keyval == Gdk.Key.Right : keyval == Gdk.Key.Left;
                    if (list_has_focus () && towards_tiles) {
                        tile_grid.focus_first_tile ();
                        return true;
                    }
                    if (!list_has_focus () && !towards_tiles) {
                        search_bar.navigate_results (1);
                        return true;
                    }
                }
                // Arrow up from tiles → back to search
                if (keyval == Gdk.Key.Up) {
                    if (!list_has_focus () && tile_grid.is_at_top_row ()) {
                        search_bar.search_entry.grab_focus ();
                        return true;
                    }
                }
                return false;
            });
            ((Gtk.Widget) this).add_controller (key_controller);
        }

        private bool list_has_focus () {
            var focused = get_focus ();
            return focused != null && focused.is_ancestor (search_bar.results_widget);
        }

        private bool list_navigation_active () {
            return content_stack.visible_child_name == "search" ||
                (combined_mode && (search_bar.is_searching () || list_has_focus ()));
        }

        private void update_content (bool searching) {
            var list = search_bar.results_widget;
            if (combined_mode) {
                if (list.get_parent () != combined_view) {
                    content_stack.remove (list);
                    browse_box.remove (scrolled);
                    combined_view.attach (scrolled, list, app.config.app_list_side);
                }
                list.width_request = -1;
                list.hexpand = true;
                list.set_column_mode (false, true);
                combined_view.set_side (app.config.app_list_side);
                combined_view.set_searching (searching, visible);
                content_stack.transition_type = Gtk.StackTransitionType.NONE;
                content_stack.visible_child_name = "combined";
            } else {
                if (list.get_parent () == combined_view) {
                    combined_view.detach ();
                    browse_box.append (scrolled);
                    content_stack.add_named (list, "search");
                }
                list.set_column_mode (false, false);
                content_stack.transition_type = Gtk.StackTransitionType.CROSSFADE;
                content_stack.visible_child_name = searching || wofi_mode ? "search" : "tiles";
            }
        }

        private void configure_interface () {
            wofi_mode = app.config.launcher_mode == LauncherMode.WOFI;
            combined_mode = app.config.launcher_mode == LauncherMode.COMBINED;
            remove_css_class ("wofi-mode");
            remove_css_class ("combined-mode");
            if (wofi_mode) add_css_class ("wofi-mode");
            if (combined_mode) add_css_class ("combined-mode");
            search_bar.set_browse_mode (wofi_mode || combined_mode, app.config.app_list_sort);
            update_content (search_bar.is_searching ());
        }

        private void setup_click_close () {
            var gesture = new Gtk.GestureClick ();
            gesture.pressed.connect ((n, x, y) => {
                if (!interactive || app.config.window_mode != WindowMode.FULLSCREEN) return;
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
            app.config.output_changed.connect (() => {
                window_geometry.invalidate_monitor ();
                apply_window_mode ();
            });
            app.config.notify["floating-position"].connect (() => { apply_window_mode (); });
            app.config.notify["floating-margin"].connect (() => { apply_window_mode (); });
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
            app.config.notify["floating-x-percent"].connect (() => {
                apply_window_mode ();
            });
            app.config.notify["floating-y-percent"].connect (() => {
                apply_window_mode ();
            });
        }

        private void setup_focus_close () {
            // Widget focus can remain on the entry after another application
            // becomes active. Track toplevel activation, not descendant focus.
            notify["is-active"].connect (() => {
                if (!desired_open) return;
                if (is_active) {
                    focus_leave_armed = true;
                    return;
                }
                if (!focus_leave_armed || !app.config.close_on_focus_loss) return;
                if (app.config.window_mode != WindowMode.FLOATING) return;
                close_grid ();
            });
        }

        private void apply_window_mode () {
            if (transition != null && transition.running) settle_transition ();
            var effective_mode = app.config.window_mode;
            if (effective_mode == WindowMode.FLOATING) {
                var monitor = window_geometry.get_floating_monitor ();
                if (monitor != null) {
                    GtkLayerShell.set_monitor (this, monitor);
                }
            }

            int floating_x;
            int floating_y;
            int floating_width;
            int floating_height;
            int floating_margin;
            window_geometry.get_floating_geometry (out floating_x, out floating_y, out floating_width, out floating_height,
                                                   out floating_margin);

            bool host = effective_mode == WindowMode.FLOATING &&
                (app.config.animation_open.effect == AnimationEffect.SLIDE ||
                 app.config.animation_hide.effect == AnimationEffect.SLIDE);
            bool custom = app.config.floating_position == FloatingPosition.CUSTOM;
            transition.configure_host (host,
                custom ? -1 : app.config.floating_position.horizontal_alignment (),
                custom ? -1 : app.config.floating_position.vertical_alignment (),
                custom ? floating_x : floating_margin,
                custom ? floating_y : floating_margin);
            LayerShellHelper.apply_window_mode (
                this, host ? WindowMode.FULLSCREEN : effective_mode,
                LayerShellHelper.parse_layer (app.config.layer), floating_x, floating_y,
                app.config.floating_position, floating_margin
            );
            if (host) {
                // The compositor supplies the whole usable area; no global origin
                // or panel height is needed for placement within this surface.
                GtkLayerShell.set_exclusive_zone (this, 0);
                remove_css_class ("fullscreen");
                add_css_class ("floating");
                add_css_class ("slide-host");
            } else remove_css_class ("slide-host");

            if (effective_mode == WindowMode.FLOATING) {
                toast_overlay.width_request = floating_width;
                toast_overlay.height_request = floating_height;
            } else {
                toast_overlay.width_request = -1;
                toast_overlay.height_request = -1;
            }

            update_input ();
            queue_resize ();
        }

        public void reload_from_config () {
            configure_interface ();
            search_bar.refresh ();
            tile_grid.build_from_config ();
            update_wallpaper ();
            update_wallpaper_appearance ();
            update_background_opacity ();
            window_geometry.invalidate_monitor ();
            apply_window_mode ();
        }

        public void open_grid () {
            if (desired_open) return;
            bool fresh = !visible;
            if (fresh) {
                configure_interface ();
                search_bar.reset ();
                tile_grid.build_from_config ();
                update_content (false);
                window_geometry.invalidate_monitor ();
                apply_window_mode ();
                transition.prepare (app.config.animation_open.copy ());
            }
            focus_leave_armed = is_active;
            desired_open = true;
            interactive = false;
            add_css_class ("menu-transitioning");
            update_input ();
            set_visible (true);
            present ();
            // Choose the initial focus now, not after the animation: a genuine
            // leave during opening must dismiss rather than refocus later.
            search_bar.search_entry.grab_focus ();
            if (desired_open)
                transition.transition (true, app.config.animation_open.copy ());
        }

        public void open_wofi () {
            open_grid ();
        }


        private void pin_to_dock (string desktop_id) {
            app.pin_to_dock (desktop_id);
        }

        private void close_grid () {
            focus_leave_armed = false;
            if (!desired_open) return;
            desired_open = false;
            interactive = false;
            var popover = search_bar.results_widget.get_active_popover ();
            if (popover != null) popover.popdown ();
            popover = tile_grid.get_active_popover ();
            if (popover != null) popover.popdown ();
            popover_navigator.reset ();
            add_css_class ("menu-transitioning");
            update_input ();
            transition.transition (false, app.config.animation_hide.copy ());
        }

        public void show_toast (string message) {
            var toast = new Adw.Toast (message);
            toast.timeout = 3;
            toast_overlay.add_toast (toast);
        }

        // --- Gamepad ---

        public void gamepad_navigate (int dx, int dy) {
            if (!interactive) return;

            if (popover_navigator.active) {
                if (dy != 0) popover_navigator.navigate (dy);
                return;
            }

            if (list_navigation_active () || (combined_mode && search_bar.search_entry.has_focus)) {
                if (dy != 0) search_bar.navigate_results (dy);
                else if (dx != 0 && combined_mode && !search_bar.is_searching ())
                    tile_grid.focus_first_tile ();
            } else if (combined_mode || content_stack.visible_child_name == "tiles") {
                if (dy < 0 && tile_grid.is_at_top_row ()) {
                    search_bar.search_entry.grab_focus ();
                } else {
                    tile_grid.gamepad_navigate (dx, dy);
                }
            }
        }

        public void gamepad_activate () {
            if (!interactive) return;

            if (popover_navigator.active) {
                popover_navigator.activate_focused ();
                return;
            }

            if (list_navigation_active ()) search_bar.activate_selected_result ();
            else tile_grid.gamepad_activate ();
        }

        public void gamepad_context_menu () {
            if (!interactive || popover_navigator.active) return;
            if (list_navigation_active ()) search_bar.results_widget.open_selected_context_menu ();
            else tile_grid.gamepad_context_menu ();
            var popover = search_bar.results_widget.get_active_popover () ?? tile_grid.get_active_popover ();
            if (popover != null) {
                popover_navigator.attach (popover);
            }
        }

        public void gamepad_back () {
            if (!interactive) { if (desired_open) close_grid (); return; }

            if (popover_navigator.active) {
                var popover = search_bar.results_widget.get_active_popover () ?? tile_grid.get_active_popover ();
                if (popover != null) popover.popdown ();
                popover_navigator.reset ();
                return;
            }

            if (search_bar.results_widget.has_open_popover) {
                search_bar.results_widget.get_active_popover ().popdown ();
                return;
            }
            if (tile_grid.has_open_folder ()) {
                tile_grid.gamepad_close_folder ();
            } else {
                close_grid ();
            }
        }

        public void gamepad_toggle () {
            if (popover_navigator.active) return;
            toggle_menu ();
        }

        public void gamepad_scroll (int direction) {
            if (!interactive) return;
            if (popover_navigator.active) return;
            var adj = list_navigation_active ()
                ? search_bar.results_widget.vadjustment : scrolled.vadjustment;
            adj.value += direction * adj.page_size * 0.3;
        }
    }
}
