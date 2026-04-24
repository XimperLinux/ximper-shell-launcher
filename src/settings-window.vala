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

            var mode_row = new Adw.ComboRow ();
            mode_row.title = "Window Mode";
            mode_row.subtitle = "Fullscreen overlay or floating panel";
            var mode_list = new Gtk.StringList ({"Fullscreen", "Floating"});
            mode_row.model = mode_list;
            mode_row.selected = app.config.window_mode == WindowMode.FULLSCREEN ? 0 : 1;
            mode_row.notify["selected"].connect (() => {
                app.config.window_mode = mode_row.selected == 0 ? WindowMode.FULLSCREEN : WindowMode.FLOATING;
                app.config.save ();
            });
            layout_group.add (mode_row);

            var monitor_row = new Adw.ComboRow ();
            monitor_row.title = "Monitor";
            monitor_row.subtitle = "Active Monitor uses the monitor under the pointer";
            var monitor_list = build_monitor_list ();
            monitor_row.model = monitor_list;
            monitor_row.selected = (uint) (app.config.monitor_index + 1).clamp (
                0,
                (int) monitor_list.get_n_items () - 1
            );
            monitor_row.notify["selected"].connect (() => {
                app.config.monitor_index = (int) monitor_row.selected - 1;
                app.config.save ();
            });
            layout_group.add (monitor_row);

            var floating_x_row = new Adw.SpinRow.with_range (0, 100, 1);
            floating_x_row.title = "Floating X (%)";
            floating_x_row.subtitle = "Horizontal position as percent of screen width";
            floating_x_row.value = app.config.floating_x_percent;
            floating_x_row.notify["value"].connect (() => {
                app.config.floating_x_percent = (int) floating_x_row.value;
                app.config.save ();
            });
            layout_group.add (floating_x_row);

            var floating_y_row = new Adw.SpinRow.with_range (0, 100, 1);
            floating_y_row.title = "Floating Y (%)";
            floating_y_row.subtitle = "Vertical position as percent of screen height";
            floating_y_row.value = app.config.floating_y_percent;
            floating_y_row.notify["value"].connect (() => {
                app.config.floating_y_percent = (int) floating_y_row.value;
                app.config.save ();
            });
            layout_group.add (floating_y_row);

            var floating_width_row = new Adw.SpinRow.with_range (320, 4096, 10);
            floating_width_row.title = "Floating Width";
            floating_width_row.subtitle = "Window width in pixels";
            floating_width_row.value = app.config.floating_width;
            floating_width_row.notify["value"].connect (() => {
                app.config.floating_width = (int) floating_width_row.value;
                app.config.save ();
            });
            layout_group.add (floating_width_row);

            var floating_height_row = new Adw.SpinRow.with_range (240, 4096, 10);
            floating_height_row.title = "Floating Height";
            floating_height_row.subtitle = "Window height in pixels";
            floating_height_row.value = app.config.floating_height;
            floating_height_row.notify["value"].connect (() => {
                app.config.floating_height = (int) floating_height_row.value;
                app.config.save ();
            });
            layout_group.add (floating_height_row);

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

        private Gtk.StringList build_monitor_list () {
            var list = new Gtk.StringList (null);
            list.append ("Active Monitor");

            var display = Gdk.Display.get_default ();
            if (display == null) return list;

            var monitors = display.get_monitors ();
            for (uint i = 0; i < monitors.get_n_items (); i++) {
                var monitor = (Gdk.Monitor) monitors.get_item (i);
                var geometry = monitor.geometry;
                var connector = monitor.get_connector ();
                if (connector != null && connector.length > 0) {
                    list.append (
                        "Monitor %u: %s (%dx%d)".printf (
                            i + 1,
                            connector,
                            geometry.width,
                            geometry.height
                        )
                    );
                } else {
                    list.append ("Monitor %u (%dx%d)".printf (i + 1, geometry.width, geometry.height));
                }
            }

            return list;
        }
    }
}
