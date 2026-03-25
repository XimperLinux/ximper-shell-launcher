namespace XimperShellTileMenu {

    public class GridWindow : Gtk.Window {

        private weak Application app;
        private SearchBar search_bar;
        private TileGrid tile_grid;
        private Gtk.ScrolledWindow scrolled;
        private Gtk.Stack content_stack;

        public GridWindow (Application app) {
            this.app = app;
            this.title = "Ximper Shell Tile Menu";
            this.decorated = false;

            add_css_class ("grid-overlay");

            LayerShellHelper.setup_overlay (this, LayerShellHelper.parse_layer (app.config.layer));

            build_ui ();
            setup_keys ();
            setup_click_close ();
        }

        private void build_ui () {
            var main_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            // Top bar: search + settings button
            var top_overlay = new Gtk.Overlay ();

            search_bar = new SearchBar (app);
            search_bar.result_activated.connect (() => {
                close_grid ();
            });
            search_bar.search_changed.connect ((is_searching) => {
                content_stack.visible_child_name = is_searching ? "search" : "tiles";
            });
            top_overlay.set_child (search_bar);

            var settings_btn = new Gtk.Button.from_icon_name ("emblem-system-symbolic");
            settings_btn.add_css_class ("flat");
            settings_btn.add_css_class ("circular");
            settings_btn.tooltip_text = "Settings";
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

            set_child (main_box);
        }

        private void setup_keys () {
            var key_controller = new Gtk.EventControllerKey ();
            key_controller.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
            key_controller.key_pressed.connect ((keyval, keycode, state) => {
                if (keyval == Gdk.Key.Escape) {
                    close_grid ();
                    return true;
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
                var widget = pick (x, y, Gtk.PickFlags.DEFAULT);
                if (widget == this || widget == scrolled || widget is Gtk.Viewport) {
                    close_grid ();
                }
            });
            ((Gtk.Widget) this).add_controller (gesture);
        }

        public void open_grid () {
            search_bar.reset ();
            tile_grid.build_from_config ();
            content_stack.visible_child_name = "tiles";

            set_visible (true);

            search_bar.search_entry.grab_focus ();
        }

        private void pin_to_dock (string desktop_id) {
            app.pin_to_dock (desktop_id);
        }

        private void close_grid () {
            set_visible (false);
        }
    }
}
