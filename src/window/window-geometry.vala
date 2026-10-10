namespace XimperShellLauncher {

    internal class WindowGeometry : Object {
        private weak Application app;
        private Gdk.Monitor? floating_monitor;

        public WindowGeometry (Application app) {
            this.app = app;
        }

        public void invalidate_monitor () {
            floating_monitor = null;
        }

        public void get_floating_geometry (
            out int x,
            out int y,
            out int width,
            out int height,
            out int margin
        ) {
            int screen_width = 1920;
            int screen_height = 1080;

            var monitor = get_floating_monitor ();
            if (monitor != null) {
                var geometry = monitor.geometry;
                screen_width = geometry.width;
                screen_height = geometry.height;
            }

            width = app.config.floating_width.clamp (320, 4096);
            height = app.config.floating_height.clamp (240, 4096);
            margin = 0;

            var position = app.config.floating_position;
            if (position != FloatingPosition.CUSTOM) {
                // Keep a usable requested size even with an excessive margin.
                int min_width = int.min (320, screen_width);
                int min_height = int.min (240, screen_height);
                int max_margin = int.max (0, int.min ((screen_width - min_width) / 2,
                                                     (screen_height - min_height) / 2));
                margin = int.min (app.config.floating_margin.clamp (0, 512), max_margin);
                width = int.min (width, int.max (1, screen_width - 2 * margin));
                height = int.min (height, int.max (1, screen_height - 2 * margin));
                int horizontal = position.horizontal_alignment ();
                int vertical = position.vertical_alignment ();
                x = horizontal < 0 ? margin : (horizontal > 0 ? screen_width - width - margin : (screen_width - width) / 2);
                y = vertical < 0 ? margin : (vertical > 0 ? screen_height - height - margin : (screen_height - height) / 2);
                return;
            }

            int available_width = screen_width - width;
            int available_height = screen_height - height;
            if (available_width < 0) available_width = 0;
            if (available_height < 0) available_height = 0;

            x = available_width * app.config.floating_x_percent.clamp (0, 100) / 100;
            y = available_height * app.config.floating_y_percent.clamp (0, 100) / 100;
        }

        public Gdk.Monitor? get_floating_monitor () {
            if (floating_monitor != null) return floating_monitor;

            if (app.config.output.length > 0) {
                floating_monitor = get_monitor_by_connector (app.config.output[0]);
                if (floating_monitor != null) return floating_monitor;
            }

            floating_monitor = get_compositor_active_monitor ();
            if (floating_monitor != null) return floating_monitor;

            return get_pointer_monitor ();
        }

        private Gdk.Monitor? get_pointer_monitor () {
            var display = Gdk.Display.get_default ();
            if (display == null) return null;

            var seat = display.get_default_seat ();
            if (seat == null) return null;

            var pointer = seat.get_pointer ();
            if (pointer == null) return null;

            double x;
            double y;
            var surface = pointer.get_surface_at_position (out x, out y);
            if (surface == null) return null;

            return display.get_monitor_at_surface (surface);
        }

        private Gdk.Monitor? get_compositor_active_monitor () {
            var connector = app.compositor_helper.get_active_monitor_connector ();
            if (connector == null || connector.length == 0) return null;
            return get_monitor_by_connector (connector);
        }

        private Gdk.Monitor? get_monitor_by_connector (string connector) {
            var display = Gdk.Display.get_default ();
            if (display == null) return null;

            var monitors = display.get_monitors ();
            for (uint i = 0; i < monitors.get_n_items (); i++) {
                var monitor = (Gdk.Monitor) monitors.get_item (i);
                var current_connector = monitor.get_connector ();
                if (current_connector == connector) return monitor;
            }

            return null;
        }
    }
}
