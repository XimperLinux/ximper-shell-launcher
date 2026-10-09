namespace XimperShellLauncher {

    public class Tile : Gtk.Box {

        public AppEntry app_entry { get; private set; }
        public TileSize tile_size { get; set; }
        public Gtk.Widget? content_widget { get; set; default = null; }

        private Gtk.Box content_box;
        private Gtk.Image icon_image;
        private Gtk.Label? name_label;
        private bool menu_visible = false;
        private int loaded_icon_size = 0;
        private bool cleaned_up = false;
        private GenericArray<Gtk.EventController> owned_controllers =
            new GenericArray<Gtk.EventController> ();

        public signal void tile_activated (AppEntry entry);
        public signal void size_change_requested (Tile tile, TileSize new_size);
        public signal void remove_requested (Tile tile);
        public signal void pin_to_dock_requested (Tile tile);
        public signal void unpin_from_dock_requested (Tile tile);
        public signal void create_folder_requested (Tile tile);

        public Tile (AppEntry entry, TileSize size, int cell_px = 64) {
            this.app_entry = entry;
            this.tile_size = size;

            add_css_class ("tile");
            focusable = true;

            build_ui ();
            apply_size (size, cell_px);
            setup_click ();
            setup_drag ();
        }

        private void build_ui () {
            content_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            content_box.halign = Gtk.Align.CENTER;
            content_box.valign = Gtk.Align.CENTER;
            content_box.hexpand = true;
            content_box.vexpand = true;

            icon_image = new Gtk.Image ();
            icon_image.add_css_class ("tile-icon");
            content_box.append (icon_image);

            name_label = new Gtk.Label (app_entry.name);
            name_label.add_css_class ("tile-name");
            name_label.ellipsize = Pango.EllipsizeMode.END;
            name_label.max_width_chars = 12;
            content_box.append (name_label);

            append (content_box);
            tooltip_text = app_entry.name;
        }

        private void setup_click () {
            var gesture = new Gtk.GestureClick ();
            gesture.button = Gdk.BUTTON_PRIMARY;
            gesture.released.connect ((n, x, y) => {
                if (menu_visible) {
                    hide_context_menu ();
                    return;
                }
                tile_activated (app_entry);
            });
            add_owned_controller (gesture);

            // Right click
            var rmb = new Gtk.GestureClick ();
            rmb.button = Gdk.BUTTON_SECONDARY;
            rmb.pressed.connect ((n, x, y) => {
                rmb.set_state (Gtk.EventSequenceState.CLAIMED);
                if (menu_visible) {
                    hide_context_menu ();
                } else {
                    show_context_menu ();
                }
                unset_state_flags (Gtk.StateFlags.ACTIVE);
            });
            add_owned_controller (rmb);

            // Long press for touchscreen
            var long_press = new Gtk.GestureLongPress ();
            long_press.pressed.connect ((x, y) => {
                long_press.set_state (Gtk.EventSequenceState.CLAIMED);
                show_context_menu ();
                unset_state_flags (Gtk.StateFlags.ACTIVE);
            });
            add_owned_controller (long_press);
        }

        private Gtk.Button make_menu_item (string label) {
            var btn = new Gtk.Button ();
            btn.add_css_class ("flat");
            btn.label = label;
            return btn;
        }

        public Gtk.Popover? active_popover { get; private set; }

        public void open_context_menu () {
            show_context_menu ();
        }

        private void show_context_menu () {
            if (menu_visible) return;

            var popover = new Gtk.Popover ();
            popover.set_parent (this);
            popover.has_arrow = true;
            popover.autohide = true;
            popover.add_css_class ("menu");

            var menu_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            // Desktop actions from .desktop file
            var desktop_actions = app_entry.list_actions ();
            if (desktop_actions.length > 0) {
                foreach (var action_id in desktop_actions) {
                    var action_name = app_entry.get_action_name (action_id);
                    var btn = make_menu_item (action_name);
                    var aid = action_id;
                    btn.clicked.connect (() => {
                        popover.popdown ();
                        app_entry.launch_action (aid);
                    });
                    menu_box.append (btn);
                }
                menu_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            }

            // Size options
            var small_btn = make_menu_item (_("Small"));
            small_btn.clicked.connect (() => {
                popover.popdown ();
                size_change_requested (this, TileSize.SMALL);
            });
            menu_box.append (small_btn);

            var medium_btn = make_menu_item (_("Medium"));
            medium_btn.clicked.connect (() => {
                popover.popdown ();
                size_change_requested (this, TileSize.MEDIUM);
            });
            menu_box.append (medium_btn);

            var large_btn = make_menu_item (_("Large"));
            large_btn.clicked.connect (() => {
                popover.popdown ();
                size_change_requested (this, TileSize.LARGE);
            });
            menu_box.append (large_btn);

            menu_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            // Pin/Unpin to Dock — check via D-Bus
            var grid_app = (Application) ((Gtk.Window) get_root ()).application;
            if (grid_app.is_dock_running ()) {
                bool pinned = grid_app.is_pinned_in_dock (app_entry.desktop_id);
                if (pinned) {
                    var unpin_btn = make_menu_item (_("Unpin from Dock"));
                    unpin_btn.clicked.connect (() => {
                        popover.popdown ();
                        unpin_from_dock_requested (this);
                    });
                    menu_box.append (unpin_btn);
                } else {
                    var pin_btn = make_menu_item (_("Pin to Dock"));
                    pin_btn.clicked.connect (() => {
                        popover.popdown ();
                        pin_to_dock_requested (this);
                    });
                    menu_box.append (pin_btn);
                }
            }

            var folder_btn = make_menu_item (_("Create Folder"));
            folder_btn.clicked.connect (() => {
                popover.popdown ();
                create_folder_requested (this);
            });
            menu_box.append (folder_btn);

            menu_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            var remove_btn = make_menu_item (_("Remove"));
            remove_btn.clicked.connect (() => {
                popover.popdown ();
                remove_requested (this);
            });
            menu_box.append (remove_btn);

            popover.set_child (menu_box);
            popover.popup ();
            menu_visible = true;
            active_popover = popover;

            var first_btn = menu_box.get_first_child ();
            if (first_btn != null && first_btn is Gtk.Button) {
                first_btn.grab_focus ();
            }

            popover.closed.connect (() => {
                menu_visible = false;
                active_popover = null;
                popover.unparent ();
            });
        }

        private void hide_context_menu () {
            menu_visible = false;
        }

        public void apply_size (TileSize size, int cell_px = 80) {
            this.tile_size = size;

            remove_css_class ("tile-small");
            remove_css_class ("tile-medium");
            remove_css_class ("tile-large");

            int icon_sz = (int) (cell_px * 0.5);
            int gap = 6; // matches SPACING in TileGroup

            switch (size) {
                case TileSize.SMALL:
                    add_css_class ("tile-small");
                    set_size_request (cell_px, cell_px);
                    icon_image.pixel_size = icon_sz;
                    name_label.visible = false;
                    break;

                case TileSize.MEDIUM:
                    add_css_class ("tile-medium");
                    set_size_request (cell_px * 2 + gap, cell_px);
                    icon_image.pixel_size = icon_sz;
                    name_label.visible = true;
                    content_box.orientation = Gtk.Orientation.HORIZONTAL;
                    content_box.spacing = 8;
                    break;

                case TileSize.LARGE:
                    add_css_class ("tile-large");
                    set_size_request (cell_px * 2 + gap, cell_px * 2 + gap);
                    icon_image.pixel_size = (int) (cell_px * 0.7);
                    name_label.visible = true;
                    content_box.orientation = Gtk.Orientation.VERTICAL;
                    content_box.spacing = 8;
                    break;

                default:
                    break;
            }

            int actual_size = icon_image.pixel_size;
            if (actual_size != loaded_icon_size) {
                loaded_icon_size = actual_size;
                IconLoader.set_image_icon (icon_image, app_entry.icon,
                    actual_size, true);
            }
        }

        private void add_owned_controller (Gtk.EventController controller) {
            owned_controllers.add (controller);
            add_controller (controller);
        }

        public void cleanup () {
            if (cleaned_up) return;
            cleaned_up = true;
            IconLoader.cancel_and_clear (icon_image);
            for (uint i = 0; i < owned_controllers.length; i++) {
                remove_controller (owned_controllers[i]);
            }
            owned_controllers = new GenericArray<Gtk.EventController> ();
            if (active_popover != null) {
                active_popover.unparent ();
                active_popover = null;
            }
        }

        protected override void dispose () {
            cleanup ();
            base.dispose ();
        }

        public bool board_managed_dnd { get; set; default = false; }
        public signal void drag_state_changed (bool active);

        private void setup_drag () {
            var source = new Gtk.DragSource ();
            source.set_actions (Gdk.DragAction.MOVE);

            Gdk.Paintable? frozen_icon = null;
            source.prepare.connect ((x, y) => {
                frozen_icon = new Gtk.WidgetPaintable (this).get_current_image ();
                var id = app_entry.desktop_id ?? "";
                return new Gdk.ContentProvider.for_value (id);
            });

            source.drag_begin.connect ((drag) => {
                if (frozen_icon != null)
                    source.set_icon (frozen_icon, get_width () / 2, get_height () / 2);
                if (!board_managed_dnd) add_css_class ("tile-dragging");
                drag_state_changed (true);
            });

            source.drag_end.connect ((drag, delete_data) => {
                remove_css_class ("tile-dragging");
                drag_state_changed (false);
            });

            add_owned_controller (source);

            // Drop target — accepts string (desktop_id)
            var target = new Gtk.DropTarget (typeof (string), Gdk.DragAction.MOVE);
            target.accept.connect (() => !board_managed_dnd);
            target.drop.connect ((val, x, y) => {
                var source_id = (string) val;
                if (source_id == null || source_id == app_entry.desktop_id) return false;
                drop_received (source_id, app_entry.desktop_id);
                return true;
            });
            add_owned_controller (target);
        }

        public signal void drop_received (string source_id, string target_id);
    }
}
