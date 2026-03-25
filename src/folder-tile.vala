namespace XimperShellTileMenu {

    public class FolderTile : Gtk.Box {

        public string folder_name { get; private set; }
        public GenericArray<string> folder_items;
        public string folder_id { get; private set; }

        private weak Application app;

        public signal void folder_clicked (FolderTile folder);
        public signal void drop_received_on_folder (string source_id, string folder_desktop_id);

        public FolderTile (Application app, string name, GenericArray<string> items, int cell_px) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.app = app;
            this.folder_name = name;
            this.folder_items = items;
            this.folder_id = "folder:" + name;

            add_css_class ("tile");
            add_css_class ("tile-folder");
            focusable = true;
            set_size_request (cell_px, cell_px);
            halign = Gtk.Align.CENTER;
            valign = Gtk.Align.CENTER;

            // 2x2 mini icon grid
            var icon_grid = new Gtk.Grid ();
            icon_grid.column_spacing = 4;
            icon_grid.row_spacing = 4;
            icon_grid.halign = Gtk.Align.CENTER;
            icon_grid.valign = Gtk.Align.CENTER;
            icon_grid.vexpand = true;

            int mini_size = int.max (16, (int) (cell_px * 0.28));
            for (int i = 0; i < 4 && i < (int) items.length; i++) {
                var entry = app.app_provider.find_by_desktop_id (items[i]);
                var img = new Gtk.Image ();
                if (entry != null && entry.icon != null) {
                    img.gicon = entry.icon;
                } else {
                    img.icon_name = "application-x-executable";
                }
                img.pixel_size = mini_size;
                icon_grid.attach (img, i % 2, i / 2, 1, 1);
            }

            append (icon_grid);

            var label = new Gtk.Label (name);
            label.add_css_class ("tile-name");
            label.ellipsize = Pango.EllipsizeMode.END;
            label.max_width_chars = 10;
            label.margin_bottom = 6;
            append (label);

            tooltip_text = name + " (" + items.length.to_string () + ")";

            // Click to open
            var gesture = new Gtk.GestureClick ();
            gesture.button = Gdk.BUTTON_PRIMARY;
            gesture.released.connect ((n, x, y) => {
                folder_clicked (this);
            });
            add_controller (gesture);

            // Right click — ungroup
            var rmb = new Gtk.GestureClick ();
            rmb.button = Gdk.BUTTON_SECONDARY;
            rmb.pressed.connect ((n, x, y) => {
                rmb.set_state (Gtk.EventSequenceState.CLAIMED);
                show_folder_menu ();
                unset_state_flags (Gtk.StateFlags.ACTIVE);
            });
            add_controller (rmb);

            // DragSource — sends folder_id as string
            var source = new Gtk.DragSource ();
            source.set_actions (Gdk.DragAction.MOVE);
            source.prepare.connect ((x, y) => {
                return new Gdk.ContentProvider.for_value (folder_id ?? "");
            });
            source.drag_begin.connect ((drag) => {
                var paintable = new Gtk.WidgetPaintable (this);
                source.set_icon (paintable, get_width () / 2, get_height () / 2);
                add_css_class ("tile-dragging");
            });
            source.drag_end.connect ((drag, del) => {
                remove_css_class ("tile-dragging");
            });
            add_controller (source);

            // DropTarget — accepts string (desktop_id or folder_id)
            var target = new Gtk.DropTarget (typeof (string), Gdk.DragAction.MOVE);
            target.drop.connect ((val, x, y) => {
                var source_id = (string) val;
                if (source_id == null || source_id == folder_id) return false;
                drop_received_on_folder (source_id, folder_id);
                return true;
            });
            add_controller (target);
        }

        public signal void ungroup_requested (FolderTile folder);
        public signal void rename_requested (FolderTile folder, string new_name);

        private void show_folder_menu () {
            var popover = new Gtk.Popover ();
            popover.set_parent (this);
            popover.has_arrow = true;
            popover.autohide = true;
            popover.add_css_class ("menu");

            var menu_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);

            var rename_btn = new Gtk.Button ();
            rename_btn.add_css_class ("flat");
            rename_btn.label = "Rename";
            rename_btn.clicked.connect (() => {
                popover.popdown ();
                show_rename_dialog ();
            });
            menu_box.append (rename_btn);

            var ungroup_btn = new Gtk.Button ();
            ungroup_btn.add_css_class ("flat");
            ungroup_btn.label = "Ungroup";
            ungroup_btn.clicked.connect (() => {
                popover.popdown ();
                ungroup_requested (this);
            });
            menu_box.append (ungroup_btn);

            popover.set_child (menu_box);
            popover.popup ();

            popover.closed.connect (() => {
                popover.unparent ();
            });
        }

        private void show_rename_dialog () {
            var popover = new Gtk.Popover ();
            popover.set_parent (this);
            popover.has_arrow = true;
            popover.autohide = true;

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            box.margin_top = 6;
            box.margin_bottom = 6;
            box.margin_start = 6;
            box.margin_end = 6;

            var entry = new Gtk.Entry ();
            entry.text = folder_name;
            entry.activates_default = true;
            box.append (entry);

            var ok_btn = new Gtk.Button.with_label ("OK");
            ok_btn.add_css_class ("suggested-action");
            box.append (ok_btn);

            ok_btn.clicked.connect (() => {
                var new_name = entry.text.strip ();
                if (new_name.length > 0 && new_name != folder_name) {
                    popover.popdown ();
                    rename_requested (this, new_name);
                }
            });

            entry.activate.connect (() => {
                ok_btn.clicked ();
            });

            popover.set_child (box);
            popover.popup ();
            entry.grab_focus ();

            popover.closed.connect (() => {
                popover.unparent ();
            });
        }
    }
}
