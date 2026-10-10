namespace XimperShellLauncher {
    // Fixed-size cross axis, bounded scrollable sections on the other axis.
    // Measuring a long button collection must never enlarge the layer window.
    public class ActionSidebar : Gtk.Widget {
        private SidebarConfig config = new SidebarConfig ();
        private Gtk.Box panel_background;
        private Gtk.ScrolledWindow start_scroll;
        private Gtk.ScrolledWindow end_scroll;
        private Gtk.Box start_box;
        private Gtk.Box end_box;
        private GenericArray<Gtk.Button> buttons = new GenericArray<Gtk.Button> ();
        private GenericArray<Gtk.Image> images = new GenericArray<Gtk.Image> ();
        private GenericArray<Gtk.Button> menu_buttons = new GenericArray<Gtk.Button> ();
        private GenericArray<Gtk.Image> menu_images = new GenericArray<Gtk.Image> ();
        private SidebarItem? last_item;
        private int64 last_activation;
        private GenericArray<SidebarItem> menu_path = new GenericArray<SidebarItem> ();
        private Gtk.Popover popup;
        private SidebarItem? confirmation;
        private weak Gtk.Button? anchor;
        private SidebarActionRunner runner = new SidebarActionRunner ();
        private Cancellable? pending;
        private uint generation;
        private uint layout_generation;
        private bool busy;
        private int menu_index;

        public signal void close_requested ();
        public signal void error (string message);
        public bool horizontal { get { return config.horizontal; } }
        public bool has_popup { get { return popup.visible; } }
        public bool contains_focus {
            get {
                var root = get_root () as Gtk.Window;
                var focus = root != null ? root.get_focus () : null;
                return focus != null && (focus == this || focus.is_ancestor (this));
            }
        }

        public ActionSidebar () {
            set_layout_manager (null);
            add_css_class ("action-sidebar");
            panel_background = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            panel_background.add_css_class ("action-sidebar-background");
            panel_background.can_target = false;
            panel_background.set_parent (this);
            start_scroll = new Gtk.ScrolledWindow ();
            end_scroll = new Gtk.ScrolledWindow ();
            start_scroll.set_parent (this);
            end_scroll.set_parent (this);
            connect_scroll (this, start_scroll);
            connect_scroll (this, end_scroll);
            popup = new Gtk.Popover ();
            popup.add_css_class ("sidebar-popover");
            popup.set_parent (this);
            connect_lifecycle (this);
            configure (new SidebarConfig ());
        }

        private static void connect_scroll (ActionSidebar panel, Gtk.ScrolledWindow scroll) {
            var controller = new Gtk.EventControllerScroll (Gtk.EventControllerScrollFlags.BOTH_AXES);
            controller.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            var panel_ref = new SidebarWeakReference (panel);
            var scroll_ref = new SidebarWeakReference (scroll);
            var controller_ref = new SidebarWeakReference (controller);
            controller.scroll.connect ((dx, dy) => {
                var owner = panel_ref.get () as ActionSidebar;
                var target = scroll_ref.get () as Gtk.ScrolledWindow;
                var input = controller_ref.get () as Gtk.EventControllerScroll;
                if (owner == null || target == null || input == null || !owner.horizontal || dx != 0 || dy == 0) return false;
                double step = input.get_unit () == Gdk.ScrollUnit.WHEEL ? 32 : 1;
                target.hadjustment.value += dy * step;
                return true;
            });
            scroll.add_controller (controller);
        }

        private static void connect_lifecycle (ActionSidebar panel) {
            var reference = new SidebarWeakReference (panel);
            panel.popup.closed.connect (() => {
                var owner = reference.get () as ActionSidebar;
                if (owner == null) return;
                owner.confirmation = null;
                owner.clear_menu_images ();
                owner.menu_path = new GenericArray<SidebarItem> ();
                owner.menu_buttons = new GenericArray<Gtk.Button> ();
                if (owner.anchor != null && owner.get_mapped ()) owner.anchor.grab_focus ();
            });
            panel.runner.failed.connect ((label, detail) => {
                var owner = reference.get () as ActionSidebar;
                if (owner != null && owner.get_mapped ()) owner.error ("%s: %s".printf (label, detail));
            });
            panel.unmap.connect (() => {
                var owner = reference.get () as ActionSidebar;
                if (owner != null) owner.cancel_pending ();
            });
        }

        private static void connect_action (ActionSidebar panel, Gtk.Button button, SidebarItem item, uint token) {
            var owner_ref = new SidebarWeakReference (panel);
            var button_ref = new SidebarWeakReference (button);
            button.clicked.connect (() => {
                var owner = owner_ref.get () as ActionSidebar;
                var source = button_ref.get () as Gtk.Button;
                if (owner != null && source != null && owner.layout_generation == token) owner.activate_item (item, source);
            });
        }

        private static void connect_back (ActionSidebar panel, Gtk.Button button) {
            var reference = new SidebarWeakReference (panel);
            button.clicked.connect (() => {
                var owner = reference.get () as ActionSidebar;
                if (owner != null) owner.back ();
            });
        }

        private static void connect_confirmation (ActionSidebar panel, Gtk.Button cancel, Gtk.Button run, SidebarItem selected, uint token) {
            var reference = new SidebarWeakReference (panel);
            cancel.clicked.connect (() => {
                var owner = reference.get () as ActionSidebar;
                if (owner != null && owner.generation == token) owner.back ();
            });
            run.clicked.connect (() => {
                var owner = reference.get () as ActionSidebar;
                if (owner == null || owner.generation != token || owner.confirmation != selected) return;
                owner.confirmation = null;
                owner.execute (selected);
            });
        }

        private static void launch_request (ActionSidebar panel, SidebarItem item, Cancellable cancel, uint token) {
            var reference = new SidebarWeakReference (panel);
            panel.runner.launch.begin (item, cancel, (source, result) => {
                bool accepted = ((SidebarActionRunner) source).launch.end (result);
                var owner = reference.get () as ActionSidebar;
                if (owner == null || owner.generation != token) return;
                owner.busy = false;
                owner.pending = null;
                if (accepted && item.close_launcher) owner.close_requested ();
            });
        }

        protected override void dispose () {
            cancel_pending ();
            clear_images ();
            clear_menu_images ();
            if (popup != null && popup.get_parent () != null) popup.unparent ();
            if (panel_background != null && panel_background.get_parent () != null) panel_background.unparent ();
            if (start_scroll != null && start_scroll.get_parent () != null) start_scroll.unparent ();
            if (end_scroll != null && end_scroll.get_parent () != null) end_scroll.unparent ();
            base.dispose ();
        }

        private void clear_images () {
            for (uint i = 0; i < images.length; i++) IconLoader.cancel_and_clear (images[i]);
            images = new GenericArray<Gtk.Image> ();
        }

        private void clear_menu_images () {
            for (uint i = 0; i < menu_images.length; i++) IconLoader.cancel_and_clear (menu_images[i]);
            menu_images = new GenericArray<Gtk.Image> ();
        }

        public void cancel_pending () {
            generation++;
            if (pending != null) pending.cancel ();
            pending = null;
            busy = false;
            confirmation = null;
            menu_path = new GenericArray<SidebarItem> ();
            menu_buttons = new GenericArray<Gtk.Button> ();
            popup.popdown ();
        }

        public void configure (SidebarConfig settings) {
            cancel_pending ();
            layout_generation++;
            clear_images ();
            buttons = new GenericArray<Gtk.Button> ();
            anchor = null;
            last_item = null;
            config = settings;
            panel_background.opacity = config.background_opacity / 100.0;
            panel_background.visible = config.background_opacity > 0;
            var axis = horizontal ? Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL;
            start_box = new Gtk.Box (axis, config.spacing);
            end_box = new Gtk.Box (axis, config.spacing);
            start_scroll.set_child (start_box);
            end_scroll.set_child (end_box);
            foreach (var scroll in new Gtk.ScrolledWindow[] { start_scroll, end_scroll }) {
                scroll.hscrollbar_policy = horizontal ? Gtk.PolicyType.EXTERNAL : Gtk.PolicyType.NEVER;
                scroll.vscrollbar_policy = horizontal ? Gtk.PolicyType.NEVER : Gtk.PolicyType.EXTERNAL;
            }
            build_section (start_box, config.start_items);
            build_section (end_box, config.end_items);
            start_scroll.visible = config.start_items.length > 0;
            end_scroll.visible = config.end_items.length > 0;
            visible = config.enabled;
            if (horizontal) add_css_class ("horizontal"); else remove_css_class ("horizontal");
            queue_resize ();
        }

        private void build_section (Gtk.Box box, GenericArray<SidebarItem> entries) {
            for (uint i = 0; i < entries.length; i++) {
                var item = entries[i];
                if (item.kind == SidebarItemKind.SEPARATOR) {
                    box.append (new Gtk.Separator (horizontal ? Gtk.Orientation.VERTICAL : Gtk.Orientation.HORIZONTAL));
                    continue;
                }
                var button = make_button (item, false);
                buttons.add (button);
                box.append (button);
            }
        }

        private Gtk.Button make_button (SidebarItem item, bool in_menu) {
            var button = new Gtk.Button ();
            button.add_css_class (in_menu ? "popover-item" : "sidebar-button");
            button.sensitive = item.valid;
            string label = item.display_label ();
            button.tooltip_text = item.valid ? label : _("Invalid action configuration");
            var content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var image = new Gtk.Image ();
            int available = int.max (8, config.thickness - 2 * effective_padding () - 16);
            int size = int.max (8, int.min (config.icon_size, int.min (config.button_height - 16, available)));
            IconLoader.set_image_icon (image, item.get_icon (), size, false);
            if (in_menu) menu_images.add (image); else images.add (image);
            content.append (image);
            if (in_menu || config.show_labels) {
                var caption = new Gtk.Label (label);
                caption.xalign = 0;
                caption.ellipsize = Pango.EllipsizeMode.END;
                caption.max_width_chars = 24;
                caption.hexpand = true;
                content.append (caption);
            } else content.halign = Gtk.Align.CENTER;
            button.set_child (content);
            if (!in_menu) button.set_size_request (horizontal && !config.show_labels ? config.button_height : -1,
                config.button_height);
            connect_action (this, button, item, layout_generation);
            return button;
        }

        private void activate_item (SidebarItem item, Gtk.Button source) {
            if (busy || !item.valid || !get_mapped ()) return;
            if (!has_popup) {
                confirmation = null;
                menu_path = new GenericArray<SidebarItem> ();
                anchor = source;
                Graphene.Rect bounds;
                if (source.compute_bounds (this, out bounds)) {
                    Gdk.Rectangle rect = { (int) bounds.origin.x, (int) bounds.origin.y,
                        (int) bounds.size.width, (int) bounds.size.height };
                    popup.set_pointing_to (rect);
                }
                popup.position = horizontal ? Gtk.PositionType.BOTTOM :
                    (config.position == SidebarPosition.RIGHT ? Gtk.PositionType.LEFT : Gtk.PositionType.RIGHT);
            }
            if (item.kind == SidebarItemKind.MENU) {
                menu_path.add (item);
                show_menu ();
            } else if (item.confirm) {
                confirmation = item;
                show_confirmation ();
            } else execute (item);
        }

        private Gtk.Box new_popup_content (string title) {
            menu_buttons = new GenericArray<Gtk.Button> ();
            clear_menu_images ();
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            var heading = new Gtk.Label (title);
            heading.ellipsize = Pango.EllipsizeMode.END;
            heading.max_width_chars = 28;
            heading.add_css_class ("heading");
            box.append (heading);
            var scroll = new Gtk.ScrolledWindow ();
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            scroll.propagate_natural_height = true;
            scroll.propagate_natural_width = true;
            scroll.max_content_height = 360;
            scroll.max_content_width = 320;
            scroll.set_child (box);
            popup.set_child (scroll);
            return box;
        }

        private void add_popup_button (Gtk.Box box, Gtk.Button button) {
            box.append (button);
            if (button.sensitive) menu_buttons.add (button);
        }

        private void focus_popup () {
            menu_index = 0;
            popup.popup ();
            if (menu_buttons.length > 0) menu_buttons[0].grab_focus ();
        }

        private void show_menu () {
            if (menu_path.length == 0) return;
            var current = menu_path[menu_path.length - 1];
            var box = new_popup_content (current.display_label ());
            if (menu_path.length > 1) {
                var back = new Gtk.Button.with_label (_("Back"));
                connect_back (this, back);
                add_popup_button (box, back);
            }
            for (uint i = 0; i < current.items.length; i++) {
                var item = current.items[i];
                if (item.kind == SidebarItemKind.SEPARATOR) box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
                else add_popup_button (box, make_button (item, true));
            }
            focus_popup ();
        }

        private void show_confirmation () {
            if (confirmation == null) return;
            var box = new_popup_content (confirmation.display_label ());
            var prompt = new Gtk.Label (_("Run this action?"));
            box.append (prompt);
            var cancel = new Gtk.Button.with_label (_("Cancel"));
            var run = new Gtk.Button.with_label (_("Run"));
            run.add_css_class ("destructive-action");
            connect_confirmation (this, cancel, run, confirmation, generation);
            add_popup_button (box, cancel);
            add_popup_button (box, run);
            focus_popup ();
        }

        private void execute (SidebarItem item) {
            if (busy || (last_item == item && get_monotonic_time () - last_activation < 250000)) return;
            last_item = item;
            last_activation = get_monotonic_time ();
            busy = true;
            popup.popdown ();
            pending = new Cancellable ();
            launch_request (this, item, pending, generation);
        }

        public bool back () {
            if (!has_popup) return false;
            if (confirmation != null) {
                confirmation = null;
                if (menu_path.length > 0) show_menu (); else popup.popdown ();
            } else if (menu_path.length > 1) {
                menu_path.remove_index (menu_path.length - 1);
                show_menu ();
            } else popup.popdown ();
            return true;
        }

        public bool focus_first () {
            for (uint i = 0; i < buttons.length; i++)
                if (buttons[i].sensitive && buttons[i].grab_focus ()) return true;
            return false;
        }

        public bool navigate (int dx, int dy) {
            int step = has_popup ? dy : (horizontal ? dx : dy);
            if (step == 0) return false;
            var entries = has_popup ? menu_buttons : buttons;
            if (entries.length == 0) return true;
            var root = get_root () as Gtk.Window;
            var focused = root != null ? root.get_focus () : null;
            int index = has_popup ? menu_index : -1;
            for (uint i = 0; i < entries.length; i++) if (entries[i] == focused) index = (int) i;
            for (uint i = 0; i < entries.length; i++) {
                index = (index + step + (int) entries.length) % (int) entries.length;
                if (entries[index].sensitive) {
                    entries[index].grab_focus ();
                    if (has_popup) menu_index = index;
                    break;
                }
            }
            return true;
        }

        public void activate_focused () {
            var root = get_root () as Gtk.Window;
            var button = root != null ? root.get_focus () as Gtk.Button : null;
            if (has_popup) {
                if (button != null) {
                    for (uint i = 0; i < menu_buttons.length; i++)
                        if (menu_buttons[i] == button) { button.activate (); return; }
                }
                if (menu_buttons.length > 0) menu_buttons[menu_index].activate ();
            } else if (button != null && button.is_ancestor (this)) button.activate ();
        }

        public bool handle_key (uint keyval) {
            if (!has_popup && !contains_focus) return false;
            if (keyval == Gdk.Key.Escape) return back ();
            if (keyval == Gdk.Key.Up) return navigate (0, -1);
            if (keyval == Gdk.Key.Down) return navigate (0, 1);
            if (keyval == Gdk.Key.Left) return navigate (-1, 0);
            if (keyval == Gdk.Key.Right) return navigate (1, 0);
            if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter || keyval == Gdk.Key.space) {
                activate_focused ();
                return true;
            }
            return false;
        }

        private int effective_padding () { return int.min (config.padding, int.max (0, (config.thickness - 24) / 2)); }

        protected override void measure (Gtk.Orientation orientation, int for_size,
                out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            minimum_baseline = natural_baseline = -1;
            bool along = orientation == (horizontal ? Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL);
            if (along) { minimum = natural = 0; return; }
            int a_min, a_nat, b_min, b_nat;
            start_box.measure (orientation, -1, out a_min, out a_nat, null, null);
            end_box.measure (orientation, -1, out b_min, out b_nat, null, null);
            minimum = natural = int.max (config.thickness, int.max (a_min, b_min) + 2 * effective_padding ());
        }

        private void allocate_section (Gtk.ScrolledWindow scroll, int width, int height, int x, int y) {
            if (!scroll.visible) return;
            scroll.measure (Gtk.Orientation.HORIZONTAL, -1, null, null, null, null);
            scroll.measure (Gtk.Orientation.VERTICAL, width, null, null, null, null);
            var transform = new Gsk.Transform ().translate (Graphene.Point () { x = x, y = y });
            scroll.allocate (int.max (1, width), int.max (1, height), -1, transform);
        }

        protected override void size_allocate (int width, int height, int baseline) {
            if (panel_background.visible) {
                panel_background.measure (Gtk.Orientation.HORIZONTAL, -1, null, null, null, null);
                panel_background.measure (Gtk.Orientation.VERTICAL, width, null, null, null, null);
                panel_background.allocate (width, height, -1, null);
            }
            int pad = effective_padding ();
            int cross = int.max (1, (horizontal ? height : width) - 2 * pad);
            int available = int.max (1, (horizontal ? width : height) - 2 * pad);
            var axis = horizontal ? Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL;
            int a_min, a_nat, b_min, b_nat;
            start_box.measure (axis, cross, out a_min, out a_nat, null, null);
            end_box.measure (axis, cross, out b_min, out b_nat, null, null);
            double total = (double) a_nat + b_nat;
            int a = a_nat, b = b_nat;
            if (total > available) {
                a = (int) (available * ((double) a_nat / total));
                b = available - a;
            }
            allocate_section (start_scroll, horizontal ? a : cross, horizontal ? cross : a, pad, pad);
            allocate_section (end_scroll, horizontal ? b : cross, horizontal ? cross : b,
                horizontal ? pad + available - b : pad, horizontal ? pad : pad + available - b);
            if (popup.visible) popup.present ();
        }
    }
}
