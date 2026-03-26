namespace XimperShellTileMenu {

    public class TileGrid : Gtk.Box {

        private weak Application app;
        private TileBoard? board;

        public signal void tile_activated (AppEntry entry);
        public signal void pin_requested (string desktop_id);
        public signal void unpin_requested (string desktop_id);

        public TileGrid (Application app) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.app = app;

            add_css_class ("tile-grid");
            hexpand = true;
            valign = Gtk.Align.START;
            margin_top = 16;
            margin_bottom = 16;

            build_from_config ();
        }

        public void build_from_config () {
            var child = get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                remove (child);
                child = next;
            }

            // Build unified tile list
            var all_tiles = new GenericArray<TileConfig> ();
            var known_ids = new HashTable<string, bool> (str_hash, str_equal);

            var groups = app.config.groups;
            if (groups != null) {
                for (uint i = 0; i < groups.length; i++) {
                    for (uint j = 0; j < groups[i].tiles.length; j++) {
                        var tc = groups[i].tiles[j];
                        all_tiles.add (tc);
                        if (tc.folder_items != null) {
                            for (uint k = 0; k < tc.folder_items.length; k++) {
                                known_ids.insert (tc.folder_items[k], true);
                            }
                        }
                        if (tc.size != TileSize.FOLDER) {
                            known_ids.insert (tc.desktop_id, true);
                        }
                    }
                }
            }

            // Add ungrouped
            var all_apps = app.app_provider.apps;
            for (uint i = 0; i < all_apps.length; i++) {
                var id = all_apps[i].desktop_id;
                if (!known_ids.contains (id)) {
                    all_tiles.add (new TileConfig (id, TileSize.SMALL));
                }
            }

            board = new TileBoard (app, all_tiles);
            board.tile_activated.connect ((entry) => {
                tile_activated (entry);
            });
            board.layout_changed.connect (() => {
                save_layout ();
            });
            board.pin_requested.connect ((id) => {
                pin_requested (id);
            });
            board.unpin_requested.connect ((id) => {
                unpin_requested (id);
            });
            append (board);
        }

        public void extract_from_open_folder (string desktop_id) {
            if (board != null) {
                board.try_extract_from_folder (desktop_id);
            }
        }

        public void focus_first_tile () {
            if (board != null) {
                board.focus_first ();
            }
        }

        public bool is_at_top_row () {
            if (board == null) return true;
            int idx = board.get_focused_index ();
            if (idx < 0) return true;
            // Check if focused widget is in the first row (y ~ 0)
            int y = board.get_focused_y ();
            return y < 10;
        }

        public void gamepad_navigate (int dx, int dy) {
            if (board != null) board.navigate_focus (dx, dy);
        }

        public void gamepad_activate () {
            if (board != null) board.activate_focused ();
        }

        public bool has_open_folder () {
            return board != null && board.has_open_folder ();
        }

        public Gtk.Popover? get_active_popover () {
            return board != null ? board.get_active_popover () : null;
        }

        public void gamepad_context_menu () {
            if (board != null) board.show_focused_context_menu ();
        }

        public void gamepad_close_folder () {
            if (board != null) board.close_open_folder ();
        }

        public void save_layout () {
            if (board == null) return;
            var new_groups = new GenericArray<GroupConfig> ();
            new_groups.add (board.to_config (""));
            app.config.groups = new_groups;
            app.config.save ();
        }
    }
}
