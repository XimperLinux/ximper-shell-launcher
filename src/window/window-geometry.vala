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
            out int height
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
