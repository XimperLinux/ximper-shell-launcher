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
            cancel_tile_focus_restore ();
            if (action_sidebar != null) action_sidebar.cancel_pending ();
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
        public bool layout_busy { get { return tile_grid != null && tile_grid.other_board_dragging (); } }
        private bool horizontal_tiles { get { return app.config.groups_enabled && app.config.group_layout == GroupLayout.HORIZONTAL; } }
        private Gtk.ScrolledWindow scrolled;
        private weak Gtk.Viewport tile_focus_viewport;
        private uint tile_layout_depth;
        private bool tile_focus_dragging;
        private Gdk.FrameClock? tile_focus_clock;
        private ulong tile_focus_after_paint;
        private uint tile_drag_scroll_tick;
        private bool tile_drag_hovering;
        private double tile_drag_x;
        private double tile_drag_y;
        private Gtk.Stack content_stack;
        private Adw.ToastOverlay toast_overlay;
        private Gtk.Box background;
        private Gtk.Picture wallpaper;
        private Gtk.Box wallpaper_dimmer;
        private Gtk.Overlay top_overlay;
        private Gtk.Overlay root_overlay;
        private Gtk.Box browse_box;
        private Gtk.Box main_box;
        private Gtk.Box panel_host;
        private ActionSidebar action_sidebar;
        private SidebarWeakReference? sidebar_return_focus;
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
                if (interactive) {
                    if (action_sidebar != null && !action_sidebar.contains_focus) remember_sidebar_focus ();
                    return false;
                }
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
            main_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            main_box.hexpand = true;
            main_box.vexpand = true;

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
            var tile_scroll = new Gtk.EventControllerScroll (Gtk.EventControllerScrollFlags.BOTH_AXES);
            tile_scroll.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
            tile_scroll.scroll.connect ((dx, dy) => {
                if (!horizontal_tiles || dx != 0 || dy == 0) return false;
                // Mouse wheels produce vertical deltas: in the horizontal tile
                // area they scroll sideways, without affecting the app list.
                var adjustment = scrolled.hadjustment;
                double step = tile_scroll.get_unit () == Gdk.ScrollUnit.WHEEL
                    ? double.max (32, adjustment.step_increment) : 1;
                adjustment.value += dy * step;
                return true;
            });
            scrolled.add_controller (tile_scroll);

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
            var tile_viewport = tile_grid.get_parent () as Gtk.Viewport;
            if (tile_viewport != null) tile_viewport.scroll_to_focus = true;
            weak GridWindow drag_window = this;
            tile_focus_viewport = tile_viewport;
            if (tile_viewport != null) tile_viewport.unmap.connect (() => {
                var window = drag_window;
                if (window != null) window.update_tile_focus_guard ();
            });
            tile_grid.drag_state_changed.connect ((active) => {
                var window = drag_window;
                if (window == null) return;
                window.tile_focus_dragging = active;
                window.update_tile_focus_guard ();
                if (!active) window.stop_tile_drag_scroll ();
            });
            tile_grid.layout_changing.connect ((active) => {
                var window = drag_window;
                if (window == null) return;
                if (active) window.tile_layout_depth++;
                else if (window.tile_layout_depth > 0) window.tile_layout_depth--;
                window.update_tile_focus_guard ();
            });
            scrolled.hadjustment.notify["page-size"].connect (() => {
                var window = drag_window;
                if (window != null) window.update_tile_drop_tail ();
            });
            scrolled.vadjustment.notify["page-size"].connect (() => {
                var window = drag_window;
                if (window != null) window.update_tile_drop_tail ();
            });
            var drag_motion = new Gtk.DropControllerMotion ();
            drag_motion.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
            drag_motion.enter.connect ((x, y) => {
                var window = drag_window;
                if (window != null) window.track_tile_drag_pointer (x, y);
            });
            drag_motion.motion.connect ((x, y) => {
                var window = drag_window;
                if (window != null) window.track_tile_drag_pointer (x, y);
            });
            drag_motion.leave.connect (() => {
                var window = drag_window;
                if (window != null) window.stop_tile_drag_scroll ();
            });
            scrolled.add_controller (drag_motion);
            update_tile_drop_tail ();
            browse_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            browse_box.add_css_class ("application-browser");
            browse_box.append (scrolled);
            content_stack.add_named (browse_box, "tiles");
            combined_view = new CombinedView ();
            content_stack.add_named (combined_view, "combined");
            content_stack.add_named (search_bar.results_widget, "search");
            content_stack.visible_child_name = "tiles";

            main_box.append (content_stack);

            panel_host = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            panel_host.append (main_box);
            action_sidebar = new ActionSidebar ();
            connect_sidebar_signals (this);
            configure_sidebar ();
            toast_overlay = new Adw.ToastOverlay ();
            toast_overlay.set_child (panel_host);
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

        private static void connect_sidebar_signals (GridWindow window) {
            var reference = new SidebarWeakReference (window);
            window.action_sidebar.close_requested.connect (() => {
                var owner = reference.get () as GridWindow;
                if (owner != null) owner.close_grid ();
            });
            window.action_sidebar.error.connect ((message) => {
                var owner = reference.get () as GridWindow;
                if (owner != null && owner.desired_open) owner.show_toast (message);
            });
        }

        private void remember_sidebar_focus () {
            var focus = get_focus ();
            if (focus == null) sidebar_return_focus = null;
            else if (sidebar_return_focus == null || sidebar_return_focus.get () != focus)
                sidebar_return_focus = new SidebarWeakReference (focus);
        }

        private bool focus_sidebar () {
            remember_sidebar_focus ();
            return action_sidebar.focus_first ();
        }

        private void configure_sidebar () {
            bool focused = action_sidebar.contains_focus;
            if (focused) search_bar.search_entry.grab_focus ();
            var parent = action_sidebar.get_parent () as Gtk.Box;
            if (parent != null) parent.remove (action_sidebar);
            action_sidebar.configure (app.config.sidebar);
            if (!app.config.sidebar.enabled) return;
            switch (app.config.sidebar.position) {
                case SidebarPosition.LEFT: panel_host.prepend (action_sidebar); break;
                case SidebarPosition.RIGHT: panel_host.append (action_sidebar); break;
                case SidebarPosition.ABOVE_SEARCH: main_box.prepend (action_sidebar); break;
                case SidebarPosition.BELOW_SEARCH: main_box.insert_child_after (action_sidebar, top_overlay); break;
            }
        }

        private bool towards_sidebar (int dx, int dy) {
            if (!action_sidebar.visible) return false;
            switch (app.config.sidebar.position) {
                case SidebarPosition.LEFT: return dx < 0;
                case SidebarPosition.RIGHT: return dx > 0;
                case SidebarPosition.ABOVE_SEARCH: return dy < 0;
                case SidebarPosition.BELOW_SEARCH: return dy < 0;
            }
            return false;
        }

        private void leave_sidebar (int dx = 0, int dy = 0) {
            var position = app.config.sidebar.position;
            if (dx != 0 || dy != 0) {
                if (position == SidebarPosition.LEFT && dx < 0) return;
                if (position == SidebarPosition.RIGHT && dx > 0) return;
                if (position == SidebarPosition.ABOVE_SEARCH && dy < 0) return;
                if (position == SidebarPosition.BELOW_SEARCH && dy > 0) {
                    if (wofi_mode || combined_mode || search_bar.is_searching ()) search_bar.navigate_results (1);
                    else tile_grid.focus_first_tile ();
                    return;
                }
                if (action_sidebar.horizontal) { search_bar.search_entry.grab_focus (); return; }
            }
            var focus = sidebar_return_focus != null ? sidebar_return_focus.get () as Gtk.Widget : null;
            if (focus != null && focus.get_mapped () && focus.get_root () == this)
                focus.grab_focus ();
            else search_bar.search_entry.grab_focus ();
        }

        private bool enter_sidebar (int dx, int dy) {
            if (!action_sidebar.visible) return false;
            var position = app.config.sidebar.position;
            if (search_bar.search_entry.has_focus && position == SidebarPosition.BELOW_SEARCH && dy > 0)
                return focus_sidebar ();
            if (!towards_sidebar (dx, dy)) return false;
            if (action_sidebar.horizontal && list_has_focus () && dy < 0 && search_bar.results_widget.at_start) {
                if (position == SidebarPosition.ABOVE_SEARCH) { search_bar.search_entry.grab_focus (); return true; }
                return focus_sidebar ();
            }
            bool can_enter = search_bar.search_entry.has_focus;
            if (list_has_focus () && !action_sidebar.horizontal) {
                can_enter = !combined_mode || search_bar.is_searching () ||
                    (app.config.sidebar.position == SidebarPosition.LEFT && app.config.app_list_side == AppListSide.LEFT) ||
                    (app.config.sidebar.position == SidebarPosition.RIGHT && app.config.app_list_side == AppListSide.RIGHT);
            }
            if (can_enter) return focus_sidebar ();
            var focus = get_focus ();
            if (focus != null && focus.is_ancestor (tile_grid) &&
                (!action_sidebar.horizontal || (position == SidebarPosition.BELOW_SEARCH && tile_grid.is_at_top_row ()))) {
                remember_sidebar_focus ();
                tile_grid.gamepad_navigate (dx, dy);
                if (get_focus () == focus) action_sidebar.focus_first ();
                return true;
            }
            return false;
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
                if (action_sidebar.visible) {
                    if (action_sidebar.has_popup) {
                        if (action_sidebar.handle_key (keyval)) return true;
                        return false;
                    }
                    if (action_sidebar.contains_focus) {
                        if (action_sidebar.handle_key (keyval)) return true;
                        if (keyval == Gdk.Key.Left || keyval == Gdk.Key.Right || keyval == Gdk.Key.Up || keyval == Gdk.Key.Down) {
                            int dx = keyval == Gdk.Key.Left ? -1 : keyval == Gdk.Key.Right ? 1 : 0;
                            int dy = keyval == Gdk.Key.Up ? -1 : keyval == Gdk.Key.Down ? 1 : 0;
                            leave_sidebar (dx, dy);
                            return true;
                        }
                        // Tab is handled natively, never by list shortcuts.
                        if (keyval != Gdk.Key.Escape) return false;
                    } else if (!search_bar.results_widget.has_open_popover && tile_grid.get_active_popover () == null) {
                        if (search_bar.search_entry.has_focus &&
                            ((keyval == Gdk.Key.Up && app.config.sidebar.position == SidebarPosition.ABOVE_SEARCH) ||
                             (keyval == Gdk.Key.Down && app.config.sidebar.position == SidebarPosition.BELOW_SEARCH))) {
                            if (focus_sidebar ()) return true;
                        } else if (!search_bar.search_entry.has_focus) {
                            int dx = keyval == Gdk.Key.Left ? -1 : keyval == Gdk.Key.Right ? 1 : 0;
                            int dy = keyval == Gdk.Key.Up ? -1 : keyval == Gdk.Key.Down ? 1 : 0;
                            if ((dx != 0 || dy != 0) && enter_sidebar (dx, dy)) return true;
                        }
                    }
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
            scrolled.hscrollbar_policy = horizontal_tiles
                ? Gtk.PolicyType.AUTOMATIC : Gtk.PolicyType.NEVER;
            scrolled.vscrollbar_policy = horizontal_tiles
                ? Gtk.PolicyType.NEVER : Gtk.PolicyType.AUTOMATIC;
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
                if (widget != null && (widget == action_sidebar || widget.is_ancestor (action_sidebar))) return;
                if (widget == this || widget == scrolled || widget is Gtk.Viewport) {
                    close_grid ();
                }
            });
            ((Gtk.Widget) this).add_controller (gesture);
        }

        private void setup_config_updates () {
            app.config.launcher_layout_changed.connect (() => { tile_grid.build_from_config (); });
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
            configure_sidebar ();
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
            action_sidebar.cancel_pending ();
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
            if (action_sidebar.visible && (action_sidebar.has_popup || action_sidebar.contains_focus)) {
                if (!action_sidebar.navigate (dx, dy) && !action_sidebar.has_popup) leave_sidebar (dx, dy);
                return;
            }

            if (popover_navigator.active) {
                if (dy != 0) popover_navigator.navigate (dy);
                return;
            }

            if (enter_sidebar (dx, dy)) return;
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
            if (action_sidebar.visible && (action_sidebar.has_popup || action_sidebar.contains_focus)) {
                action_sidebar.activate_focused ();
                return;
            }

            if (popover_navigator.active) {
                popover_navigator.activate_focused ();
                return;
            }

            if (list_navigation_active ()) search_bar.activate_selected_result ();
            else tile_grid.gamepad_activate ();
        }

        public void gamepad_context_menu () {
            if (!interactive || popover_navigator.active || action_sidebar.has_popup || action_sidebar.contains_focus) return;
            if (list_navigation_active ()) search_bar.results_widget.open_selected_context_menu ();
            else tile_grid.gamepad_context_menu ();
            var popover = search_bar.results_widget.get_active_popover () ?? tile_grid.get_active_popover ();
            if (popover != null) {
                popover_navigator.attach (popover);
            }
        }

        public void gamepad_back () {
            if (!interactive) { if (desired_open) close_grid (); return; }
            if (action_sidebar.back ()) return;
            if (action_sidebar.contains_focus) { leave_sidebar (); return; }

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
            if (popover_navigator.active || action_sidebar.has_popup) return;
            toggle_menu ();
        }

        private void update_tile_drop_tail () {
            tile_grid.set_drop_viewport_size ((int) scrolled.hadjustment.page_size,
                (int) scrolled.vadjustment.page_size);
        }

        private void cancel_tile_focus_restore () {
            if (tile_focus_after_paint != 0) {
                SignalHandler.disconnect (tile_focus_clock, tile_focus_after_paint);
                tile_focus_after_paint = 0;
            }
            tile_focus_clock = null;
        }

        private bool tile_focus_guard_busy () {
            return tile_focus_dragging || tile_layout_depth > 0 ||
                (tile_grid != null && tile_grid.other_board_dragging ());
        }

        private void update_tile_focus_guard () {
            cancel_tile_focus_restore ();
            if (tile_focus_viewport == null) return;
            tile_focus_viewport.scroll_to_focus = false;
            if (tile_focus_guard_busy ()) return;

            // Drag-end precedes the HIGH_IDLE root rebuild. Reconnect only
            // after GTK has allocated and painted the replacement children.
            var clock = tile_focus_viewport.get_frame_clock ();
            if (!tile_focus_viewport.get_mapped () || clock == null) {
                // No visible layout/focus work can run here; the setter itself
                // does not scroll. Do not leave hidden/no-clock views disabled.
                tile_focus_viewport.scroll_to_focus = true;
                return;
            }
            tile_focus_clock = clock;
            weak GridWindow owner = this;
            tile_focus_after_paint = clock.after_paint.connect (() => {
                var window = owner;
                if (window == null) return;
                window.cancel_tile_focus_restore ();
                if (!window.tile_focus_guard_busy () && window.tile_focus_viewport != null)
                    window.tile_focus_viewport.scroll_to_focus = true;
            });
            clock.request_phase (Gdk.FrameClockPhase.LAYOUT | Gdk.FrameClockPhase.AFTER_PAINT);
        }

        private void stop_tile_drag_scroll () {
            tile_drag_hovering = false;
            if (tile_drag_scroll_tick != 0) {
                scrolled.remove_tick_callback (tile_drag_scroll_tick);
                tile_drag_scroll_tick = 0;
            }
        }

        private void track_tile_drag_pointer (double x, double y) {
            tile_drag_x = x;
            tile_drag_y = y;
            tile_drag_hovering = true;
            if (tile_drag_scroll_tick != 0 || !tile_grid.has_active_drag) return;
            weak GridWindow owner = this;
            int64 previous_time = 0;
            tile_drag_scroll_tick = scrolled.add_tick_callback ((widget, clock) => {
                var window = owner;
                if (window == null) return Source.REMOVE;
                if (!window.tile_drag_hovering || !window.tile_grid.has_active_drag || !window.interactive) {
                    window.tile_drag_scroll_tick = 0;
                    return Source.REMOVE;
                }
                int64 now = clock.get_frame_time ();
                double dt = previous_time == 0 ? 0 : double.min (0.05, (now - previous_time) / 1000000.0);
                previous_time = now;
                bool horizontal = window.horizontal_tiles;
                double extent = horizontal ? widget.get_width () : widget.get_height ();
                double position = horizontal ? window.tile_drag_x : window.tile_drag_y;
                double edge = double.min (48, extent / 4);
                double proximity = 0;
                if (edge > 0 && position < edge) proximity = -double.min (1, (edge - position) / edge);
                else if (edge > 0 && position > extent - edge) proximity = double.min (1, (position - extent + edge) / edge);
                if (proximity != 0) {
                    var adjustment = horizontal ? window.scrolled.hadjustment : window.scrolled.vadjustment;
                    double speed = (proximity < 0 ? -1 : 1) * (80 + 420 * proximity.abs ());
                    adjustment.value += speed * dt;
                }
                return Source.CONTINUE;
            });
        }

        public void gamepad_scroll (int direction) {
            if (!interactive) return;
            if (popover_navigator.active) return;
            if (action_sidebar.has_popup || action_sidebar.contains_focus) return;
            var adj = list_navigation_active ()
                ? search_bar.results_widget.vadjustment :
                (horizontal_tiles ? scrolled.hadjustment : scrolled.vadjustment);
            adj.value += direction * adj.page_size * 0.3;
        }
    }
}
