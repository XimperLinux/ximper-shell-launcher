namespace XimperShellLauncher {

    public class SettingsWindow : Adw.PreferencesWindow {

        private weak Application app;
        private GenericArray<Gtk.Widget> tile_only_widgets = new GenericArray<Gtk.Widget> ();
        private GenericArray<Gtk.Widget> wofi_only_widgets = new GenericArray<Gtk.Widget> ();
        private Gtk.ListBox? search_providers_list;
        private GenericArray<SearchProviderRow> search_provider_rows = new GenericArray<SearchProviderRow> ();

        private class SearchProviderRow : Object {
            public string id;
            public Gtk.ListBoxRow row;

            public SearchProviderRow (string id, Gtk.ListBoxRow row) {
                this.id = id;
                this.row = row;
            }
        }

        public SettingsWindow (Application app) {
            this.app = app;
            this.title = _("Launcher Settings");
            this.default_width = 500;
            this.default_height = 550;
            this.modal = false;

            build_grid_page ();
            build_search_page ();
        }

        private void build_search_page () {
            var page = new Adw.PreferencesPage ();
            page.title = _("Search");
            page.icon_name = "system-search-symbolic";

            var group = new Adw.PreferencesGroup ();
            group.title = _("Search Providers");
            group.description = _("Drag providers to change the order of search results.");

            search_providers_list = new Gtk.ListBox ();
            search_providers_list.selection_mode = Gtk.SelectionMode.NONE;
            search_providers_list.add_css_class ("boxed-list");
            group.add (search_providers_list);
            page.add (group);
            add (page);
            refresh_search_providers ();
        }

        private void refresh_search_providers () {
            if (search_providers_list == null) return;
            search_providers_list.remove_all ();
            search_provider_rows = new GenericArray<SearchProviderRow> ();

            var manager = new SearchProviderManager (app.config);
            manager.scan_providers ();
            for (uint i = 0; i < manager.providers.length; i++) {
                var provider = manager.providers[i];
                var content = new Adw.ActionRow ();
                content.title = provider.name ?? provider.desktop_id;
                content.subtitle = provider.desktop_id;

                if (provider.icon != null) {
                    var image = new Gtk.Image.from_gicon (provider.icon);
                    image.pixel_size = 24;
                    content.add_prefix (image);
                }

                var handle = new Gtk.Image.from_icon_name ("list-drag-handle-symbolic");
                handle.tooltip_text = _("Drag to reorder");
                content.add_prefix (handle);

                var enabled = new Gtk.Switch ();
                enabled.valign = Gtk.Align.CENTER;
                enabled.active = app.config.is_search_provider_enabled (provider.desktop_id);
                enabled.notify["active"].connect (() => {
                    app.config.set_search_provider_enabled (provider.desktop_id, enabled.active);
                    app.config.save ();
                });
                content.add_suffix (enabled);

                var row = new Gtk.ListBoxRow ();
                row.set_child (content);
                var provider_row = new SearchProviderRow (provider.desktop_id, row);

                // Only the handle starts a drag, as in GNOME Settings. This keeps
                // switches and row activation from accidentally initiating one.
                var source = new Gtk.DragSource ();
                source.actions = Gdk.DragAction.MOVE;
                source.prepare.connect ((x, y) => {
                    return new Gdk.ContentProvider.for_value (provider.desktop_id);
                });
                handle.add_controller (source);

                var target = new Gtk.DropTarget (typeof (string), Gdk.DragAction.MOVE);
                target.preload = true;
                target.drop.connect ((value, x, y) => {
                    var source_id = (string) value;
                    int source_index = search_provider_index (source_id);
                    int target_index = search_provider_index (provider_row.id);
                    if (source_index < 0 || target_index < 0 || source_index == target_index)
                        return false;

                    bool after = y > row.get_height () / 2.0;
                    int insert_at = target_index + (after ? 1 : 0);
                    var source_row = search_provider_rows.steal_index ((uint) source_index);
                    search_providers_list.remove (source_row.row);
                    if (source_index < insert_at) insert_at--;
                    search_provider_rows.insert (insert_at, (owned) source_row);
                    search_providers_list.insert (search_provider_rows[insert_at].row, insert_at);

                    save_search_provider_order ();
                    return true;
                });
                row.add_controller (target);

                search_providers_list.append (row);
                search_provider_rows.add (provider_row);
            }
        }

        private int search_provider_index (string id) {
            for (uint i = 0; i < search_provider_rows.length; i++) {
                if (search_provider_rows[i].id == id) return (int) i;
            }
            return -1;
        }

        private void save_search_provider_order () {
            var ids = new GenericArray<string> ();
            for (uint i = 0; i < search_provider_rows.length; i++)
                ids.add (search_provider_rows[i].id);
            app.config.sync_search_provider_order (ids);
            app.config.save ();
        }

        private void build_grid_page () {
            var page = new Adw.PreferencesPage ();
            page.title = _("Grid");
            page.icon_name = "view-app-grid-symbolic";

            var layout_group = new Adw.PreferencesGroup ();
            layout_group.title = _("Layout");

            var launcher_row = new Adw.ComboRow ();
            launcher_row.title = _("Launcher Mode");
            launcher_row.subtitle = _("Tile grid or compact application launcher");
            launcher_row.model = new Gtk.StringList ({_("Tiles"), "Wofi"});
            launcher_row.selected = app.config.launcher_mode == LauncherMode.WOFI ? 1 : 0;
            layout_group.add (launcher_row);

            var mode_row = new Adw.ComboRow ();
            mode_row.title = _("Window Mode");
            mode_row.subtitle = _("Fullscreen overlay or floating panel");
            var mode_list = new Gtk.StringList ({_("Fullscreen"), _("Floating")});
            mode_row.model = mode_list;
            mode_row.selected = app.config.window_mode == WindowMode.FULLSCREEN ? 0 : 1;
            mode_row.notify["selected"].connect (() => {
                app.config.window_mode = mode_row.selected == 0 ? WindowMode.FULLSCREEN : WindowMode.FLOATING;
                app.config.save ();
            });
            layout_group.add (mode_row);
            tile_only_widgets.add (mode_row);

            var focus_loss_row = new Adw.SwitchRow ();
            focus_loss_row.title = _("Close When Focus Is Lost");
            focus_loss_row.subtitle = _("Hide floating launchers after switching to another window");
            focus_loss_row.active = app.config.close_on_focus_loss;
            focus_loss_row.notify["active"].connect (() => {
                app.config.close_on_focus_loss = focus_loss_row.active;
                app.config.save ();
            });
            layout_group.add (focus_loss_row);

            var monitor_row = new Adw.ComboRow ();
            monitor_row.title = _("Monitor");
            monitor_row.subtitle = _("Active Monitor uses the monitor under the pointer");
            var monitor_list = build_monitor_list ();
            monitor_row.model = monitor_list;
            monitor_row.selected = selected_monitor_index (monitor_list);
            monitor_row.notify["selected"].connect (() => {
                string? connector = null;
                if (monitor_row.selected > 0) {
                    var display = Gdk.Display.get_default ();
                    if (display != null) {
                        var monitors = display.get_monitors ();
                        uint index = monitor_row.selected - 1;
                        if (index < monitors.get_n_items ())
                            connector = ((Gdk.Monitor) monitors.get_item (index)).get_connector ();
                    }
                }
                app.config.set_output (connector);
                app.config.save ();
            });
            layout_group.add (monitor_row);

            var floating_x_row = new Adw.SpinRow.with_range (0, 100, 1);
            floating_x_row.title = _("Floating X (%)");
            floating_x_row.subtitle = _("Horizontal position as percent of screen width");
            floating_x_row.value = app.config.floating_x_percent;
            floating_x_row.notify["value"].connect (() => {
                app.config.floating_x_percent = (int) floating_x_row.value;
                app.config.save ();
            });
            layout_group.add (floating_x_row);

            var floating_y_row = new Adw.SpinRow.with_range (0, 100, 1);
            floating_y_row.title = _("Floating Y (%)");
            floating_y_row.subtitle = _("Vertical position as percent of screen height");
            floating_y_row.value = app.config.floating_y_percent;
            floating_y_row.notify["value"].connect (() => {
                app.config.floating_y_percent = (int) floating_y_row.value;
                app.config.save ();
            });
            layout_group.add (floating_y_row);

            var floating_width_row = new Adw.SpinRow.with_range (320, 4096, 10);
            floating_width_row.title = _("Floating Width");
            floating_width_row.subtitle = _("Window width in pixels");
            floating_width_row.value = app.config.floating_width;
            floating_width_row.notify["value"].connect (() => {
                app.config.floating_width = (int) floating_width_row.value;
                app.config.save ();
            });
            layout_group.add (floating_width_row);
            tile_only_widgets.add (floating_width_row);

            var floating_height_row = new Adw.SpinRow.with_range (240, 4096, 10);
            floating_height_row.title = _("Floating Height");
            floating_height_row.subtitle = _("Window height in pixels");
            floating_height_row.value = app.config.floating_height;
            floating_height_row.notify["value"].connect (() => {
                app.config.floating_height = (int) floating_height_row.value;
                app.config.save ();
            });
            layout_group.add (floating_height_row);
            tile_only_widgets.add (floating_height_row);

            var wofi_width_row = new Adw.SpinRow.with_range (320, 4096, 10);
            wofi_width_row.title = _("Launcher Width");
            wofi_width_row.subtitle = _("Compact launcher width in pixels");
            wofi_width_row.value = app.config.wofi_width;
            wofi_width_row.notify["value"].connect (() => {
                app.config.wofi_width = (int) wofi_width_row.value;
                app.config.save ();
            });
            layout_group.add (wofi_width_row);
            wofi_only_widgets.add (wofi_width_row);

            var wofi_height_row = new Adw.SpinRow.with_range (240, 4096, 10);
            wofi_height_row.title = _("Launcher Height");
            wofi_height_row.subtitle = _("Compact launcher height in pixels");
            wofi_height_row.value = app.config.wofi_height;
            wofi_height_row.notify["value"].connect (() => {
                app.config.wofi_height = (int) wofi_height_row.value;
                app.config.save ();
            });
            layout_group.add (wofi_height_row);
            wofi_only_widgets.add (wofi_height_row);

            // Max columns
            var cols_row = new Adw.SpinRow.with_range (0, 30, 2);
            cols_row.title = _("Max Columns");
            cols_row.subtitle = _("0 = automatic");
            cols_row.value = app.config.max_columns;
            cols_row.notify["value"].connect (() => {
                app.config.max_columns = (int) cols_row.value;
                app.config.save ();
            });
            layout_group.add (cols_row);
            tile_only_widgets.add (cols_row);

            // Cell size
            var cell_row = new Adw.SpinRow.with_range (0, 256, 4);
            cell_row.title = _("Cell Size");
            cell_row.subtitle = _("0 = automatic (derived from Max Rows or screen)");
            cell_row.value = app.config.cell_size;
            cell_row.notify["value"].connect (() => {
                app.config.cell_size = (int) cell_row.value;
                app.config.save ();
            });
            layout_group.add (cell_row);
            tile_only_widgets.add (cell_row);

            // Layer
            var layer_row = new Adw.ComboRow ();
            layer_row.title = _("Layer");
            layer_row.subtitle = _("Choose the layer where the launcher is displayed");
            layer_row.model = new Gtk.StringList ({
                _("Background"), _("Bottom"), _("Top"), _("Overlay")
            });
            layer_row.selected = layer_index (app.config.layer);
            layer_row.notify["selected"].connect (() => {
                app.config.layer = layer_name (layer_row.selected);
                app.config.save ();
            });
            layout_group.add (layer_row);

            launcher_row.notify["selected"].connect (() => {
                app.config.launcher_mode = launcher_row.selected == 1
                    ? LauncherMode.WOFI : LauncherMode.TILES;
                app.config.save ();
                update_launcher_mode_visibility ();
            });
            update_launcher_mode_visibility ();

            page.add (layout_group);

            var appearance_group = new Adw.PreferencesGroup ();
            appearance_group.title = _("Appearance");

            var background_opacity_row = new Adw.SpinRow.with_range (0, 100, 1);
            background_opacity_row.title = _("Background Opacity (%)");
            background_opacity_row.value = app.config.background_opacity;
            background_opacity_row.notify["value"].connect (() => {
                app.config.background_opacity = (int) background_opacity_row.value;
                app.config.save ();
            });
            appearance_group.add (background_opacity_row);

            var wallpaper_row = new Adw.ActionRow ();
            wallpaper_row.title = _("Wallpaper");
            wallpaper_row.subtitle = wallpaper_subtitle ();
            var choose_wallpaper_btn = new Gtk.Button.with_label (_("Choose…"));
            choose_wallpaper_btn.valign = Gtk.Align.CENTER;
            choose_wallpaper_btn.clicked.connect (() => {
                choose_wallpaper (wallpaper_row);
            });
            wallpaper_row.add_suffix (choose_wallpaper_btn);

            var clear_wallpaper_btn = new Gtk.Button.with_label (_("Reset"));
            clear_wallpaper_btn.valign = Gtk.Align.CENTER;
            clear_wallpaper_btn.clicked.connect (() => {
                app.config.wallpaper_path = "";
                app.config.save ();
                wallpaper_row.subtitle = wallpaper_subtitle ();
            });
            wallpaper_row.add_suffix (clear_wallpaper_btn);
            appearance_group.add (wallpaper_row);

            var fit_row = new Adw.ComboRow ();
            fit_row.title = _("Wallpaper Scale");
            fit_row.model = new Gtk.StringList ({_("Fill"), _("Contain"), _("Cover"), _("Scale Down")});
            fit_row.selected = (uint) app.config.wallpaper_fit.clamp (0, 3);
            fit_row.notify["selected"].connect (() => {
                app.config.wallpaper_fit = (int) fit_row.selected;
                app.config.save ();
            });
            appearance_group.add (fit_row);

            var opacity_row = new Adw.SpinRow.with_range (0, 100, 1);
            opacity_row.title = _("Wallpaper Opacity (%)");
            opacity_row.value = app.config.wallpaper_opacity;
            opacity_row.notify["value"].connect (() => {
                app.config.wallpaper_opacity = (int) opacity_row.value;
                app.config.save ();
            });
            appearance_group.add (opacity_row);

            var dim_row = new Adw.SpinRow.with_range (0, 100, 1);
            dim_row.title = _("Wallpaper Dim (%)");
            dim_row.value = app.config.wallpaper_dim;
            dim_row.notify["value"].connect (() => {
                app.config.wallpaper_dim = (int) dim_row.value;
                app.config.save ();
            });
            appearance_group.add (dim_row);
            page.add (appearance_group);

            // Data group
            var data_group = new Adw.PreferencesGroup ();
            data_group.title = _("Data");

            // Reset layout
            var reset_row = new Adw.ActionRow ();
            reset_row.title = _("Reset Layout");
            reset_row.subtitle = _("Regenerate folders from app categories");
            var reset_btn = new Gtk.Button.with_label (_("Reset"));
            reset_btn.valign = Gtk.Align.CENTER;
            reset_btn.add_css_class ("destructive-action");
            reset_btn.clicked.connect (() => {
                var config_path = Path.build_filename (
                    Environment.get_user_config_dir (), "ximper-shell", "launcher", "config.json"
                );
                FileUtils.remove (config_path);
                app.config.load ();
            });
            reset_row.add_suffix (reset_btn);
            data_group.add (reset_row);

            page.add (data_group);

            add (page);
        }

        private void update_launcher_mode_visibility () {
            bool wofi = app.config.launcher_mode == LauncherMode.WOFI;
            for (uint i = 0; i < tile_only_widgets.length; i++) {
                tile_only_widgets[i].visible = !wofi;
            }
            for (uint i = 0; i < wofi_only_widgets.length; i++) {
                wofi_only_widgets[i].visible = wofi;
            }
        }

        private string wallpaper_subtitle () {
            return app.config.wallpaper_path.length > 0
                ? app.config.wallpaper_path
                : _("No wallpaper selected");
        }

        private void choose_wallpaper (Adw.ActionRow wallpaper_row) {
            var dialog = new Gtk.FileDialog ();
            dialog.title = _("Choose Wallpaper");

            var image_filter = new Gtk.FileFilter ();
            image_filter.name = _("Images");
            image_filter.add_mime_type ("image/jpeg");
            image_filter.add_mime_type ("image/png");
            image_filter.add_mime_type ("image/webp");
            image_filter.add_mime_type ("image/gif");
            image_filter.add_mime_type ("image/bmp");

            var filters = new ListStore (typeof (Gtk.FileFilter));
            filters.append (image_filter);
            dialog.filters = filters;
            dialog.default_filter = image_filter;

            dialog.open.begin (this, null, (obj, result) => {
                try {
                    var file = dialog.open.end (result);
                    var path = file.get_path ();
                    if (path == null || !Path.is_absolute (path) ||
                        !FileUtils.test (path, FileTest.IS_REGULAR)) return;

                    app.config.wallpaper_path = path;
                    app.config.save ();
                    wallpaper_row.subtitle = wallpaper_subtitle ();
                } catch (Error e) {
                    if (e.code != Gtk.DialogError.DISMISSED) {
                        warning ("Failed to choose wallpaper: %s", e.message);
                    }
                }
            });
        }

        private uint selected_monitor_index (Gtk.StringList list) {
            if (app.config.output.length == 0) return 0;
            var display = Gdk.Display.get_default ();
            if (display == null) return 0;
            var monitors = display.get_monitors ();
            for (uint i = 0; i < monitors.get_n_items (); i++) {
                var connector = ((Gdk.Monitor) monitors.get_item (i)).get_connector ();
                if (connector == app.config.output[0]) return i + 1;
            }
            return 0;
        }

        private Gtk.StringList build_monitor_list () {
            var list = new Gtk.StringList (null);
            list.append (_("Active Monitor"));

            var display = Gdk.Display.get_default ();
            if (display == null) return list;

            var monitors = display.get_monitors ();
            for (uint i = 0; i < monitors.get_n_items (); i++) {
                var monitor = (Gdk.Monitor) monitors.get_item (i);
                var geometry = monitor.geometry;
                var connector = monitor.get_connector ();
                if (connector != null && connector.length > 0) {
                    list.append (
                        _("Monitor %u: %s (%dx%d)").printf (
                            i + 1,
                            connector,
                            geometry.width,
                            geometry.height
                        )
                    );
                } else {
                    list.append (_("Monitor %u (%dx%d)").printf (i + 1, geometry.width, geometry.height));
                }
            }

            return list;
        }

        private static uint layer_index (string layer) {
            switch (LayerShellHelper.normalize_layer_name (layer)) {
                case "background": return 0;
                case "bottom": return 1;
                case "top": return 2;
                default: return 3;
            }
        }

        private static string layer_name (uint index) {
            return LayerShellHelper.layer_name_from_legacy ((int) index);
        }
    }
}
