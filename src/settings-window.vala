namespace XimperShellTileMenu {

    public class SettingsWindow : Adw.PreferencesWindow {

        private weak Application app;

        public SettingsWindow (Application app) {
            this.app = app;
            this.title = "Tile Menu Settings";
            this.default_width = 500;
            this.default_height = 550;
            this.modal = false;

            build_grid_page ();
        }

        private void build_grid_page () {
            var page = new Adw.PreferencesPage ();
            page.title = "Grid";
            page.icon_name = "view-app-grid-symbolic";

            var layout_group = new Adw.PreferencesGroup ();
            layout_group.title = "Layout";

            // Max columns
            var cols_row = new Adw.SpinRow.with_range (0, 30, 2);
            cols_row.title = "Max Columns";
            cols_row.subtitle = "0 = automatic";
            cols_row.value = app.config.max_columns;
            cols_row.notify["value"].connect (() => {
                app.config.max_columns = (int) cols_row.value;
                app.config.save ();
            });
            layout_group.add (cols_row);

            // Cell size
            var cell_row = new Adw.SpinRow.with_range (0, 256, 4);
            cell_row.title = "Cell Size";
            cell_row.subtitle = "0 = automatic (derived from Max Rows or screen)";
            cell_row.value = app.config.cell_size;
            cell_row.notify["value"].connect (() => {
                app.config.cell_size = (int) cell_row.value;
                app.config.save ();
            });
            layout_group.add (cell_row);

            // Layer
            var layer_row = new Adw.SpinRow.with_range (0, 3, 1);
            layer_row.title = "Layer";
            layer_row.subtitle = "0 = background, 1 = bottom, 2 = top, 3 = overlay";
            layer_row.value = app.config.layer;
            layer_row.notify["value"].connect (() => {
                app.config.layer = (int) layer_row.value;
                app.config.save ();
            });
            layout_group.add (layer_row);

            page.add (layout_group);

            // Data group
            var data_group = new Adw.PreferencesGroup ();
            data_group.title = "Data";

            // Reset layout
            var reset_row = new Adw.ActionRow ();
            reset_row.title = "Reset Layout";
            reset_row.subtitle = "Regenerate folders from app categories";
            var reset_btn = new Gtk.Button.with_label ("Reset");
            reset_btn.valign = Gtk.Align.CENTER;
            reset_btn.add_css_class ("destructive-action");
            reset_btn.clicked.connect (() => {
                var config_path = Path.build_filename (
                    Environment.get_user_config_dir (), "ximper-shell", "tile-menu", "config.json"
                );
                FileUtils.remove (config_path);
                app.config.load ();
            });
            reset_row.add_suffix (reset_btn);
            data_group.add (reset_row);

            page.add (data_group);

            add (page);
        }
    }
}
