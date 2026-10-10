namespace XimperShellLauncher {

    public class CellPlacement {
        public int col;
        public int row;
        public int col_span;
        public int row_span;
        public int config_index;

        public CellPlacement (int col, int row, int col_span, int row_span, int config_index) {
            this.col = col;
            this.row = row;
            this.col_span = col_span;
            this.row_span = row_span;
            this.config_index = config_index;
        }
    }

    public class TilePlacement {
        public Gtk.Widget widget;
        public int x;
        public int y;
        public int w;
        public int h;
        public bool below;
        public bool is_folder_item;
        public int folder_index;

        public TilePlacement (Gtk.Widget widget, int x, int y, int w, int h) {
            this.widget = widget;
            this.x = x;
            this.y = y;
            this.w = w;
            this.h = h;
        }
    }

    public class GridPacker {

        public int columns { get; private set; default = 10; }
        public int cell_size { get; private set; default = 80; }
        public int margin { get; private set; default = 24; }

        public bool horizontal { get; private set; default = false; }
        public int rows { get; private set; default = 2; }
        public int content_height { get; private set; default = 160; }
        public int folder_rows { get { return int.max (1, (content_height - FOLDER_HEADER_H - SPACING + SPACING) / (cell_size + SPACING)); } }

        public bool compute_for_height (int height, int cfg_cell) {
            int cell = cfg_cell > 0 ? cfg_cell : 70;
            // Keep a large (2x2) tile accessible even in a short floating menu.
            cell = int.max (1, int.min (cell, (int.max (8, height) - SPACING) / 2));
            int count = int.max (2, (height + SPACING) / (cell + SPACING));
            bool changed = !horizontal || rows != count || cell_size != cell || content_height != height;
            horizontal = true; rows = count; cell_size = cell;
            content_height = height; margin = MIN_MARGIN;
            return changed;
        }

        public const int SPACING = 6;
        public const int MIN_MARGIN = 24;
        public const int FOLDER_HEADER_H = 32;

        // Returns true if layout params changed
        public bool compute_for_size (int width, int cfg_cell, int max_col) {
            horizontal = false;
            int usable = width - MIN_MARGIN * 2;
            if (usable < 200) usable = 200;

            int new_cell;
            int new_cols;

            if (cfg_cell > 0) {
                new_cell = cfg_cell;
                new_cols = usable / (new_cell + SPACING);
            } else {
                new_cols = usable / (70 + SPACING);
                new_cell = (usable - (new_cols - 1) * SPACING) / new_cols;
            }

            if (max_col <= 0) max_col = 18;
            if (new_cols > max_col) new_cols = max_col;
            if (new_cols < 4) new_cols = 4;
            if (new_cols % 2 != 0) new_cols--;

            if (cfg_cell <= 0) {
                new_cell = (usable - (new_cols - 1) * SPACING) / new_cols;
            }

            int grid_w = new_cols * (new_cell + SPACING) - SPACING;
            int new_margin = (width - grid_w) / 2;
            if (new_margin < MIN_MARGIN) new_margin = MIN_MARGIN;

            bool changed = new_cols != columns || new_cell != cell_size || new_margin != margin;
            columns = new_cols;
            cell_size = new_cell;
            margin = new_margin;
            return changed;
        }

        public GenericArray<CellPlacement> pack (GenericArray<TileConfig> tiles) {
            if (horizontal) return pack_horizontal (tiles);
            var max_rows = (int) tiles.length * 2 + 4;
            bool[,] occupied = new bool[max_rows, columns];
            var result = new GenericArray<CellPlacement> ();
            int cursor = 0;

            for (uint i = 0; i < tiles.length; i++) {
                int cs, rs;
                get_spans (tiles[i].size, out cs, out rs);
                if (cs > columns) cs = columns;

                int col, row;
                find_free (occupied, max_rows, cs, rs, cursor, out col, out row);
                // Preserve visual order: never backfill gaps preceding this anchor.
                cursor = row * columns + col + 1;

                for (int r = row; r < row + rs; r++)
                    for (int c = col; c < col + cs; c++)
                        if (r < max_rows && c < columns)
                            occupied[r, c] = true;

                result.add (new CellPlacement (col, row, cs, rs, (int) i));
            }

            return result;
        }

        private GenericArray<CellPlacement> pack_horizontal (GenericArray<TileConfig> tiles) {
            int max_columns = (int) tiles.length * 2 + 4;
            bool[,] occupied = new bool[rows, max_columns];
            var result = new GenericArray<CellPlacement> ();
            int cursor = 0;
            for (uint i = 0; i < tiles.length; i++) {
                int cs, rs;
                get_spans (tiles[i].size, out cs, out rs);
                int col = 0, row = 0;
                for (int anchor = cursor; anchor < max_columns * rows; anchor++) {
                    col = anchor / rows; row = anchor % rows;
                    if (row + rs > rows || col + cs > max_columns) continue;
                    bool free = true;
                    for (int r = row; r < row + rs; r++)
                        for (int c = col; c < col + cs; c++)
                            if (occupied[r, c]) free = false;
                    if (free) { cursor = anchor + 1; break; }
                }
                for (int r = row; r < row + rs; r++)
                    for (int c = col; c < col + cs; c++) occupied[r, c] = true;
                result.add (new CellPlacement (col, row, cs, rs, (int) i));
            }
            return result;
        }

        public static void get_spans (TileSize size, out int cs, out int rs) {
            switch (size) {
                case TileSize.SMALL: cs = 1; rs = 1; break;
                case TileSize.MEDIUM: cs = 2; rs = 1; break;
                case TileSize.LARGE: cs = 2; rs = 2; break;
                default: cs = 1; rs = 1; break;
            }
        }

        private void find_free (bool[,] occ, int max_r, int cs, int rs, int cursor,
                                out int oc, out int or) {
            for (int r = cursor / columns; r < max_r; r++) {
                for (int c = 0; c <= columns - cs; c++) {
                    if (r * columns + c < cursor) continue;
                    bool ok = true;
                    for (int dr = 0; dr < rs && ok; dr++)
                        for (int dc = 0; dc < cs && ok; dc++)
                            if (r + dr >= max_r || occ[r + dr, c + dc]) ok = false;
                    if (ok) { oc = c; or = r; return; }
                }
            }
            oc = 0; or = max_r;
        }

        public int compute_folder_height (int item_count) {
            if (item_count <= 0) return 0;
            if (horizontal) return content_height;
            int rows = (item_count + columns - 1) / columns;
            return rows * (cell_size + SPACING) + FOLDER_HEADER_H + SPACING;
        }
    }
}
