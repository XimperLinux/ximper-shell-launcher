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
                try {
                    var config_path = Path.build_filename (
                        Environment.get_user_config_dir (), "ximper-shell", "tile-menu", "config.json"
                    );
                    FileUtils.remove (config_path);
                    app.config.load ();
                } catch (Error e) {}
            });
            reset_row.add_suffix (reset_btn);
            data_group.add (reset_row);

            page.add (data_group);

            add (page);
        }
    }
}
