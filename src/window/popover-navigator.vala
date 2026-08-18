namespace XimperShellLauncher {

    internal class PopoverNavigator : Object {
        private int focus_index = -1;
        private GenericArray<Gtk.Button>? buttons;

        public bool active { get { return buttons != null; } }

        public void attach (Gtk.Popover popover) {
            buttons = new GenericArray<Gtk.Button> ();
            focus_index = 0;

            var menu_box = popover.get_child ();
            if (menu_box == null) return;

            var child = menu_box.get_first_child ();
            while (child != null) {
                if (child is Gtk.Button && child.sensitive) {
                    buttons.add ((Gtk.Button) child);
                }
                child = child.get_next_sibling ();
            }

            update_highlight ();

            popover.closed.connect (() => {
                reset ();
            });
        }

        public void reset () {
            if (buttons != null) clear_highlight ();
            buttons = null;
            focus_index = -1;
        }

        public void navigate (int dy) {
            if (buttons == null || buttons.length == 0) return;
            focus_index += dy;
            if (focus_index < 0) focus_index = (int) buttons.length - 1;
            if (focus_index >= (int) buttons.length) focus_index = 0;
            update_highlight ();
        }

        public void activate_focused () {
            if (buttons == null || focus_index < 0) return;
            if (focus_index >= (int) buttons.length) return;

            var btn = buttons[focus_index];

            // Clean up state BEFORE activation — activation may trigger rebuild.
            reset ();
            btn.activate ();
        }

        private void update_highlight () {
            if (buttons == null) return;
            for (uint i = 0; i < buttons.length; i++) {
                if ((int) i == focus_index) {
                    buttons[i].add_css_class ("popover-item-focused");
                } else {
                    buttons[i].remove_css_class ("popover-item-focused");
                }
            }
        }

        private void clear_highlight () {
            if (buttons == null) return;
            for (uint i = 0; i < buttons.length; i++) {
                buttons[i].remove_css_class ("popover-item-focused");
            }
        }
    }
}
