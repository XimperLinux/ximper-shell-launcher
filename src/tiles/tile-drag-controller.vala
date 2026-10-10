namespace XimperShellLauncher {

    private class DragTilePosition : Object {
        public TilePlacement placement;
        public int origin_x;
        public int origin_y;
        public double x;
        public double y;
        public double from_x;
        public double from_y;
        public int target_x;
        public int target_y;
        public bool hidden = false;

        public DragTilePosition (TilePlacement placement, int x, int y) {
            this.placement = placement;
            origin_x = target_x = x;
            origin_y = target_y = y;
            this.x = from_x = x;
            this.y = from_y = y;
        }
    }

    // GTK drag lifecycle and a mutation-free visual layout. The model remains
    // the baseline until one complete, validated candidate is committed.
    public class TileDragController : Object {
        private weak TileBoard board;
        private weak Application app;
        private TileModel model;
        private GridPacker packer;
        private Gtk.DropTarget target;
        private Gtk.Box gap;
        private GenericArray<DragTilePosition> positions = new GenericArray<DragTilePosition> ();
        private GenericArray<TileConfig>? candidate;
        private GenericArray<CellPlacement>? candidate_cells;
        private GenericArray<TileConfig>? hit_tiles;
        private GenericArray<CellPlacement>? hit_cells;
        private string? hit_source_id;
        private int hit_folder_row = -1;
        private int hit_folder_height = 0;
        private Adw.TimedAnimation? animation;
        private weak Gtk.Widget? source_widget;
        // Keep the removed source invisible until deferred board destruction.
        private weak Gtk.Widget? transferred_widget;
        private Gdk.Paintable? source_paintable;
        private Gtk.Picture? committed_preview;
        private bool retained_positions;
        public Gdk.Paintable? source_image { get { return source_paintable; } }
        private string? source_id;
        private string? preview_key;
        private string? highlighted_folder;
        private bool local_drag = false;
        private bool hovering = false;
        private bool committed = false;
        private bool finishing = false;
        private bool disposed = false;
        private double pointer_x;
        private double pointer_y;
        private int gap_x;
        private int gap_y;
        private int gap_w;
        private int gap_h;
        public int folder_preview_bottom { get; private set; default = 0; }
        public bool has_folder_geometry { get; private set; default = false; }
        public int preview_folder_row { get; private set; default = -1; }
        public int preview_folder_height { get; private set; default = 0; }
        private string? original_folder;
        private double folder_y;
        private double folder_height;
        private double original_folder_y;
        private double original_folder_height;
        private double from_folder_y;
        private double from_folder_height;
        private double target_folder_y;
        private double target_folder_height;
        private bool folder_anchor_active = false;
        private int anchor_x;
        private int anchor_y;
        private int anchor_w;
        private int anchor_h;
        public bool busy { get { return local_drag || hovering || finishing; } }

        public TileDragController (TileBoard board, Application app, TileModel model, GridPacker packer) {
            this.board = board;
            this.app = app;
            this.model = model;
            this.packer = packer;
            gap = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            gap.add_css_class ("tile-insertion-gap");
            gap.can_target = false;
            gap.visible = false;
            gap.set_parent (board);
            target = new Gtk.DropTarget (typeof (string), Gdk.DragAction.MOVE);
            target.preload = true;
            // TileGrid resolves the actual live source board, not the payload
            // folder name (which is intentionally only unique within a group).
            target.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
            weak TileDragController weak_self = this;
            target.enter.connect ((x, y) => {
                var self = weak_self;
                if (self == null) return (Gdk.DragAction) 0;
                self.hovering = true;
                self.pointer_x = x;
                self.pointer_y = y;
                return self.update_from_target ();
            });
            target.motion.connect ((x, y) => {
                var self = weak_self;
                if (self == null) return (Gdk.DragAction) 0;
                self.pointer_x = x;
                self.pointer_y = y;
                return self.update_from_target ();
            });
            target.notify["value"].connect (() => {
                var self = weak_self;
                if (self != null && self.hovering) self.update_from_target ();
            });
            target.leave.connect (() => {
                var self = weak_self;
                if (self == null) return;
                self.hovering = false;
                if (!self.committed) self.restore_preview (!self.local_drag);
            });
            target.drop.connect ((value, x, y) => {
                var self = weak_self;
                if (self == null) return false;
                string? id = value.get_string ();
                if (id == null || !self.update_hover (id, x, y) || self.candidate == null) return false;
                var grid = self.board.group_grid;
                self.committed = grid != null ? grid.commit_drop (self.board, id, self.candidate) : self.model.commit_candidate (self.candidate);
                if (self.committed && grid == null) self.board.drag_layout_committed ();
                if (!self.committed) return false;
                if (!self.local_drag) self.finish_drag ();
                return true;
            });
            board.add_controller (target);
        }

        public void begin_source (Gtk.Widget widget, string id) {
            if (disposed) return;
            transferred_widget = null;
            source_widget = widget;
            // Freeze the complete tile before hiding its live GtkDragSource.
            source_paintable = new Gtk.WidgetPaintable (widget).get_current_image ();
            source_id = id;
            local_drag = true;
            committed = false;
            finishing = false;
            preview_key = null;
            hit_tiles = null;
            hit_cells = null;
            hit_source_id = null;
            capture_positions ();
            for (uint i = 0; i < positions.length; i++) {
                if (positions[i].placement.widget == widget) positions[i].hidden = true;
            }
            widget.opacity = 0;
        }

        public void show_committed_preview (Gdk.Paintable? image) {
            if (disposed || image == null || !gap.visible || gap_w <= 0 || gap_h <= 0) return;
            clear_committed_preview ();
            committed_preview = new Gtk.Picture.for_paintable (image);
            committed_preview.can_shrink = true;
            committed_preview.content_fit = Gtk.ContentFit.FILL;
            committed_preview.can_target = false;
            committed_preview.hexpand = committed_preview.vexpand = true;
            gap.append (committed_preview);
            gap.add_css_class ("committed-tile-preview");
            gap.visible = true;
            board.queue_allocate ();
        }

        public void clear_committed_preview () {
            if (committed_preview != null) {
                gap.remove (committed_preview);
                committed_preview = null;
            }
            gap.remove_css_class ("committed-tile-preview");
            gap.visible = false;
            if (retained_positions) {
                positions = new GenericArray<DragTilePosition> ();
                retained_positions = false;
            }
        }

        public void commit_source_transfer () {
            if (disposed || !local_drag) return;
            committed = true;
            transferred_widget = source_widget;
            if (animation != null) animation.pause ();
            animation = null;
        }

        public void end_source () {
            if (disposed) return;
            local_drag = false;
            hovering = false;
            finish_drag ();
        }

        private void capture_positions () {
            if (positions.length > 0) return;
            int row, height;
            original_folder = board.get_drag_folder_baseline (out row, out height);
            original_folder_y = folder_y = packer.horizontal ? 0 : (row + 1) * (packer.cell_size + GridPacker.SPACING);
            original_folder_height = folder_height = height;
            var placements = board.get_drag_placements ();
            for (uint i = 0; i < placements.length; i++) {
                int x, y;
                board.get_drag_base_position (placements[i], out x, out y);
                positions.add (new DragTilePosition (placements[i], x, y));
            }
        }

        private Gdk.DragAction update_from_target () {
            unowned GLib.Value? value = target.get_value ();
            string? id = value != null ? value.get_string () : (local_drag ? source_id : null);
            if (id == null) return Gdk.DragAction.MOVE; // Wait for preloaded string data.
            return update_hover (id, pointer_x, pointer_y) ? Gdk.DragAction.MOVE : (Gdk.DragAction) 0;
        }

        private string widget_id (Gtk.Widget widget) {
            if (widget is Tile) return ((Tile) widget).app_entry.desktop_id;
            if (widget is FolderTile) return ((FolderTile) widget).folder_id;
            return "";
        }

        private int original_index (string id) {
            for (uint i = 0; i < model.tiles.length; i++)
                if (model.tiles[i].desktop_id == id) return (int) i;
            return -1;
        }

        private bool prepare_hit_layout (string id, bool allow_new) {
            if (hit_source_id == id && hit_tiles != null) return true;
            // Pack the remaining tiles once, without either the source or its
            // preview gap. Moving the visual gap must never move input targets.
            bool cross = board.group_grid != null && board.group_grid.is_cross_drag (board, id);
            var remaining = cross ? model.copy_tiles () : model.preview_insert (id, (int) model.tiles.length, allow_new);
            if (remaining == null) return false;
            if (!cross) for (uint i = 0; i < remaining.length; i++) {
                if (remaining[i].desktop_id == id) { remaining.remove_index (i); break; }
            }
            // An emptied source folder still exists in the live model until
            // drop. Keep its input target so its sole item can be dropped back.
            for (uint i = 0; i < model.tiles.length; i++) {
                var original = model.tiles[i];
                if (original.size != TileSize.FOLDER || original.desktop_id == id || original.folder_items == null)
                    continue;
                bool contains_source = false;
                for (uint j = 0; j < original.folder_items.length; j++)
                    if (original.folder_items[j] == id) contains_source = true;
                if (!contains_source) continue;
                bool retained = false;
                for (uint j = 0; j < remaining.length; j++)
                    if (remaining[j].desktop_id == original.desktop_id) retained = true;
                if (!retained) {
                    var empty = new TileConfig.folder (original.folder_name ?? "", new GenericArray<string> ());
                    empty.desktop_id = original.desktop_id;
                    remaining.insert ((int) uint.min (i, remaining.length), empty);
                }
            }
            hit_tiles = remaining;
            hit_cells = packer.pack (hit_tiles);
            hit_source_id = id;
            hit_folder_row = -1;
            hit_folder_height = 0;
            for (uint i = 0; i < hit_cells.length; i++) {
                var cell = hit_cells[i];
                if (hit_tiles[cell.config_index].folder_name == original_folder && original_folder != null) {
                    hit_folder_row = cell.row;
                    hit_folder_height = (int) original_folder_height;
                    break;
                }
            }
            return true;
        }

        private bool update_hover (string id, double x, double y) {
            if (disposed || committed) return committed;
            bool allow_new = app.app_provider.find_by_desktop_id (id) != null;
            if (id.has_prefix ("folder:") && !local_drag &&
                !(board.group_grid != null && board.group_grid.source_matches (id))) return false;
            if (!allow_new && original_index (id) < 0 &&
                !(board.group_grid != null && board.group_grid.source_matches (id))) return false;
            capture_positions ();
            finishing = false;
            source_id = id;
            if (!prepare_hit_layout (id, allow_new)) return false;
            string? folder_name = null;
            int boundary;
            int folder_y = (hit_folder_row + 1) * (packer.cell_size + GridPacker.SPACING);
            int folder_top = folder_y + GridPacker.FOLDER_HEADER_H + GridPacker.SPACING;
            int folder_bottom = folder_y + hit_folder_height;
            string? open_folder = hit_folder_row >= 0 ? original_folder : null;
            if (highlighted_folder != null && folder_anchor_active &&
                x >= anchor_x && x < anchor_x + anchor_w && y >= anchor_y && y < anchor_y + anchor_h) {
                folder_name = highlighted_folder;
                var folder = model.find_folder (folder_name);
                boundary = folder != null && folder.folder_items != null ? (int) folder.folder_items.length : 0;
            } else if (open_folder != null && !id.has_prefix ("folder:") &&
                (packer.horizontal ? x >= board.folder_panel_x (hit_tiles) && y >= GridPacker.FOLDER_HEADER_H + GridPacker.SPACING && y < packer.content_height :
                y >= folder_top && y < folder_bottom)) {
                folder_anchor_active = false;
                folder_name = open_folder;
                boundary = folder_boundary (open_folder, x, y, folder_top);
            } else {
                boundary = top_boundary (id, x, y, out folder_name);
            }
            string key = id + "|" + (folder_name ?? "") + "|" + boundary.to_string ();
            if (preview_key == key) return candidate != null;
            var grid = board.group_grid;
            var next = grid != null ? grid.preview_drop (board, id, boundary, folder_name) :
                (folder_name == null ? model.preview_insert (id, boundary, allow_new) : model.preview_folder_insert (folder_name, id, boundary, allow_new));
            if (next == null) { restore_preview (false); return false; }
            candidate = next;
            candidate_cells = packer.pack (candidate);
            update_folder_geometry ();
            preview_key = key;
            highlighted_folder = folder_name;
            animate_candidate (folder_name);
            return true;
        }

        private int folder_boundary (string name, double x, double y, int top) {
            var folder = model.find_folder (name);
            int count = folder != null && folder.folder_items != null ? (int) folder.folder_items.length : 0;
            int stride = packer.cell_size + GridPacker.SPACING;
            int origin_x = packer.horizontal ? board.folder_panel_x (hit_tiles) : packer.margin;
            if (packer.horizontal) top = GridPacker.FOLDER_HEADER_H + GridPacker.SPACING;
            int col = int.max (0, ((int) x - origin_x) / stride);
            int row = int.max (0, ((int) y - top) / stride);
            int index = packer.horizontal ? col * packer.folder_rows + row.clamp (0, packer.folder_rows - 1) : row * packer.columns + col.clamp (0, packer.columns - 1);
            bool after = packer.horizontal ? y - top - row * stride > packer.cell_size / 2.0 : x - origin_x - col * stride > packer.cell_size / 2.0;
            var visible_items = folder != null ? folder.folder_items : null;
            if (hit_tiles != null) {
                for (uint i = 0; i < hit_tiles.length; i++) {
                    if (hit_tiles[i].folder_name == name) visible_items = hit_tiles[i].folder_items;
                }
            }
            if (visible_items == null || index >= visible_items.length) return count;
            string target_id = visible_items[index];
            for (uint i = 0; folder != null && folder.folder_items != null && i < folder.folder_items.length; i++) {
                if (folder.folder_items[i] == target_id) return (int) i + (after ? 1 : 0);
            }
            return count;
        }

        private int top_boundary (string id, double x, double y, out string? folder_name) {
            folder_name = null;
            // This is the logical layout WITHOUT the dragged tile. Do not use
            // candidate_cells here: they already contain the moving gap.
            var configs = hit_tiles;
            var cells = hit_cells;
            folder_anchor_active = false;
            int nearest = (int) model.tiles.length;
            double nearest_row_distance = double.MAX;
            double nearest_column_distance = double.MAX;
            int grid_bottom = hit_folder_row >= 0
                ? (hit_folder_row + 1) * (packer.cell_size + GridPacker.SPACING) + hit_folder_height : 0;
            for (uint i = 0; i < cells.length; i++) {
                var cell = cells[i];
                var config = configs[cell.config_index];
                int cx, cy, cw, ch;
                hit_cell_rect (cell, out cx, out cy, out cw, out ch);
                grid_bottom = int.max (grid_bottom, cy + ch);
                int index = original_index (config.desktop_id);
                if (index < 0) continue;
                if (!id.has_prefix ("folder:") && config.size == TileSize.FOLDER &&
                    x > cx + cw * 0.25 && x < cx + cw * 0.75 &&
                    y > cy + ch * 0.2 && y < cy + ch * 0.8) {
                    folder_name = config.folder_name;
                    folder_anchor_active = true;
                    // Hysteresis only within the original center, never on
                    // insertion edges: moving from center to edge changes mode.
                    anchor_x = cx + cw / 4;
                    anchor_y = cy + ch / 5;
                    anchor_w = cw / 2;
                    anchor_h = ch * 3 / 5;
                    var original = model.find_folder (folder_name);
                    return original != null && original.folder_items != null
                        ? (int) original.folder_items.length : 0;
                }
                double dx = x < cx ? cx - x : (x > cx + cw ? x - cx - cw : 0);
                double dy = y < cy ? cy - y : (y > cy + ch ? y - cy - ch : 0);
                // Choose the row first. Far-right empty space in a short last
                // row belongs after that row, not to a full row above it.
                double primary = packer.horizontal ? dx : dy;
                double secondary = packer.horizontal ? dy : dx;
                if (primary < nearest_row_distance ||
                    (primary == nearest_row_distance && secondary < nearest_column_distance)) {
                    nearest_row_distance = primary;
                    nearest_column_distance = secondary;
                    bool after = packer.horizontal ? x >= cx + cw || (x >= cx && y >= cy + ch / 2.0) : y >= cy + ch || (y >= cy && x >= cx + cw / 2.0);
                    nearest = index + (after ? 1 : 0);
                }
            }
            return !packer.horizontal && y >= grid_bottom ? (int) model.tiles.length : nearest;
        }

        private void hit_cell_rect (CellPlacement cell, out int x, out int y, out int w, out int h) {
            x = packer.margin + cell.col * (packer.cell_size + GridPacker.SPACING);
            y = cell.row * (packer.cell_size + GridPacker.SPACING);
            if (!packer.horizontal && hit_folder_row >= 0 && (cell.row > hit_folder_row ||
                (cell.row <= hit_folder_row && cell.row + cell.row_span > hit_folder_row + 1)))
                y += hit_folder_height;
            w = cell.col_span * packer.cell_size + (cell.col_span - 1) * GridPacker.SPACING;
            h = cell.row_span * packer.cell_size + (cell.row_span - 1) * GridPacker.SPACING;
        }

        private void cell_rect (CellPlacement cell, out int x, out int y, out int w, out int h) {
            x = packer.margin + cell.col * (packer.cell_size + GridPacker.SPACING);
            y = cell.row * (packer.cell_size + GridPacker.SPACING);
            if (has_folder_geometry && !packer.horizontal) {
                if (preview_folder_row >= 0 && (cell.row > preview_folder_row ||
                    (cell.row <= preview_folder_row && cell.row + cell.row_span > preview_folder_row + 1)))
                    y += preview_folder_height;
            } else if (board.drag_cell_below_folder (cell.row, cell.row + cell.row_span)) {
                y += board.get_drag_folder_offset ();
            }
            w = cell.col_span * packer.cell_size + (cell.col_span - 1) * GridPacker.SPACING;
            h = cell.row_span * packer.cell_size + (cell.row_span - 1) * GridPacker.SPACING;
        }

        private TileConfig? candidate_folder (string? name) {
            if (name == null || candidate == null) return null;
            for (uint i = 0; i < candidate.length; i++) {
                if (candidate[i].size == TileSize.FOLDER && candidate[i].folder_name == name)
                    return candidate[i];
            }
            return null;
        }

        private void update_folder_geometry () {
            has_folder_geometry = original_folder != null;
            preview_folder_row = -1;
            preview_folder_height = 0;
            folder_preview_bottom = 0;
            target_folder_y = packer.horizontal ? 0 : original_folder_y;
            target_folder_height = 0;
            var folder = candidate_folder (original_folder);
            if (folder == null || folder.folder_items == null) return;
            for (uint i = 0; i < candidate_cells.length; i++) {
                var cell = candidate_cells[i];
                if (candidate[cell.config_index].desktop_id != folder.desktop_id) continue;
                preview_folder_row = cell.row;
                preview_folder_height = packer.compute_folder_height ((int) folder.folder_items.length);
                target_folder_y = packer.horizontal ? 0 : (cell.row + 1) * (packer.cell_size + GridPacker.SPACING);
                target_folder_height = preview_folder_height;
                folder_preview_bottom = (int) target_folder_y + preview_folder_height;
                break;
            }
        }

        public bool get_folder_render (out int y, out int height, out bool visible) {
            y = (int) folder_y;
            height = (int) folder_height;
            visible = !has_folder_geometry || preview_folder_row >= 0;
            return positions.length > 0 && original_folder != null;
        }

        private void animate_candidate (string? folder_name) {
            gap.visible = false;
            for (uint i = 0; i < positions.length; i++) {
                var position = positions[i];
                position.target_x = position.origin_x;
                position.target_y = position.origin_y;
                position.hidden = false;
                string id = widget_id (position.placement.widget);
                if (!position.placement.is_folder_item) {
                    bool found = false;
                    for (uint j = 0; j < candidate_cells.length; j++) {
                        var cell = candidate_cells[j];
                        if (candidate[cell.config_index].desktop_id != id) continue;
                        int w, h;
                        cell_rect (cell, out position.target_x, out position.target_y, out w, out h);
                        found = true;
                        break;
                    }
                    position.hidden = !found;
                } else {
                    position.hidden = true;
                    for (uint j = 0; j < candidate.length; j++) {
                        var folder = candidate[j];
                        if (folder.folder_name != original_folder || folder.folder_items == null) continue;
                        int top, bottom;
                        if (board.get_drag_folder (out top, out bottom) != original_folder) break;
                        for (uint k = 0; k < folder.folder_items.length; k++) {
                            if (folder.folder_items[k] != id) continue;
                            if (packer.horizontal) board.folder_item_position ((int) k, out position.target_x, out position.target_y, candidate);
                            else {
                                position.target_x = packer.margin + (int) (k % packer.columns) * (packer.cell_size + GridPacker.SPACING);
                                position.target_y = top + (int) (k / packer.columns) * (packer.cell_size + GridPacker.SPACING);
                            }
                            position.hidden = false;
                            break;
                        }
                        break;
                    }
                }
                if (position.placement.widget == source_widget || id == source_id) {
                    position.target_x = position.origin_x;
                    position.target_y = position.origin_y;
                    position.hidden = true;
                }
                if (position.placement.widget is FolderTile) {
                    var folder = (FolderTile) position.placement.widget;
                    folder.remove_css_class ("tile-drop-into-folder");
                    if (folder.folder_name == folder_name) folder.add_css_class ("tile-drop-into-folder");
                }
            }
            if (folder_name == null) {
                for (uint i = 0; i < candidate_cells.length; i++) {
                    var cell = candidate_cells[i];
                    if (candidate[cell.config_index].desktop_id != source_id) continue;
                    cell_rect (cell, out gap_x, out gap_y, out gap_w, out gap_h);
                    gap.visible = true;
                    break;
                }
            } else {
                int top, bottom;
                if (board.get_drag_folder (out top, out bottom) == folder_name) {
                    for (uint i = 0; i < candidate.length; i++) {
                        var folder = candidate[i];
                        if (folder.folder_name != folder_name || folder.folder_items == null) continue;
                        int rows = ((int) folder.folder_items.length + packer.columns - 1) / packer.columns;
                        folder_preview_bottom = top + rows * (packer.cell_size + GridPacker.SPACING);
                        for (uint j = 0; j < folder.folder_items.length; j++) {
                            if (folder.folder_items[j] != source_id) continue;
                            if (packer.horizontal) board.folder_item_position ((int) j, out gap_x, out gap_y, candidate);
                            else {
                                gap_x = packer.margin + (int) (j % packer.columns) * (packer.cell_size + GridPacker.SPACING);
                                gap_y = top + (int) (j / packer.columns) * (packer.cell_size + GridPacker.SPACING);
                            }
                            gap_w = gap_h = packer.cell_size;
                            gap.visible = true;
                            break;
                        }
                    }
                }
            }
            play_animation (false);
        }

        private void play_animation (bool finish) {
            if (animation != null) animation.pause ();
            from_folder_y = folder_y;
            from_folder_height = folder_height;
            for (uint i = 0; i < positions.length; i++) {
                positions[i].from_x = positions[i].x;
                positions[i].from_y = positions[i].y;
            }
            weak TileDragController weak_self = this;
            animation = new Adw.TimedAnimation (board, 0, 1, 180,
                new Adw.CallbackAnimationTarget ((progress) => {
                    var self = weak_self;
                    if (self == null || self.disposed) return;
                    for (uint i = 0; i < self.positions.length; i++) {
                        var p = self.positions[i];
                        p.x = p.from_x + (p.target_x - p.from_x) * progress;
                        p.y = p.from_y + (p.target_y - p.from_y) * progress;
                    }
                    self.folder_y = self.from_folder_y + (self.target_folder_y - self.from_folder_y) * progress;
                    self.folder_height = self.from_folder_height +
                        (self.target_folder_height - self.from_folder_height) * progress;
                    self.board.queue_allocate ();
                }));
            animation.easing = Adw.Easing.EASE_OUT_CUBIC;
            if (finish) {
                animation.done.connect (() => {
                    var self = weak_self;
                    if (self == null || self.disposed) return;
                    Idle.add (() => {
                        var current = weak_self;
                        if (current != null && !current.disposed && current.finishing) current.complete_finish ();
                        return Source.REMOVE;
                    });
                });
            }
            animation.play ();
            board.queue_resize ();
        }

        private void restore_preview (bool finish) {
            candidate = null;
            candidate_cells = null;
            preview_key = null;
            highlighted_folder = null;
            folder_anchor_active = false;
            has_folder_geometry = false;
            target_folder_y = original_folder_y;
            target_folder_height = original_folder_height;
            folder_preview_bottom = 0;
            gap.visible = false;
            for (uint i = 0; i < positions.length; i++) {
                var p = positions[i];
                p.target_x = p.origin_x;
                p.target_y = p.origin_y;
                p.hidden = p.placement.widget == source_widget && local_drag;
                p.placement.widget.remove_css_class ("tile-drop-into-folder");
            }
            finishing = finish;
            play_animation (finish);
        }

        private void finish_drag () {
            if (committed) {
                finishing = true;
                weak TileDragController weak_self = this;
                Idle.add (() => {
                    var self = weak_self;
                    if (self != null && !self.disposed && self.finishing) self.complete_finish ();
                    return Source.REMOVE;
                });
            } else {
                restore_preview (true);
            }
        }

        private void complete_finish () {
            if (animation != null) animation.pause ();
            animation = null;
            bool rebuild = committed;
            for (uint i = 0; i < positions.length; i++) {
                positions[i].placement.widget.opacity = positions[i].placement.widget == transferred_widget ? 0 : 1;
                positions[i].placement.widget.remove_css_class ("tile-drop-into-folder");
            }
            retained_positions = committed_preview != null;
            if (retained_positions) {
                // Keep neighbors at their accepted positions too; returning
                // them to old placement coordinates would look like a reorder.
                for (uint i = 0; i < positions.length; i++) {
                    positions[i].x = positions[i].target_x;
                    positions[i].y = positions[i].target_y;
                }
            } else {
                positions = new GenericArray<DragTilePosition> ();
            }
            candidate = null;
            candidate_cells = null;
            preview_key = null;
            source_widget = null;
            source_paintable = null;
            source_id = null;
            hit_tiles = null;
            hit_cells = null;
            hit_source_id = null;
            highlighted_folder = null;
            folder_anchor_active = false;
            has_folder_geometry = false;
            original_folder = null;
            folder_preview_bottom = 0;
            committed = local_drag = hovering = finishing = false;
            // Keep the accepted tile visible while a different source board is
            // still finishing. Rebuild replaces it with the real widget.
            gap.visible = committed_preview != null;
            board.drag_preview_finished (rebuild);
        }

        public bool get_position (TilePlacement placement, out int x, out int y, out bool hidden) {
            x = y = 0;
            hidden = false;
            if (placement.widget == transferred_widget) {
                x = placement.x;
                y = placement.y;
                hidden = true;
                return true;
            }
            for (uint i = 0; i < positions.length; i++) {
                var p = positions[i];
                if (p.placement != placement) continue;
                x = (int) p.x;
                y = (int) p.y;
                hidden = p.hidden;
                return true;
            }
            return false;
        }

        public void allocate_gap () {
            if (!gap.visible) return;
            if (board.get_last_child () != gap) gap.insert_after (board, board.get_last_child ());
            var point = Graphene.Point ();
            point.init (gap_x, gap_y);
            int minimum, natural;
            gap.measure (Gtk.Orientation.HORIZONTAL, -1, out minimum, out natural, null, null);
            gap.measure (Gtk.Orientation.VERTICAL, gap_w, out minimum, out natural, null, null);
            gap.allocate (gap_w, gap_h, -1, new Gsk.Transform ().translate (point));
        }

        public int folder_panel_left () { return board.folder_panel_x (candidate); }

        public int preview_right () {
            int edge = gap.visible ? gap_x + gap_w : 0;
            for (uint i = 0; i < positions.length; i++) {
                var p = positions[i];
                if (!p.hidden) edge = int.max (edge, p.target_x + p.placement.w);
            }
            return edge;
        }

        public int preview_bottom () {
            int bottom = int.max (folder_preview_bottom, gap.visible ? gap_y + gap_h : 0);
            for (uint i = 0; i < positions.length; i++) {
                var p = positions[i];
                if (!p.hidden) bottom = int.max (bottom, p.target_y + p.placement.h);
            }
            return bottom;
        }

        public void cleanup () {
            if (disposed) return;
            disposed = true;
            if (animation != null) animation.pause ();
            animation = null;
            if (board != null) board.remove_controller (target);
            clear_committed_preview ();
            source_paintable = null;
            if (gap.get_parent () != null) gap.unparent ();
            hit_tiles = null;
            hit_cells = null;
            hit_source_id = null;
            positions = new GenericArray<DragTilePosition> ();
        }

        protected override void dispose () {
            cleanup ();
            base.dispose ();
        }
    }
}
