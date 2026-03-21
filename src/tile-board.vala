namespace XimperShellTileMenu {

    private class CellPlacement {
        public int col;
        public int row;
        public int col_span;
        public int row_span;
        public int config_index;
        public CellPlacement (int c, int r, int cs, int rs, int idx) {
            col = c; row = r; col_span = cs; row_span = rs; config_index = idx;
        }
    }

    public class TileBoard : Gtk.Widget {

        private weak Application app;
        private GenericArray<TileConfig> tile_configs;

        private int columns = 10;
        private int cell_size = 80;
        private const int SPACING = 6;
        private const int MARGIN = 24;

        // Folder expansion
        private string? open_folder_id = null;
        private int folder_insert_after_row = -1;
        private GenericArray<Gtk.Widget> all_widgets;
        private Gtk.Widget? folder_widget = null;

        // Animation
        private double anim_progress = 1.0; // 0 = closed, 1 = fully open (slide)
        private double cascade_progress = 1.0; // 0 = hidden, 1 = all visible
        private int target_folder_height = 0;
        private int folder_item_count_cached = 0;
        private Adw.TimedAnimation? cascade_anim = null;
        private Adw.TimedAnimation? folder_anim = null;

        public signal void layout_changed ();
        public signal void tile_activated (AppEntry entry);
        public signal void pin_requested (string desktop_id);
        public signal void unpin_requested (string desktop_id);

        public TileBoard (Application app, GenericArray<TileConfig> configs) {
            this.app = app;
            this.tile_configs = configs;
            this.all_widgets = new GenericArray<Gtk.Widget> ();

            set_layout_manager (null);
            hexpand = true;
            focusable = true;

            setup_keyboard ();
            compute_layout ();
            rebuild ();
        }

        private void setup_keyboard () {
            var key_controller = new Gtk.EventControllerKey ();
            key_controller.key_pressed.connect ((keyval, keycode, state) => {
                switch (keyval) {
                    case Gdk.Key.Left:
                        return move_focus (-1, 0);
                    case Gdk.Key.Right:
                        return move_focus (1, 0);
                    case Gdk.Key.Up:
                        return move_focus (0, -1);
                    case Gdk.Key.Down:
                        return move_focus (0, 1);
                    case Gdk.Key.Return:
                    case Gdk.Key.KP_Enter:
                    case Gdk.Key.space:
                        return activate_focused ();
                    default:
                        return false;
                }
            });
            ((Gtk.Widget) this).add_controller (key_controller);
        }

        public int get_focused_index () {
            for (uint i = 0; i < all_widgets.length; i++) {
                if (all_widgets[i].has_focus || all_widgets[i].has_css_class ("tile-focused")) {
                    return (int) i;
                }
            }
            return -1;
        }

        public int get_focused_y () {
            int idx = get_focused_index ();
            if (idx < 0) return 0;
            return get_visual_y (all_widgets[idx]);
        }

        public void focus_first () {
            if (all_widgets.length > 0) {
                set_tile_focus (0);
            }
        }

        private void set_tile_focus (int idx) {
            // Remove old focus
            for (uint i = 0; i < all_widgets.length; i++) {
                all_widgets[i].remove_css_class ("tile-focused");
            }
            if (idx >= 0 && idx < (int) all_widgets.length) {
                all_widgets[idx].add_css_class ("tile-focused");
                all_widgets[idx].grab_focus ();
            }
        }

        private int compute_tile_offset (int tile_x, int tile_w, int tile_y) {
            if (open_folder_id == null || folder_insert_after_row < 0) return target_folder_height;

            // For tiles starting below the folder row, standard offset
            int folder_row_bottom = (folder_insert_after_row + 1) * (cell_size + SPACING);
            if (tile_y >= folder_row_bottom) return target_folder_height;

            // For large tiles starting at folder row — check how many
            // folder content rows actually reach this tile's columns
            int tile_col_start = (tile_x - MARGIN) / (cell_size + SPACING);

            int total_folder_rows = (folder_item_count_cached + columns - 1) / columns;
            int last_row_items = folder_item_count_cached % columns;
            if (last_row_items == 0 && folder_item_count_cached > 0) last_row_items = columns;

            int effective_rows = total_folder_rows;
            if (tile_col_start >= last_row_items) {
                effective_rows = total_folder_rows - 1;
                if (effective_rows < 0) effective_rows = 0;
            }

            int header_h = 32 + SPACING;
            int content_y = (folder_insert_after_row + 1) * (cell_size + SPACING) + header_h;
            int fcb = content_y + effective_rows * (cell_size + SPACING);
            return fcb - tile_y;
        }

        private int get_visual_y (Gtk.Widget w) {
            int y = w.get_data<int> ("board-y");
            bool below = w.get_data<bool> ("board-below");
            if (below) {
                int uo = target_folder_height;
                for (uint j = 0; j < all_widgets.length; j++) {
                    if (!all_widgets[j].get_data<bool> ("board-below")) continue;
                    int needed = compute_tile_offset (
                        all_widgets[j].get_data<int> ("board-x"),
                        all_widgets[j].get_data<int> ("board-w"),
                        all_widgets[j].get_data<int> ("board-y"));
                    if (needed > uo) uo = needed;
                }
                y += (int) (uo * anim_progress);
            }
            return y;
        }

        private bool move_focus (int dx, int dy) {
            int current = get_focused_index ();
            if (current < 0) {
                if (all_widgets.length > 0) {
                    set_tile_focus (0);
                    return true;
                }
                return false;
            }

            int cur_x = all_widgets[current].get_data<int> ("board-x");
            int cur_y = get_visual_y (all_widgets[current]);
            int cur_w = all_widgets[current].get_data<int> ("board-w");
            int cur_h = all_widgets[current].get_data<int> ("board-h");
            int cx = cur_x + cur_w / 2;
            int cy = cur_y + cur_h / 2;

            int best = -1;
            int best_dist = int.MAX;

            for (uint i = 0; i < all_widgets.length; i++) {
                if ((int) i == current) continue;

                int wx = all_widgets[i].get_data<int> ("board-x");
                int wy = get_visual_y (all_widgets[i]);
                int ww = all_widgets[i].get_data<int> ("board-w");
                int wh = all_widgets[i].get_data<int> ("board-h");
                int wx_c = wx + ww / 2;
                int wy_c = wy + wh / 2;

                int ddx = wx_c - cx;
                int ddy = wy_c - cy;

                // Check direction
                if (dx > 0 && ddx <= 0) continue;
                if (dx < 0 && ddx >= 0) continue;
                if (dy > 0 && ddy <= 0) continue;
                if (dy < 0 && ddy >= 0) continue;

                // Distance with bias toward primary axis
                int dist;
                if (dx != 0) {
                    dist = ddx.abs () + ddy.abs () * 3;
                } else {
                    dist = ddy.abs () + ddx.abs () * 3;
                }

                if (dist < best_dist) {
                    best_dist = dist;
                    best = (int) i;
                }
            }

            if (best >= 0) {
                set_tile_focus (best);
                return true;
            }
            return false;
        }

        private void focus_folder_first () {
            // Find first folder-item tile in all_widgets
            for (uint i = 0; i < all_widgets.length; i++) {
                if (all_widgets[i].get_data<bool> ("board-folder-item")) {
                    set_tile_focus ((int) i);
                    return;
                }
            }
        }

        private bool activate_focused () {
            int idx = get_focused_index ();
            if (idx < 0) return false;

            var widget = all_widgets[idx];
            if (widget is Tile) {
                ((Tile) widget).tile_activated (((Tile) widget).app_entry);
                return true;
            } else if (widget is FolderTile) {
                ((FolderTile) widget).folder_clicked ((FolderTile) widget);
                return true;
            }
            return false;
        }

        private void compute_layout_for_width (int width) {
            int usable = width - MARGIN * 2;
            if (usable < 200) usable = 200;

            int max_col = app.config.max_columns;
            if (max_col <= 0) max_col = 18; // auto

            int new_cols = usable / (70 + SPACING);
            if (new_cols > max_col) new_cols = max_col;
            if (new_cols < 4) new_cols = 4;
            if (new_cols % 2 != 0) new_cols--;

            int new_cell = (usable - (new_cols - 1) * SPACING) / new_cols;

            if (new_cols != columns || new_cell != cell_size) {
                columns = new_cols;
                cell_size = new_cell;
                rebuild ();
            }
        }

        private void compute_layout () {
            int screen_w = 1920;
            var display = Gdk.Display.get_default ();
            if (display != null) {
                var monitors = display.get_monitors ();
                if (monitors.get_n_items () > 0) {
                    var monitor = (Gdk.Monitor) monitors.get_item (0);
                    screen_w = monitor.geometry.width;
                }
            }
            compute_layout_for_width (screen_w);
        }

        public void rebuild () {
            // Remove all children
            for (uint i = 0; i < all_widgets.length; i++) {
                all_widgets[i].unparent ();
            }
            all_widgets = new GenericArray<Gtk.Widget> ();
            if (folder_widget != null) {
                folder_widget.unparent ();
                folder_widget = null;
            }

            // Compute placements
            var max_rows = (int) tile_configs.length + 4;
            bool[,] occupied = new bool[max_rows, columns];
            var placements = new GenericArray<CellPlacement> ();

            for (uint i = 0; i < tile_configs.length; i++) {
                var tc = tile_configs[i];
                int cs, rs;
                if (tc.size == TileSize.FOLDER) {
                    cs = 1; rs = 1;
                } else {
                    get_spans (tc.size, out cs, out rs);
                }
                if (cs > columns) cs = columns;

                int col, row;
                find_free (occupied, max_rows, cs, rs, out col, out row);

                // Update folder row if this is the open folder
                if (open_folder_id != null && tc.size == TileSize.FOLDER &&
                    tc.folder_name == open_folder_id) {
                    folder_insert_after_row = row;
                }

                for (int r = row; r < row + rs; r++)
                    for (int c = col; c < col + cs; c++)
                        if (r < max_rows && c < columns)
                            occupied[r, c] = true;

                placements.add (new CellPlacement (col, row, cs, rs, (int) i));
            }

            // Find total rows
            int total_rows = 0;
            for (uint i = 0; i < placements.length; i++) {
                int bot = placements[i].row + placements[i].row_span;
                if (bot > total_rows) total_rows = bot;
            }

            // Determine folder content height
            target_folder_height = 0;
            if (open_folder_id != null && folder_insert_after_row >= 0) {
                int folder_item_count = 0;
                for (uint i = 0; i < tile_configs.length; i++) {
                    if (tile_configs[i].size == TileSize.FOLDER &&
                        tile_configs[i].folder_name == open_folder_id &&
                        tile_configs[i].folder_items != null) {
                        for (uint j = 0; j < tile_configs[i].folder_items.length; j++) {
                            if (app.app_provider.find_by_desktop_id (tile_configs[i].folder_items[j]) != null) {
                                folder_item_count++;
                            }
                        }
                        break;
                    }
                }
                folder_item_count_cached = folder_item_count;
                int folder_rows = (folder_item_count + columns - 1) / columns;
                int header_h = 32 + SPACING;
                target_folder_height = folder_rows * (cell_size + SPACING) + header_h;
            }

            // Create widgets and position them
            for (uint i = 0; i < placements.length; i++) {
                var p = placements[i];
                var tc = tile_configs[p.config_index];

                int x = MARGIN + p.col * (cell_size + SPACING);
                int y = p.row * (cell_size + SPACING);
                bool below = open_folder_id != null &&
                    p.row > folder_insert_after_row;
                // Large tiles starting at folder row but spanning past it also need to move
                if (!below && open_folder_id != null &&
                    p.row <= folder_insert_after_row &&
                    (p.row + p.row_span) > (folder_insert_after_row + 1)) {
                    below = true;
                }

                int w = p.col_span * cell_size + (p.col_span - 1) * SPACING;
                int h = p.row_span * cell_size + (p.row_span - 1) * SPACING;

                Gtk.Widget widget;

                if (tc.size == TileSize.FOLDER && tc.folder_items != null) {
                    var ftile = new FolderTile (app, tc.folder_name ?? "Folder", tc.folder_items, cell_size);
                    ftile.folder_clicked.connect ((f) => {
                        toggle_folder (f, p.row);
                    });
                    ftile.drop_received_on_folder.connect ((src_id, tgt_id) => {
                        handle_drop (src_id, tgt_id);
                    });
                    ftile.ungroup_requested.connect ((f) => {
                        ungroup_folder (f.folder_name);
                    });
                    ftile.rename_requested.connect ((f, new_name) => {
                        rename_folder (f.folder_name, new_name);
                    });
                    widget = ftile;
                } else {
                    var entry = app.app_provider.find_by_desktop_id (tc.desktop_id);
                    if (entry == null) continue;

                    var tile = new Tile (entry, tc.size, cell_size);
                    tile.tile_activated.connect ((e) => {
                        tile_activated (e);
                    });
                    tile.size_change_requested.connect ((t, new_size) => {
                        change_tile_size (t.app_entry.desktop_id, new_size);
                    });
                    tile.remove_requested.connect ((t) => {
                        remove_tile_by_id (t.app_entry.desktop_id);
                    });
                    tile.pin_to_dock_requested.connect ((t) => {
                        pin_requested (t.app_entry.desktop_id);
                    });
                    tile.unpin_from_dock_requested.connect ((t) => {
                        unpin_requested (t.app_entry.desktop_id);
                    });
                    tile.drop_received.connect ((src_id, tgt_id) => {
                        handle_drop (src_id, tgt_id);
                    });
                    tile.create_folder_requested.connect ((t) => {
                        create_folder_from_tile (t.app_entry.desktop_id, t.app_entry.name);
                    });
                    widget = tile;
                }

                widget.set_parent (this);
                widget.set_data<int> ("board-x", x);
                widget.set_data<int> ("board-y", y);
                widget.set_data<int> ("board-w", w);
                widget.set_data<int> ("board-h", h);
                widget.set_data<bool> ("board-below", below);
                all_widgets.add (widget);
            }

            // Create folder content widget if open
            if (open_folder_id != null && folder_insert_after_row >= 0) {
                build_folder_content ();
            }

            queue_resize ();
        }

        private void build_folder_content () {
            TileConfig? fc = null;
            for (uint i = 0; i < tile_configs.length; i++) {
                if (tile_configs[i].size == TileSize.FOLDER &&
                    tile_configs[i].folder_name == open_folder_id) {
                    fc = tile_configs[i];
                    break;
                }
            }
            if (fc == null || fc.folder_items == null) return;

            int base_y = (folder_insert_after_row + 1) * (cell_size + SPACING);
            int header_h = 32;

            // Header label
            var header = new Gtk.Label (fc.folder_name);
            header.add_css_class ("folder-header-label");
            header.halign = Gtk.Align.START;
            header.set_parent (this);
            header.set_data<int> ("board-x", MARGIN + 8);
            header.set_data<int> ("board-y", base_y);
            header.set_data<int> ("board-w", columns * (cell_size + SPACING) - SPACING);
            header.set_data<int> ("board-h", header_h);
            header.set_data<bool> ("board-below", false);
            // Use folder_widget to hold the header for cleanup
            folder_widget = header;

            int content_y = base_y + header_h + SPACING;

            var fname = fc.folder_name;
            int placed = 0;
            for (uint i = 0; i < fc.folder_items.length; i++) {
                var item_id = fc.folder_items[i];
                var entry = app.app_provider.find_by_desktop_id (item_id);
                if (entry == null) continue;

                var tile = new Tile (entry, TileSize.SMALL, cell_size);
                tile.tile_activated.connect ((e) => {
                    tile_activated (e);
                });
                tile.remove_requested.connect ((t) => {
                    remove_from_folder (fname, t.app_entry.desktop_id);
                });
                tile.pin_to_dock_requested.connect ((t) => {
                    pin_requested (t.app_entry.desktop_id);
                });
                tile.unpin_from_dock_requested.connect ((t) => {
                    unpin_requested (t.app_entry.desktop_id);
                });
                tile.drop_received.connect ((src_id, tgt_id) => {
                    reorder_in_folder (fname, src_id, tgt_id);
                });

                int col = placed % columns;
                int row = placed / columns;
                int x = MARGIN + col * (cell_size + SPACING);
                int y = content_y + row * (cell_size + SPACING);

                tile.set_parent (this);
                tile.set_data<int> ("board-x", x);
                tile.set_data<int> ("board-y", y);
                tile.set_data<int> ("board-w", cell_size);
                tile.set_data<int> ("board-h", cell_size);
                tile.set_data<bool> ("board-below", false);
                tile.set_data<bool> ("board-folder-item", true);
                tile.set_data<int> ("board-folder-index", placed);
                all_widgets.add (tile);

                placed++;
            }
        }

        protected override void size_allocate (int width, int height, int baseline) {
            // Recompute layout if width changed
            compute_layout_for_width (width);

            // Compute uniform offset — max needed across all below tiles
            int uniform_offset = target_folder_height;
            for (uint i = 0; i < all_widgets.length; i++) {
                if (!all_widgets[i].get_data<bool> ("board-below")) continue;
                int bx = all_widgets[i].get_data<int> ("board-x");
                int bw = all_widgets[i].get_data<int> ("board-w");
                int by = all_widgets[i].get_data<int> ("board-y");
                int needed = compute_tile_offset (bx, bw, by);
                if (needed > uniform_offset) uniform_offset = needed;
            }
            int animated_offset = (int) (uniform_offset * anim_progress);

            for (uint i = 0; i < all_widgets.length; i++) {
                var w = all_widgets[i];
                int bx = w.get_data<int> ("board-x");
                int by = w.get_data<int> ("board-y");
                int bw = w.get_data<int> ("board-w");
                int bh = w.get_data<int> ("board-h");
                bool below = w.get_data<bool> ("board-below");

                int final_y = by;
                if (below) {
                    final_y += animated_offset;
                }

                bool is_folder_item = w.get_data<bool> ("board-folder-item");
                if (is_folder_item) {
                    int idx = w.get_data<int> ("board-folder-index");
                    int total = folder_item_count_cached > 1 ? folder_item_count_cached - 1 : 1;
                    double tile_start = 0.6 * idx / total;
                    double tile_progress = (cascade_progress - tile_start) / 0.4;
                    if (tile_progress < 0) tile_progress = 0;
                    if (tile_progress > 1) tile_progress = 1;
                    w.set_opacity (tile_progress);
                }

                int mw, mh, nw, nh;
                w.measure (Gtk.Orientation.HORIZONTAL, -1, out mw, out nw, null, null);
                w.measure (Gtk.Orientation.VERTICAL, -1, out mh, out nh, null, null);

                var transform = new Gsk.Transform ();
                transform = transform.translate (Graphene.Point () { x = bx, y = final_y });
                w.allocate (bw, bh, -1, transform);
            }
            if (folder_widget != null) {
                int bx = folder_widget.get_data<int> ("board-x");
                int by = folder_widget.get_data<int> ("board-y");
                int bw = folder_widget.get_data<int> ("board-w");
                int bh = folder_widget.get_data<int> ("board-h");

                int mw2, nw2, mh2, nh2;
                folder_widget.measure (Gtk.Orientation.HORIZONTAL, -1, out mw2, out nw2, null, null);
                folder_widget.measure (Gtk.Orientation.VERTICAL, bw, out mh2, out nh2, null, null);

                folder_widget.set_opacity (cascade_progress);

                var transform = new Gsk.Transform ();
                transform = transform.translate (Graphene.Point () { x = bx, y = by });
                folder_widget.allocate (bw, int.max (bh, mh2), -1, transform);
            }
        }

        protected override Gtk.SizeRequestMode get_request_mode () {
            return Gtk.SizeRequestMode.HEIGHT_FOR_WIDTH;
        }

        protected override void measure (Gtk.Orientation orientation, int for_size,
                                          out int minimum, out int natural,
                                          out int minimum_baseline, out int natural_baseline) {
            minimum_baseline = -1;
            natural_baseline = -1;

            if (orientation == Gtk.Orientation.HORIZONTAL) {
                minimum = 200;
                natural = columns * (cell_size + SPACING) + MARGIN * 2;
            } else {
                int uo = target_folder_height;
                for (uint j = 0; j < all_widgets.length; j++) {
                    if (!all_widgets[j].get_data<bool> ("board-below")) continue;
                    int needed = compute_tile_offset (
                        all_widgets[j].get_data<int> ("board-x"),
                        all_widgets[j].get_data<int> ("board-w"),
                        all_widgets[j].get_data<int> ("board-y"));
                    if (needed > uo) uo = needed;
                }
                int ao = (int) (uo * anim_progress);
                int max_row = 0;
                for (uint i = 0; i < all_widgets.length; i++) {
                    int y = all_widgets[i].get_data<int> ("board-y");
                    int h = all_widgets[i].get_data<int> ("board-h");
                    bool below = all_widgets[i].get_data<bool> ("board-below");
                    int final_y = y + (below ? ao : 0);
                    int bot = final_y + h;
                    if (bot > max_row) max_row = bot;
                }
                if (folder_widget != null) {
                    int y = folder_widget.get_data<int> ("board-y");
                    int h = folder_widget.get_data<int> ("board-h");
                    int bot = y + h;
                    if (bot > max_row) max_row = bot;
                }
                minimum = max_row;
                natural = max_row;
            }
        }

        // --- Folder logic ---

        private void toggle_folder (FolderTile folder, int folder_row) {
            if (cascade_anim != null) {
                cascade_anim.pause ();
                cascade_anim = null;
            }
            if (folder_anim != null) {
                folder_anim.pause ();
                folder_anim = null;
            }

            if (open_folder_id == folder.folder_name) {
                // Close same folder: cascade out → slide up
                var ct = new Adw.CallbackAnimationTarget ((v) => {
                    cascade_progress = v;
                    queue_allocate ();
                });
                cascade_anim = new Adw.TimedAnimation (this, cascade_progress, 0.0, 200, ct);
                cascade_anim.done.connect (() => {
                    Idle.add (() => {
                        var target = new Adw.CallbackAnimationTarget ((val) => {
                            anim_progress = val;
                            queue_resize ();
                            queue_allocate ();
                        });
                        folder_anim = new Adw.TimedAnimation (this, anim_progress, 0.0, 200, target);
                        folder_anim.done.connect (() => {
                            Idle.add (() => {
                                open_folder_id = null;
                                folder_insert_after_row = -1;
                                target_folder_height = 0;
                                anim_progress = 1.0;
                                cascade_progress = 1.0;
                                rebuild ();
                                return Source.REMOVE;
                            });
                        });
                        folder_anim.play ();
                        return Source.REMOVE;
                    });
                });
                cascade_anim.play ();
            } else if (open_folder_id != null) {
                // Switch folder: cascade out → slide up → slide down new → cascade in
                var new_name = folder.folder_name;
                var new_row = folder_row;
                start_close_cascade (() => {
                    start_close_slide (() => {
                        switch_to_folder (new_name, new_row);
                    });
                });
            } else {
                // Open folder (nothing open) — lightweight, no full rebuild
                open_folder_id = folder.folder_name;
                folder_insert_after_row = folder_row;
                anim_progress = 0.0;

                // Compute folder height
                int folder_item_count = 0;
                for (uint i = 0; i < tile_configs.length; i++) {
                    if (tile_configs[i].size == TileSize.FOLDER &&
                        tile_configs[i].folder_name == open_folder_id &&
                        tile_configs[i].folder_items != null) {
                        for (uint j = 0; j < tile_configs[i].folder_items.length; j++) {
                            if (app.app_provider.find_by_desktop_id (tile_configs[i].folder_items[j]) != null) {
                                folder_item_count++;
                            }
                        }
                        break;
                    }
                }
                folder_item_count_cached = folder_item_count;
                int folder_rows = (folder_item_count + columns - 1) / columns;
                int header_h = 32 + SPACING;
                target_folder_height = folder_rows * (cell_size + SPACING) + header_h;

                // Update below flags on existing widgets
                for (uint i = 0; i < all_widgets.length; i++) {
                    var w = all_widgets[i];
                    int wy = w.get_data<int> ("board-y");
                    int wh = w.get_data<int> ("board-h");
                    // Last row this tile occupies
                    int last_row = (wy + wh - 1) / (cell_size + SPACING);
                    w.set_data<bool> ("board-below", last_row > folder_insert_after_row);
                }

                cascade_progress = 0.0;

                // Phase 1: slide down
                var target = new Adw.CallbackAnimationTarget ((val) => {
                    anim_progress = val;
                    queue_resize ();
                    queue_allocate ();
                });
                folder_anim = new Adw.TimedAnimation (this, 0.0, 1.0, 200, target);
                folder_anim.done.connect (() => {
                    // Phase 2: cascade appearance
                    Idle.add (() => {
                        var ct = new Adw.CallbackAnimationTarget ((v) => {
                            cascade_progress = v;
                            queue_allocate ();
                        });
                        cascade_anim = new Adw.TimedAnimation (this, 0.0, 1.0, 350, ct);
                        cascade_anim.play ();
                        return Source.REMOVE;
                    });
                });
                folder_anim.play ();

                // Build content in background during slide
                Idle.add (() => {
                    build_folder_content ();
                    focus_folder_first ();
                    return Source.REMOVE;
                });
            }
        }

        private delegate void AnimDone ();

        private void start_close_cascade (owned AnimDone then) {
            var ct = new Adw.CallbackAnimationTarget ((v) => {
                cascade_progress = v;
                queue_allocate ();
            });
            cascade_anim = new Adw.TimedAnimation (this, cascade_progress, 0.0, 200, ct);
            cascade_anim.done.connect (() => {
                Idle.add (() => { then (); return Source.REMOVE; });
            });
            cascade_anim.play ();
        }

        private void start_close_slide (owned AnimDone then) {
            var st = new Adw.CallbackAnimationTarget ((v) => {
                anim_progress = v;
                queue_resize ();
                queue_allocate ();
            });
            folder_anim = new Adw.TimedAnimation (this, anim_progress, 0.0, 200, st);
            folder_anim.done.connect (() => {
                Idle.add (() => { then (); return Source.REMOVE; });
            });
            folder_anim.play ();
        }

        private void start_open_slide (owned AnimDone then) {
            var st = new Adw.CallbackAnimationTarget ((v) => {
                anim_progress = v;
                queue_resize ();
                queue_allocate ();
            });
            folder_anim = new Adw.TimedAnimation (this, 0.0, 1.0, 200, st);
            folder_anim.done.connect (() => {
                Idle.add (() => { then (); return Source.REMOVE; });
            });
            folder_anim.play ();
        }

        private void start_open_cascade () {
            var ct = new Adw.CallbackAnimationTarget ((v) => {
                cascade_progress = v;
                queue_allocate ();
            });
            cascade_anim = new Adw.TimedAnimation (this, 0.0, 1.0, 350, ct);
            cascade_anim.play ();
        }

        private void setup_folder_state (string name, int row) {
            // Clean up old folder content
            if (folder_widget != null) {
                folder_widget.unparent ();
                folder_widget = null;
            }
            for (int k = (int) all_widgets.length - 1; k >= 0; k--) {
                if (all_widgets[k].get_data<bool> ("board-folder-item")) {
                    all_widgets[k].unparent ();
                    all_widgets.remove_index (k);
                }
            }

            open_folder_id = name;
            folder_insert_after_row = row;
            anim_progress = 0.0;
            cascade_progress = 0.0;

            // Compute folder height
            int fic = 0;
            for (uint i = 0; i < tile_configs.length; i++) {
                if (tile_configs[i].size == TileSize.FOLDER &&
                    tile_configs[i].folder_name == name &&
                    tile_configs[i].folder_items != null) {
                    for (uint j = 0; j < tile_configs[i].folder_items.length; j++) {
                        if (app.app_provider.find_by_desktop_id (tile_configs[i].folder_items[j]) != null)
                            fic++;
                    }
                    break;
                }
            }
            folder_item_count_cached = fic;
            int fr = (fic + columns - 1) / columns;
            int hh = 32 + SPACING;
            target_folder_height = fr * (cell_size + SPACING) + hh;

            // Update below flags
            for (uint i = 0; i < all_widgets.length; i++) {
                var w = all_widgets[i];
                int wy = w.get_data<int> ("board-y");
                int wh = w.get_data<int> ("board-h");
                int lr = (wy + wh - 1) / (cell_size + SPACING);
                w.set_data<bool> ("board-below", lr > row);
            }
        }

        private void switch_to_folder (string name, int row) {
            setup_folder_state (name, row);

            start_open_slide (() => {
                start_open_cascade ();
            });

            Idle.add (() => {
                build_folder_content ();
                focus_folder_first ();
                return Source.REMOVE;
            });
        }

        // --- Drop handling ---

        private void handle_drop (string source_id, string target_id) {
            if (target_id.has_prefix ("folder:") && !source_id.has_prefix ("folder:")) {
                var folder_name = target_id.substring ("folder:".length);
                add_to_folder (folder_name, source_id);
                return;
            }

            int idx_a = find_config_index (source_id);
            int idx_b = find_config_index (target_id);

            if (idx_a >= 0 && idx_b >= 0 && idx_a != idx_b) {
                var tmp = tile_configs[idx_a];
                tile_configs[idx_a] = tile_configs[idx_b];
                tile_configs[idx_b] = tmp;
                rebuild ();
                layout_changed ();
            }
        }

        private int find_config_index (string id) {
            for (uint i = 0; i < tile_configs.length; i++) {
                if (id.has_prefix ("folder:")) {
                    if (tile_configs[i].folder_name == id.substring ("folder:".length))
                        return (int) i;
                } else {
                    if (tile_configs[i].desktop_id == id && tile_configs[i].size != TileSize.FOLDER)
                        return (int) i;
                }
            }
            return -1;
        }

        private void add_to_folder (string folder_name, string desktop_id) {
            for (uint i = 0; i < tile_configs.length; i++) {
                var tc = tile_configs[i];
                if (tc.size == TileSize.FOLDER && tc.folder_name == folder_name && tc.folder_items != null) {
                    for (uint j = 0; j < tc.folder_items.length; j++) {
                        if (tc.folder_items[j] == desktop_id) return;
                    }
                    tc.folder_items.add (desktop_id);
                    break;
                }
            }
            for (uint i = 0; i < tile_configs.length; i++) {
                if (tile_configs[i].desktop_id == desktop_id && tile_configs[i].size != TileSize.FOLDER) {
                    tile_configs.remove_index (i);
                    break;
                }
            }
            rebuild ();
            layout_changed ();
        }

        private void create_folder_from_tile (string desktop_id, string app_name) {
            // Remove the tile
            int idx = -1;
            for (uint i = 0; i < tile_configs.length; i++) {
                if (tile_configs[i].desktop_id == desktop_id && tile_configs[i].size != TileSize.FOLDER) {
                    idx = (int) i;
                    break;
                }
            }
            if (idx < 0) return;

            tile_configs.remove_index (idx);

            // Create folder with this one app
            var items = new GenericArray<string> ();
            items.add (desktop_id);
            var folder = new TileConfig.folder (app_name, items);

            // Insert at same position
            tile_configs.insert (idx, folder);

            rebuild ();
            layout_changed ();
        }

        private void rename_folder (string old_name, string new_name) {
            for (uint i = 0; i < tile_configs.length; i++) {
                if (tile_configs[i].size == TileSize.FOLDER &&
                    tile_configs[i].folder_name == old_name) {
                    tile_configs[i].folder_name = new_name;
                    tile_configs[i].desktop_id = "folder:" + new_name;
                    break;
                }
            }
            if (open_folder_id == old_name) {
                open_folder_id = new_name;
            }
            rebuild ();
            layout_changed ();
        }

        private void ungroup_folder (string folder_name) {
            // Find folder, extract all items as standalone tiles, remove folder
            int folder_idx = -1;
            GenericArray<string>? items = null;

            for (uint i = 0; i < tile_configs.length; i++) {
                if (tile_configs[i].size == TileSize.FOLDER &&
                    tile_configs[i].folder_name == folder_name) {
                    folder_idx = (int) i;
                    items = tile_configs[i].folder_items;
                    break;
                }
            }

            if (folder_idx < 0) return;

            // Close folder if open
            if (open_folder_id == folder_name) {
                open_folder_id = null;
                folder_insert_after_row = -1;
            }

            // Remove folder tile
            tile_configs.remove_index (folder_idx);

            // Add all items as individual tiles at that position
            if (items != null) {
                for (int i = (int) items.length - 1; i >= 0; i--) {
                    tile_configs.insert (folder_idx, new TileConfig (items[i], TileSize.SMALL));
                }
            }

            rebuild ();
            layout_changed ();
        }

        public void remove_from_folder (string folder_name, string desktop_id) {
            for (uint i = 0; i < tile_configs.length; i++) {
                var tc = tile_configs[i];
                if (tc.size == TileSize.FOLDER && tc.folder_name == folder_name && tc.folder_items != null) {
                    for (uint j = 0; j < tc.folder_items.length; j++) {
                        if (tc.folder_items[j] == desktop_id) {
                            tc.folder_items.remove_index (j);
                            break;
                        }
                    }
                    if (tc.folder_items.length == 0) {
                        tile_configs.remove_index (i);
                    }
                    break;
                }
            }
            tile_configs.add (new TileConfig (desktop_id, TileSize.SMALL));

            // Keep folder open if it still has items
            bool folder_gone = true;
            for (uint i = 0; i < tile_configs.length; i++) {
                if (tile_configs[i].size == TileSize.FOLDER &&
                    tile_configs[i].folder_name == folder_name &&
                    tile_configs[i].folder_items != null &&
                    tile_configs[i].folder_items.length > 0) {
                    folder_gone = false;
                    break;
                }
            }
            if (folder_gone) {
                open_folder_id = null;
                folder_insert_after_row = -1;
            }
            rebuild ();
            layout_changed ();
        }

        private void reorder_in_folder (string folder_name, string id_a, string id_b) {
            for (uint i = 0; i < tile_configs.length; i++) {
                var tc = tile_configs[i];
                if (tc.size == TileSize.FOLDER && tc.folder_name == folder_name && tc.folder_items != null) {
                    int idx_a = -1, idx_b = -1;
                    for (uint j = 0; j < tc.folder_items.length; j++) {
                        if (tc.folder_items[j] == id_a) idx_a = (int) j;
                        if (tc.folder_items[j] == id_b) idx_b = (int) j;
                    }
                    if (idx_a >= 0 && idx_b >= 0 && idx_a != idx_b) {
                        var tmp = tc.folder_items[idx_a];
                        tc.folder_items[idx_a] = tc.folder_items[idx_b];
                        tc.folder_items[idx_b] = tmp;
                        rebuild ();
                        layout_changed ();
                    }
                    break;
                }
            }
        }

        private void change_tile_size (string desktop_id, TileSize new_size) {
            for (uint i = 0; i < tile_configs.length; i++) {
                if (tile_configs[i].desktop_id == desktop_id) {
                    tile_configs[i] = new TileConfig (desktop_id, new_size);
                    break;
                }
            }
            rebuild ();
            layout_changed ();
        }

        private void remove_tile_by_id (string desktop_id) {
            for (uint i = 0; i < tile_configs.length; i++) {
                if (tile_configs[i].desktop_id == desktop_id) {
                    tile_configs.remove_index (i);
                    break;
                }
            }
            rebuild ();
            layout_changed ();
        }

        // --- Helpers ---

        private void get_spans (TileSize size, out int cs, out int rs) {
            switch (size) {
                case TileSize.SMALL: cs = 1; rs = 1; break;
                case TileSize.MEDIUM: cs = 2; rs = 1; break;
                case TileSize.LARGE: cs = 2; rs = 2; break;
                default: cs = 1; rs = 1; break;
            }
        }

        private void find_free (bool[,] occ, int max_r, int cs, int rs, out int oc, out int or) {
            for (int r = 0; r < max_r; r++) {
                for (int c = 0; c <= columns - cs; c++) {
                    bool ok = true;
                    for (int dr = 0; dr < rs && ok; dr++)
                        for (int dc = 0; dc < cs && ok; dc++)
                            if (r + dr >= max_r || occ[r + dr, c + dc]) ok = false;
                    if (ok) { oc = c; or = r; return; }
                }
            }
            oc = 0; or = max_r;
        }

        public GroupConfig to_config (string group_name) {
            var config = new GroupConfig (group_name);
            for (uint i = 0; i < tile_configs.length; i++) {
                var tc = new TileConfig (tile_configs[i].desktop_id, tile_configs[i].size);
                tc.folder_name = tile_configs[i].folder_name;
                tc.folder_items = tile_configs[i].folder_items;
                config.tiles.add (tc);
            }
            return config;
        }

        public void try_extract_from_folder (string desktop_id) {
            if (open_folder_id != null) {
                remove_from_folder (open_folder_id, desktop_id);
            }
        }

        protected override void dispose () {
            for (uint i = 0; i < all_widgets.length; i++) {
                all_widgets[i].unparent ();
            }
            all_widgets = new GenericArray<Gtk.Widget> ();
            if (folder_widget != null) {
                folder_widget.unparent ();
                folder_widget = null;
            }
            base.dispose ();
        }
    }
}
