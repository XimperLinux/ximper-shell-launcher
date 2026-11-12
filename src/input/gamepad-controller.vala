namespace XimperShellLauncher {

    public class GamepadController {

        private Manette.Monitor monitor;
        private weak GridWindow window;

        private const uint16 BTN_SOUTH = 0x130; // A
        private const uint16 BTN_EAST = 0x131; // B
        private const uint16 BTN_NORTH = 0x133; // X
        private const uint16 BTN_WEST = 0x134; // Y
        private const uint16 BTN_TL = 0x136; // LB
        private const uint16 BTN_TR = 0x137; // RB
        private const uint16 BTN_START = 0x13b;
        private const uint16 BTN_MODE = 0x13c; // Xbox/Guide/PS

        private const uint16 BTN_DPAD_UP = 0x220;
        private const uint16 BTN_DPAD_DOWN = 0x221;
        private const uint16 BTN_DPAD_LEFT = 0x222;
        private const uint16 BTN_DPAD_RIGHT = 0x223;

        private const uint16 ABS_X = 0x00;
        private const uint16 ABS_Y = 0x01;

        private const double STICK_DEADZONE = 0.5;
        private const uint REPEAT_DELAY = 400; // ms before repeat starts
        private const uint REPEAT_INTERVAL = 120; // ms between repeats

        private int nav_dx;
        private int nav_dy;
        private uint repeat_source;
        private Manette.Device? repeat_device;

        public signal void device_connected_notify (string name);

        private static bool is_steam_running () {
            try {
                var dir = Dir.open ("/proc");
                string? name;
                while ((name = dir.read_name ()) != null) {
                    if (name[0] < '0' || name[0] > '9') continue;
                    var comm_path = "/proc/" + name + "/comm";
                    string contents;
                    if (FileUtils.get_contents (comm_path, out contents)) {
                        if (contents.strip () == "steam") return true;
                    }
                }
            } catch (Error e) {}
            return false;
        }

        public GamepadController (GridWindow window) {
            this.window = window;
            monitor = new Manette.Monitor ();

            var iter = monitor.iterate ();
            unowned Manette.Device? dev;
            while (iter.next (out dev)) {
                if (dev != null) connect_device (dev);
            }

            monitor.device_disconnected.connect ((device) => {
                if (repeat_device == device) stop_repeat ();
            });
            monitor.device_connected.connect ((device) => {
                connect_device (device);
                device_connected_notify (device.get_name ());
            });
        }

        private void connect_device (Manette.Device device) {
            device.button_press_event.connect (on_button_press);
            device.button_release_event.connect (on_button_release);
            device.absolute_axis_event.connect (on_axis_event);
            device.hat_axis_event.connect (on_hat_event);
        }

        private void start_repeat (Manette.Device device, int dx, int dy) {
            if (device == repeat_device && dx == nav_dx && dy == nav_dy && repeat_source != 0) return;
            stop_repeat ();

            repeat_device = device;
            nav_dx = dx;
            nav_dy = dy;
            window.gamepad_navigate (dx, dy);

            repeat_source = Timeout.add (REPEAT_DELAY, () => {
                repeat_source = Timeout.add (REPEAT_INTERVAL, () => {
                    window.gamepad_navigate (nav_dx, nav_dy);
                    return Source.CONTINUE;
                });
                return Source.REMOVE;
            });
        }

        private void stop_repeat () {
            if (repeat_source != 0) {
                Source.remove (repeat_source);
                repeat_source = 0;
            }
            repeat_device = null;
            nav_dx = 0;
            nav_dy = 0;
        }

        private void on_button_press (Manette.Event event) {
            uint16 button;
            if (!event.get_button (out button)) return;

            switch (button) {
                case BTN_SOUTH:
                    window.gamepad_activate ();
                    break;
                case BTN_EAST:
                    window.gamepad_back ();
                    break;
                case BTN_NORTH:
                    window.gamepad_context_menu ();
                    break;
                case BTN_MODE:
                    if (is_steam_running ()) break;
                    window.gamepad_toggle ();
                    break;
                case BTN_DPAD_UP:
                    start_repeat (event.get_device (), 0, -1);
                    break;
                case BTN_DPAD_DOWN:
                    start_repeat (event.get_device (), 0, 1);
                    break;
                case BTN_DPAD_LEFT:
                    start_repeat (event.get_device (), -1, 0);
                    break;
                case BTN_DPAD_RIGHT:
                    start_repeat (event.get_device (), 1, 0);
                    break;
                case BTN_TL:
                    window.gamepad_scroll (-1);
                    break;
                case BTN_TR:
                    window.gamepad_scroll (1);
                    break;
            }
        }

        private void on_button_release (Manette.Event event) {
            uint16 button;
            if (!event.get_button (out button)) return;

            switch (button) {
                case BTN_DPAD_UP:
                case BTN_DPAD_DOWN:
                case BTN_DPAD_LEFT:
                case BTN_DPAD_RIGHT:
                    if (repeat_device == event.get_device ()) stop_repeat ();
                    break;
            }
        }

        private void on_axis_event (Manette.Event event) {
            uint16 axis;
            double value;
            if (!event.get_absolute (out axis, out value)) return;

            if (axis != ABS_X && axis != ABS_Y) return;
            if (repeat_device != null && repeat_device != event.get_device ()) {
                if (value >= -STICK_DEADZONE && value <= STICK_DEADZONE) return;
                stop_repeat ();
            }
            if (axis == ABS_X) {
                if (value < -STICK_DEADZONE) {
                    start_repeat (event.get_device (), -1, nav_dy);
                } else if (value > STICK_DEADZONE) {
                    start_repeat (event.get_device (), 1, nav_dy);
                } else if (nav_dx != 0) {
                    if (nav_dy != 0) {
                        start_repeat (event.get_device (), 0, nav_dy);
                    } else {
                        stop_repeat ();
                    }
                }
            } else if (axis == ABS_Y) {
                if (value < -STICK_DEADZONE) {
                    start_repeat (event.get_device (), nav_dx, -1);
                } else if (value > STICK_DEADZONE) {
                    start_repeat (event.get_device (), nav_dx, 1);
                } else if (nav_dy != 0) {
                    if (nav_dx != 0) {
                        start_repeat (event.get_device (), nav_dx, 0);
                    } else {
                        stop_repeat ();
                    }
                }
            }
        }

        private void on_hat_event (Manette.Event event) {
            uint16 axis;
            int8 value;
            if (!event.get_hat (out axis, out value)) return;

            if (axis % 2 == 0) {
                if (value < 0) start_repeat (event.get_device (), -1, 0);
                else if (value > 0) start_repeat (event.get_device (), 1, 0);
                else if (repeat_device == event.get_device ()) stop_repeat ();
            } else {
                if (value < 0) start_repeat (event.get_device (), 0, -1);
                else if (value > 0) start_repeat (event.get_device (), 0, 1);
                else if (repeat_device == event.get_device ()) stop_repeat ();
            }
        }
    }
}
