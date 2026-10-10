namespace XimperShellLauncher {

    public class TileBoard : Gtk.Widget {

        private weak Application app;
        private TileModel model;
        private GridPacker packer;
        private FolderAnimator animator;
        private TileDragController drag_controller;
        private bool rebuild_after_drag = false;
        private int viewport_height = 160;
        public bool horizontal { get { return app.config.group_layout == GroupLayout.HORIZONTAL; } }
        public TileModel drag_model { get { return model; } }
        private void update_viewport_height (int height) {
            viewport_height = int.max (8, height);
            if (!drag_in_progress &&
                (group_grid == null || !group_grid.other_board_dragging (this)) &&
                packer.compute_for_height (viewport_height, app.config.cell_size)) rebuild ();
        }
        public int folder_panel_x (GenericArray<TileConfig>? configs = null) {
            int edge = packer.margin;
            var cells = packer.pack (configs ?? model.tiles);
            for (uint i = 0; i < cells.length; i++)
                edge = int.max (edge, packer.margin + (cells[i].col + cells[i].col_span) * (packer.cell_size + GridPacker.SPACING));
            return edge + GridPacker.SPACING;
        }
        public void folder_item_position (int index, out int x, out int y, GenericArray<TileConfig>? configs = null) {
            int stride = packer.cell_size + GridPacker.SPACING;
            x = horizontal ? folder_panel_x (configs) + index / packer.folder_rows * stride : packer.margin + index % packer.columns * stride;
            y = horizontal ? GridPacker.FOLDER_HEADER_H + GridPacker.SPACING + index % packer.folder_rows * stride :
                (folder_row + 1) * stride + GridPacker.FOLDER_HEADER_H + GridPacker.SPACING + index / packer.columns * stride;
        }
        public void commit_source_transfer () {
            drag_controller.commit_source_transfer ();
        }
        public void apply_drag_candidate (GenericArray<TileConfig> candidate) {
            model.commit_candidate (candidate);
            rebuild_after_drag = true;
        }

        private GenericArray<TilePlacement> placements;
        private Gtk.Widget? folder_header;
        private Gtk.Widget? folder_drop_zone;

        // Folder state
        private string? open_folder_id;
        private int folder_row = -1;
        private int target_folder_height;
        private int folder_item_count;

        public bool drag_in_progress { get { return drag_controller != null && drag_controller.busy; } }
        public weak TileGrid? group_grid;
        public signal void extend_menu (Gtk.Box menu, Gtk.Popover popover, string id);
        public signal void drag_finished ();
        public signal void layout_changed ();
        public signal void tile_activated (AppEntry entry);
        public signal void pin_requested (string desktop_id);
        public signal void unpin_requested (string desktop_id);

        public TileBoard (Application app, GenericArray<TileConfig> configs) {
            this.app = app;
            this.model = new TileModel (configs);
            this.packer = new GridPacker ();
            this.animator = new FolderAnimator (this);
            this.placements = new GenericArray<TilePlacement> ();

            set_layout_manager (null);
            hexpand = true;
            vexpand = true;
            focusable = true;

            model.purge_missing (app.app_provider);

            setup_keyboard ();
            drag_controller = new TileDragController (this, app, model, packer);
            compute_initial_layout ();
            rebuild ();
        }


        private void cleanup_widget (Gtk.Widget widget) {
            var tile = widget as Tile;
            if (tile != null) tile.cleanup ();
            var folder = widget as FolderTile;
            if (folder != null) folder.cleanup ();
            widget.unparent ();
        }

        // --- Layout ---

        private void compute_initial_layout () {
            int screen_w = 1920;
            var display = Gdk.Display.get_default ();
            if (display != null) {
                var monitors = display.get_monitors ();
                if (monitors.get_n_items () > 0) {
                    var monitor = (Gdk.Monitor) monitors.get_item (0);
                    screen_w = monitor.geometry.width;
                }
            }
            if (horizontal) packer.compute_for_height (viewport_height, app.config.cell_size);
            else packer.compute_for_size (screen_w, app.config.cell_size, app.config.max_columns);
        }

        private int horizontal_group_width () {
            int edge = folder_panel_x () - GridPacker.SPACING;
            if (open_folder_id != null) {
                int count = model.count_folder_items (open_folder_id, app.app_provider);
                edge = folder_panel_x () + int.max (1, (count + packer.folder_rows - 1) / packer.folder_rows) * (packer.cell_size + GridPacker.SPACING);
            }
            return int.max (200, edge + packer.margin);
        }

        private void rebuild () {
            // A Gtk.DragSource must survive until drag_end, even after a drop.
            if ((drag_controller != null && drag_controller.busy) ||
                (group_grid != null && group_grid.other_board_dragging (this))) {
                rebuild_after_drag = true;
                return;
            }
            if (horizontal) packer.compute_for_height (viewport_height, app.config.cell_size);
            // Remove all children
            for (uint i = 0; i < placements.length; i++) {
                cleanup_widget (placements[i].widget);
            }
            placements = new GenericArray<TilePlacement> ();
            if (folder_header != null) {
                folder_header.unparent ();
                folder_header = null;
            }
            if (folder_drop_zone != null) {
                folder_drop_zone.unparent ();
                folder_drop_zone = null;
            }

            // Pack grid
            var cells = packer.pack (model.tiles);

            // Find folder row
            if (open_folder_id != null) {
                folder_row = -1;
                for (uint i = 0; i < cells.length; i++) {
                    var tc = model.tiles[cells[i].config_index];
                    if (tc.size == TileSize.FOLDER && tc.folder_name == open_folder_id) {
                        folder_row = cells[i].row;
                        break;
                    }
                }
            }

            // Compute folder height
            target_folder_height = 0;
            if (open_folder_id != null && folder_row >= 0) {
                folder_item_count = model.count_folder_items (open_folder_id, app.app_provider);
                target_folder_height = packer.compute_folder_height (folder_item_count);
            }

            // Create widgets
            for (uint i = 0; i < cells.length; i++) {
                var cell = cells[i];
                var tc = model.tiles[cell.config_index];

                int x = packer.margin + cell.col * (packer.cell_size + GridPacker.SPACING);
                int y = cell.row * (packer.cell_size + GridPacker.SPACING);
                int w = cell.col_span * packer.cell_size + (cell.col_span - 1) * GridPacker.SPACING;
                int h = cell.row_span * packer.cell_size + (cell.row_span - 1) * GridPacker.SPACING;

                bool below = is_below_folder (cell.row, cell.row + cell.row_span);

                Gtk.Widget? widget = create_grid_widget (tc, cell.row);
                if (widget == null) continue;

                widget.set_parent (this);
                var placement = new TilePlacement (widget, x, y, w, h);
                placement.below = below;
                placements.add (placement);
            }

            // Build folder content if open
            if (open_folder_id != null && folder_row >= 0) {
                build_folder_content ();
            }

            queue_resize ();
        }

        private bool is_below_folder (int row_start, int row_end) {
            if (horizontal || open_folder_id == null) return false;
            if (row_start > folder_row) return true;
            // Large tiles starting at folder row but spanning past it
            if (row_start <= folder_row && row_end > folder_row + 1) return true;
            return false;
        }

        private Gtk.Widget? create_grid_widget (TileConfig tc, int cell_row) {
            unowned TileBoard owner = this;
            if (tc.size == TileSize.FOLDER && tc.folder_items != null) {
                var ftile = new FolderTile (app, tc.folder_name ?? "Folder", tc.folder_items, packer.cell_size);
                ftile.board_managed_dnd = true;
                string menu_folder_id = ftile.folder_id;
                ftile.extend_menu.connect ((menu, popover) => {
                    if (owner != null) owner.extend_menu (menu, popover, menu_folder_id);
                });
                weak FolderTile weak_folder = ftile;
                ftile.drag_state_changed.connect ((active) => {
                    var source = weak_folder;
                    if (owner == null || source == null) return;
                    if (active) owner.begin_tile_drag (source, source.folder_id);
                    else owner.drag_controller.end_source ();
                });
                ftile.folder_clicked.connect ((f) => {
                    if (owner != null) owner.toggle_folder (f, cell_row);
                });
                ftile.drop_received_on_folder.connect ((src_id, tgt_id) => {
                    if (owner != null) owner.on_drop (src_id, tgt_id);
                });
                ftile.ungroup_requested.connect ((f) => {
                    if (owner != null) owner.on_ungroup (f.folder_name);
                });
                ftile.rename_requested.connect ((f, new_name) => {
                    if (owner != null) owner.on_rename (f.folder_name, new_name);
                });
                return ftile;
            }

            var entry = app.app_provider.find_by_desktop_id (tc.desktop_id);
            if (entry == null) return null;

            var tile = new Tile (entry, tc.size, packer.cell_size);
            tile.board_managed_dnd = true;
            string menu_app_id = tile.app_entry.desktop_id;
            tile.extend_menu.connect ((menu, popover) => {
                if (owner != null) owner.extend_menu (menu, popover, menu_app_id);
            });
            weak Tile weak_tile = tile;
            tile.drag_state_changed.connect ((active) => {
                var source = weak_tile;
                if (owner == null || source == null) return;
                if (active) owner.begin_tile_drag (source, source.app_entry.desktop_id);
                else owner.drag_controller.end_source ();
            });
            tile.tile_activated.connect ((e) => { if (owner != null) owner.tile_activated (e); });
            tile.size_change_requested.connect ((t, s) => {
                if (owner != null) owner.on_size_change (t.app_entry.desktop_id, s);
            });
            tile.remove_requested.connect ((t) => { if (owner != null) owner.on_remove (t.app_entry.desktop_id); });
            tile.pin_to_dock_requested.connect ((t) => { if (owner != null) owner.pin_requested (t.app_entry.desktop_id); });
            tile.unpin_from_dock_requested.connect ((t) => { if (owner != null) owner.unpin_requested (t.app_entry.desktop_id); });
            tile.drop_received.connect ((src_id, tgt_id) => { if (owner != null) owner.on_drop (src_id, tgt_id); });
            tile.create_folder_requested.connect ((t) => {
                if (owner != null) owner.on_create_folder (t.app_entry.desktop_id, t.app_entry.name);
            });
            return tile;
        }

        private void build_folder_content () {
            unowned TileBoard owner = this;
            var fc = model.find_folder (open_folder_id);
            if (fc == null || fc.folder_items == null) return;

            // Header label
            var header = new Gtk.Label (fc.folder_name);
            header.add_css_class ("folder-header-label");
            header.halign = Gtk.Align.START;
            header.set_parent (this);
            folder_header = header;

            // Drop zone background — accepts tiles dragged into the folder
            var zone = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            zone.add_css_class ("folder-drop-zone");
            // The board capture target owns folder insertion too. Nested drop
            // handlers must never destroy a source widget before drag_end.
            zone.set_parent (this);
            folder_drop_zone = zone;

            var fname = fc.folder_name;
            int placed = 0;

            for (uint i = 0; i < fc.folder_items.length; i++) {
                var item_id = fc.folder_items[i];
                var entry = app.app_provider.find_by_desktop_id (item_id);
                if (entry == null) continue;

                var tile = new Tile (entry, TileSize.SMALL, packer.cell_size);
                tile.board_managed_dnd = true;
                string menu_item_id = tile.app_entry.desktop_id;
                tile.extend_menu.connect ((menu, popover) => {
                    if (owner != null) owner.extend_menu (menu, popover, menu_item_id);
                });
                weak Tile weak_tile = tile;
                tile.drag_state_changed.connect ((active) => {
                    var source = weak_tile;
                    if (owner == null || source == null) return;
                    if (active) owner.begin_tile_drag (source, source.app_entry.desktop_id);
                    else owner.drag_controller.end_source ();
                });
                tile.tile_activated.connect ((e) => { if (owner != null) owner.tile_activated (e); });
                tile.remove_requested.connect ((t) => {
                    if (owner != null) owner.on_remove_from_folder (fname, t.app_entry.desktop_id);
                });
                tile.pin_to_dock_requested.connect ((t) => { if (owner != null) owner.pin_requested (t.app_entry.desktop_id); });
                tile.unpin_from_dock_requested.connect ((t) => { if (owner != null) owner.unpin_requested (t.app_entry.desktop_id); });
                tile.drop_received.connect ((src_id, tgt_id) => {
                    if (owner != null) owner.on_reorder_in_folder (fname, src_id, tgt_id);
                });

                int x, y;
                folder_item_position (placed, out x, out y);

                tile.set_parent (this);
                var placement = new TilePlacement (tile, x, y, packer.cell_size, packer.cell_size);
                placement.is_folder_item = true;
                placement.folder_index = placed;
                placements.add (placement);

                placed++;
            }
        }

        // --- Widget overrides ---

        protected override void size_allocate (int width, int height, int baseline) {
            // Unlike Gtk.Box (whose layout manager allocates its children), this
            // custom widget receives the actual content allocation here. Header,
            // search and container margins have already been accounted for.
            if (horizontal) update_viewport_height (height);
            if (!horizontal && !drag_controller.busy &&
                packer.compute_for_size (width, app.config.cell_size, app.config.max_columns)) {
                rebuild ();
            }

            int animated_offset = compute_animated_offset ();

            for (uint i = 0; i < placements.length; i++) {
                var p = placements[i];
                int final_y = p.y;
                if (p.below) {
                    final_y += animated_offset;
                }

                if (p.is_folder_item) {
                    p.widget.set_opacity (
                        animator.compute_item_opacity (p.folder_index, folder_item_count));
                }
                int final_x = p.x;
                int drag_x, drag_y;
                bool drag_hidden;
                if (drag_controller.get_position (p, out drag_x, out drag_y, out drag_hidden)) {
                    final_x = drag_x;
                    final_y = drag_y;
                    p.widget.opacity = drag_hidden ? 0 : 1;
                }

                int mw, nw, mh, nh;
                p.widget.measure (Gtk.Orientation.HORIZONTAL, -1, out mw, out nw, null, null);
                p.widget.measure (Gtk.Orientation.VERTICAL, -1, out mh, out nh, null, null);

                var transform = new Gsk.Transform ();
                transform = transform.translate (Graphene.Point () { x = final_x, y = final_y });
                p.widget.allocate (p.w, p.h, -1, transform);
            }

            drag_controller.allocate_gap ();
            int folder_render_y = horizontal ? 0 : (folder_row + 1) * (packer.cell_size + GridPacker.SPACING);
            int folder_render_height = animated_offset;
            int drag_folder_y, drag_folder_height;
            bool folder_visible = true;
            bool drag_folder_visible;
            if (drag_controller.get_folder_render (out drag_folder_y, out drag_folder_height, out drag_folder_visible)) {
                folder_render_y = drag_folder_y;
                folder_render_height = drag_folder_height;
                folder_visible = drag_folder_visible;
            }

            if (folder_header != null) {
                int hx = (horizontal ? drag_controller.folder_panel_left () : packer.margin) + 8;
                int hy = folder_render_y;
                int hw = horizontal ? int.max (packer.cell_size, width - hx - packer.margin) : packer.columns * (packer.cell_size + GridPacker.SPACING) - GridPacker.SPACING;

                int mw2, nw2, mh2, nh2;
                folder_header.measure (Gtk.Orientation.HORIZONTAL, -1, out mw2, out nw2, null, null);
                folder_header.measure (Gtk.Orientation.VERTICAL, hw, out mh2, out nh2, null, null);

                folder_header.set_opacity (folder_visible ? animator.cascade_progress : 0);

                var transform = new Gsk.Transform ();
                transform = transform.translate (Graphene.Point () { x = hx, y = hy });
                folder_header.allocate (hw, int.max (GridPacker.FOLDER_HEADER_H, mh2), -1, transform);
            }

            if (folder_drop_zone != null && folder_row >= 0) {
                int zone_x = horizontal ? drag_controller.folder_panel_left () : packer.margin;
                int zone_y = folder_render_y;
                int zone_w = horizontal ? int.max (packer.cell_size, width - zone_x - packer.margin) : packer.columns * (packer.cell_size + GridPacker.SPACING) - GridPacker.SPACING;
                int zone_h = horizontal ? viewport_height : folder_render_height;
                folder_drop_zone.opacity = folder_visible ? 1 : 0;

                int zmw, znw, zmh, znh;
                folder_drop_zone.measure (Gtk.Orientation.HORIZONTAL, -1, out zmw, out znw, null, null);
                folder_drop_zone.measure (Gtk.Orientation.VERTICAL, zone_w, out zmh, out znh, null, null);

                var zt = new Gsk.Transform ();
                zt = zt.translate (Graphene.Point () { x = zone_x, y = zone_y });
                folder_drop_zone.allocate (zone_w, zone_h, -1, zt);
            }
        }

        protected override Gtk.SizeRequestMode get_request_mode () {
            return horizontal ? Gtk.SizeRequestMode.CONSTANT_SIZE : Gtk.SizeRequestMode.HEIGHT_FOR_WIDTH;
        }

        protected override void measure (Gtk.Orientation orientation, int for_size,
                                          out int minimum, out int natural,
                                          out int minimum_baseline, out int natural_baseline) {
            minimum_baseline = -1;
            natural_baseline = -1;

            if (orientation == Gtk.Orientation.HORIZONTAL) {
                if (app.config.group_layout == GroupLayout.HORIZONTAL) {
                    minimum = natural = int.max (horizontal_group_width (), drag_controller.preview_right () + packer.margin);
                } else {
                    minimum = 200;
                    natural = packer.columns * (packer.cell_size + GridPacker.SPACING) - GridPacker.SPACING + packer.margin * 2;
                }
            } else {
                if (horizontal) { minimum = natural = 0; return; }
                int ao = compute_animated_offset ();
                int max_bot = 0;
                for (uint i = 0; i < placements.length; i++) {
                    var p = placements[i];
                    int final_y = p.y + (p.below ? ao : 0);
                    int bot = final_y + p.h;
                    if (bot > max_bot) max_bot = bot;
                }
                if (folder_header != null) {
                    int hy = (folder_row + 1) * (packer.cell_size + GridPacker.SPACING);
                    int bot = hy + GridPacker.FOLDER_HEADER_H;
                    if (bot > max_bot) max_bot = bot;
                }
                max_bot = int.max (max_bot, drag_controller.preview_bottom ());
                minimum = max_bot;
                natural = max_bot;
            }
        }

        // --- Offset computation ---

        private int compute_tile_offset (TilePlacement p) {
            if (open_folder_id == null || folder_row < 0) return target_folder_height;

            int folder_row_bottom = (folder_row + 1) * (packer.cell_size + GridPacker.SPACING);
            if (p.y >= folder_row_bottom) return target_folder_height;

            // For large tiles starting at folder row — check how many
            // folder content rows actually reach this tile's columns
            int tile_col_start = (p.x - packer.margin) / (packer.cell_size + GridPacker.SPACING);

            int total_folder_rows = (folder_item_count + packer.columns - 1) / packer.columns;
            int last_row_items = folder_item_count % packer.columns;
            if (last_row_items == 0 && folder_item_count > 0) last_row_items = packer.columns;

            int effective_rows = total_folder_rows;
            if (tile_col_start >= last_row_items) {
                effective_rows = total_folder_rows - 1;
                if (effective_rows < 0) effective_rows = 0;
            }

            int header_h = GridPacker.FOLDER_HEADER_H + GridPacker.SPACING;
            int content_y = folder_row_bottom + header_h;
            int fcb = content_y + effective_rows * (packer.cell_size + GridPacker.SPACING);
            return fcb - p.y;
        }

        private int compute_animated_offset () {
            if (horizontal) return 0;
            int uniform_offset = target_folder_height;
            for (uint i = 0; i < placements.length; i++) {
                if (!placements[i].below) continue;
                int needed = compute_tile_offset (placements[i]);
                if (needed > uniform_offset) uniform_offset = needed;
            }
            return (int) (uniform_offset * animator.slide_progress);
        }

        public unowned GenericArray<TilePlacement> get_drag_placements () { return placements; }

        public void get_drag_base_position (TilePlacement placement, out int x, out int y) {
            x = placement.x;
            y = placement.y + (placement.below ? compute_animated_offset () : 0);
        }

        public string? get_drag_folder_baseline (out int row, out int height) {
            row = folder_row;
            height = target_folder_height;
            return open_folder_id != null && row >= 0 ? open_folder_id : null;
        }

        public bool drag_cell_below_folder (int first_row, int last_row) {
            if (horizontal) return false;
            if (!drag_controller.has_folder_geometry) return is_below_folder (first_row, last_row);
            int row = drag_controller.preview_folder_row;
            return row >= 0 && (first_row > row || (first_row <= row && last_row > row + 1));
        }

        public int get_drag_folder_offset () {
            return drag_controller.has_folder_geometry ? drag_controller.preview_folder_height : compute_animated_offset ();
        }

        public string? get_drag_folder (out int top, out int bottom) {
            if (horizontal) {
                top = GridPacker.FOLDER_HEADER_H + GridPacker.SPACING;
                bottom = viewport_height;
                return open_folder_id;
            }
            int row = drag_controller.has_folder_geometry ? drag_controller.preview_folder_row : folder_row;
            int height = drag_controller.has_folder_geometry ? drag_controller.preview_folder_height : target_folder_height;
            top = (row + 1) * (packer.cell_size + GridPacker.SPACING)
                + GridPacker.FOLDER_HEADER_H + GridPacker.SPACING;
            bottom = (row + 1) * (packer.cell_size + GridPacker.SPACING) + height;
            return open_folder_id != null && row >= 0 ? open_folder_id : null;
        }

        private void begin_tile_drag (Gtk.Widget source, string id) {
            animator.reset ();
            if (group_grid != null) group_grid.begin_drag (this, id);
            drag_controller.begin_source (source, id);
            queue_allocate ();
        }

        public void drag_layout_committed () { layout_changed (); }

        public void drag_preview_finished (bool changed) {
            if (changed || rebuild_after_drag) {
                rebuild_after_drag = false;
                if (open_folder_id != null && model.find_folder (open_folder_id) == null)
                    close_folder_state ();
                rebuild ();
            }
            queue_resize ();
            queue_allocate ();
            if (group_grid != null) group_grid.end_drag (this);
            drag_finished ();
        }

        // --- Folder animation ---

        private void toggle_folder (FolderTile folder, int cell_row) {
            if (drag_in_progress) return;
            animator.cancel ();
            if (horizontal) {
                open_folder_id = open_folder_id == folder.folder_name ? null : folder.folder_name;
                animator.reset ();
                rebuild ();
                if (open_folder_id != null) focus_folder_first ();
                return;
            }

            if (open_folder_id == folder.folder_name) {
                // Close same folder: cascade out → slide up → rebuild
                animator.run_cascade (animator.cascade_progress, 0.0, () => {
                    animator.run_slide (animator.slide_progress, 0.0, () => {
                        close_folder_state ();
                        rebuild ();
                    });
                });
            } else if (open_folder_id != null) {
                // Switch folder: cascade out → slide up → setup new → slide down → cascade in
                var new_name = folder.folder_name;
                var new_row = cell_row;
                animator.run_cascade (animator.cascade_progress, 0.0, () => {
                    animator.run_slide (animator.slide_progress, 0.0, () => {
                        setup_folder_state (new_name, new_row);
                        animator.run_slide (0.0, 1.0, () => {
                            animator.run_cascade (0.0, 1.0, null);
                        });
                        var id2 = Idle.add (() => {
                            build_folder_content ();
                            focus_folder_first ();
                            return Source.REMOVE;
                        });
                        animator.track_idle (id2);
                    });
                });
            } else {
                // Open folder (nothing currently open)
                open_folder_id = folder.folder_name;
                folder_row = cell_row;
                folder_item_count = model.count_folder_items (open_folder_id, app.app_provider);
                target_folder_height = packer.compute_folder_height (folder_item_count);
                update_below_flags ();

                animator.cascade_progress = 0.0;
                animator.run_slide (0.0, 1.0, () => {
                    animator.run_cascade (0.0, 1.0, null);
                });

                var id = Idle.add (() => {
                    build_folder_content ();
                    focus_folder_first ();
                    return Source.REMOVE;
                });
                animator.track_idle (id);
            }
        }

        private void setup_folder_state (string name, int row) {
            cleanup_folder_content ();
            open_folder_id = name;
            folder_row = row;
            folder_item_count = model.count_folder_items (name, app.app_provider);
            target_folder_height = packer.compute_folder_height (folder_item_count);
            animator.slide_progress = 0.0;
            animator.cascade_progress = 0.0;
            update_below_flags ();
        }

        private void close_folder_state () {
            open_folder_id = null;
            folder_row = -1;
            target_folder_height = 0;
            animator.reset ();
        }

        private void cleanup_folder_content () {
            if (folder_header != null) {
                folder_header.unparent ();
                folder_header = null;
            }
            if (folder_drop_zone != null) {
                folder_drop_zone.unparent ();
                folder_drop_zone = null;
            }
            for (int k = (int) placements.length - 1; k >= 0; k--) {
                if (placements[k].is_folder_item) {
                    cleanup_widget (placements[k].widget);
                    placements.remove_index (k);
                }
            }
        }

        private void update_below_flags () {
            for (uint i = 0; i < placements.length; i++) {
                var p = placements[i];
                int last_row = (p.y + p.h - 1) / (packer.cell_size + GridPacker.SPACING);
                p.below = !horizontal && last_row > folder_row;
            }
        }

        // --- Keyboard navigation ---

        private void setup_keyboard () {
            var key_controller = new Gtk.EventControllerKey ();
            key_controller.key_pressed.connect (on_key_pressed);
            ((Gtk.Widget) this).add_controller (key_controller);
        }

        private bool on_key_pressed (uint keyval, uint keycode, Gdk.ModifierType state) {
            switch (keyval) {
                case Gdk.Key.Left: return route_navigation (-1, 0);
                case Gdk.Key.Right: return route_navigation (1, 0);
                case Gdk.Key.Up: return route_navigation (0, -1);
                case Gdk.Key.Down: return route_navigation (0, 1);
                case Gdk.Key.Return:
                case Gdk.Key.KP_Enter:
                case Gdk.Key.space: return activate_focused ();
                default: return false;
            }
        }

        private bool route_navigation (int dx, int dy) {
            if (group_grid != null) return group_grid.navigate_groups (dx, dy);
            return navigate_focus (dx, dy);
        }

        public int get_focused_index () {
            for (uint i = 0; i < placements.length; i++) {
                var w = placements[i].widget;
                if (w.has_focus || w.has_css_class ("tile-focused"))
                    return (int) i;
            }
            return -1;
        }

        public int get_focused_y () {
            int idx = get_focused_index ();
            if (idx < 0) return 0;
            return get_visual_y (placements[idx]);
        }

        public bool focus_first () {
            if (placements.length == 0) return false;
            set_tile_focus (0);
            return true;
        }

        public void clear_tile_focus () {
            for (uint i = 0; i < placements.length; i++) placements[i].widget.remove_css_class ("tile-focused");
        }

        private void set_tile_focus (int idx) {
            if (group_grid != null) group_grid.clear_other_focus (this);
            for (uint i = 0; i < placements.length; i++) {
                placements[i].widget.remove_css_class ("tile-focused");
            }
            if (idx >= 0 && idx < (int) placements.length) {
                placements[idx].widget.add_css_class ("tile-focused");
                placements[idx].widget.grab_focus ();
            }
        }

        private int get_visual_y (TilePlacement p) {
            if (!p.below) return p.y;
            return p.y + compute_animated_offset ();
        }

        public bool navigate_focus (int dx, int dy) {
            int current = get_focused_index ();
            if (current < 0) {
                if (placements.length > 0) { set_tile_focus (0); return true; }
                return false;
            }

            var cur = placements[current];
            int cx = cur.x + cur.w / 2;
            int cy = get_visual_y (cur) + cur.h / 2;

            int best = -1;
            int best_dist = int.MAX;

            for (uint i = 0; i < placements.length; i++) {
                if ((int) i == current) continue;
                var p = placements[i];
                int wx_c = p.x + p.w / 2;
                int wy_c = get_visual_y (p) + p.h / 2;

                int ddx = wx_c - cx;
                int ddy = wy_c - cy;

                if (dx > 0 && ddx <= 0) continue;
                if (dx < 0 && ddx >= 0) continue;
                if (dy > 0 && ddy <= 0) continue;
                if (dy < 0 && ddy >= 0) continue;

                // Bias toward primary axis
                int dist = dx != 0
                    ? ddx.abs () + ddy.abs () * 3
                    : ddy.abs () + ddx.abs () * 3;

                if (dist < best_dist) {
                    best_dist = dist;
                    best = (int) i;
                }
            }

            if (best >= 0) { set_tile_focus (best); return true; }
            return false;
        }

        private void focus_folder_first () {
            for (uint i = 0; i < placements.length; i++) {
                if (placements[i].is_folder_item) {
                    set_tile_focus ((int) i);
                    return;
                }
            }
        }

        public bool activate_focused () {
            int idx = get_focused_index ();
            if (idx < 0) return false;

            var widget = placements[idx].widget;
            if (widget is Tile) {
                ((Tile) widget).tile_activated (((Tile) widget).app_entry);
                return true;
            } else if (widget is FolderTile) {
                ((FolderTile) widget).folder_clicked ((FolderTile) widget);
                return true;
            }
            return false;
        }

        // --- Data mutation handlers ---

        private void on_drop (string source_id, string target_id) {
            if (model.handle_drop (source_id, target_id)) {
                if (open_folder_id != null && !model.has_folder (open_folder_id)) {
                    close_folder_state ();
                }
                rebuild ();
                layout_changed ();
            }
        }

        private void on_size_change (string desktop_id, TileSize new_size) {
            if (model.change_tile_size (desktop_id, new_size)) {
                rebuild ();
                layout_changed ();
            }
        }

        private void on_remove (string desktop_id) {
            if (model.remove_tile (desktop_id)) {
                rebuild ();
                layout_changed ();
            }
        }

        private void on_create_folder (string desktop_id, string app_name) {
            if (model.create_folder (desktop_id, app_name)) {
                rebuild ();
                layout_changed ();
            }
        }

        private void on_ungroup (string folder_name) {
            if (open_folder_id == folder_name) {
                close_folder_state ();
            }
            if (model.ungroup_folder (folder_name)) {
                rebuild ();
                layout_changed ();
            }
        }

        private void on_rename (string old_name, string new_name) {
            if (model.rename_folder (old_name, new_name)) {
                if (open_folder_id == old_name) {
                    open_folder_id = new_name;
                }
                rebuild ();
                layout_changed ();
            }
        }

        private void on_remove_from_folder (string folder_name, string desktop_id) {
            model.remove_from_folder (folder_name, desktop_id);
            if (open_folder_id == folder_name && !model.has_folder (folder_name)) {
                close_folder_state ();
            }
            rebuild ();
            layout_changed ();
        }

        private void on_reorder_in_folder (string folder_name, string id_a, string id_b) {
            if (model.reorder_in_folder (folder_name, id_a, id_b)) {
                rebuild ();
                layout_changed ();
            }
        }

        // --- Public API ---

        public Gtk.Popover? get_active_popover () {
            for (uint i = 0; i < placements.length; i++) {
                var w = placements[i].widget;
                if (w is Tile) {
                    var p = ((Tile) w).active_popover;
                    if (p != null) return p;
                } else if (w is FolderTile) {
                    var p = ((FolderTile) w).active_popover;
                    if (p != null) return p;
                }
            }
            return null;
        }

        public void show_focused_context_menu () {
            int idx = get_focused_index ();
            if (idx < 0) return;
            var widget = placements[idx].widget;
            if (widget is Tile) {
                ((Tile) widget).open_context_menu ();
            } else if (widget is FolderTile) {
                ((FolderTile) widget).open_context_menu ();
            }
        }

        public bool has_open_folder () {
            return open_folder_id != null;
        }

        public void close_open_folder () {
            if (open_folder_id == null || drag_in_progress) return;
            if (horizontal) { close_folder_state (); rebuild (); return; }
            animator.cancel ();
            animator.run_cascade (animator.cascade_progress, 0.0, () => {
                animator.run_slide (animator.slide_progress, 0.0, () => {
                    close_folder_state ();
                    rebuild ();
                });
            });
        }

        public void try_extract_from_folder (string desktop_id) {
            if (open_folder_id != null) {
                on_remove_from_folder (open_folder_id, desktop_id);
            }
        }

        public GroupConfig to_config (string group_name, bool include_transient = false) {
            return model.to_group_config (group_name, include_transient);
        }

        private bool cleaned_up = false;

        public void cleanup () {
            if (cleaned_up) return;
            cleaned_up = true;
            drag_controller.cleanup ();
            animator.cleanup ();
            cleanup_folder_content ();
            for (uint i = 0; i < placements.length; i++) {
                cleanup_widget (placements[i].widget);
            }
            placements = new GenericArray<TilePlacement> ();
            folder_header = null;
            folder_drop_zone = null;
            open_folder_id = null;
        }

        protected override void dispose () {
            cleanup ();
            base.dispose ();
        }
    }
}
