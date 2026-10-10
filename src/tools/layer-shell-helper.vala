namespace XimperShellLauncher {

    public class LayerShellHelper {

        public static string normalize_layer_name (string value) {
            switch (value) {
                case "background":
                case "bottom":
                case "top":
                case "overlay":
                    return value;
                default:
                    return "overlay";
            }
        }

        public static string layer_name_from_legacy (int value) {
            switch (value.clamp (0, 3)) {
                case 0: return "background";
                case 1: return "bottom";
                case 2: return "top";
                default: return "overlay";
            }
        }

        public static GtkLayerShell.Layer parse_layer (string value) {
            switch (normalize_layer_name (value)) {
                case "background": return GtkLayerShell.Layer.BACKGROUND;
                case "bottom": return GtkLayerShell.Layer.BOTTOM;
                case "top": return GtkLayerShell.Layer.TOP;
                default: return GtkLayerShell.Layer.OVERLAY;
            }
        }

        public static void setup_overlay (Gtk.Window window, GtkLayerShell.Layer layer) {
            GtkLayerShell.init_for_window (window);
            apply_window_mode (window, WindowMode.FULLSCREEN, layer);
            GtkLayerShell.set_keyboard_mode (window, GtkLayerShell.KeyboardMode.ON_DEMAND);
            GtkLayerShell.set_namespace (window, "ximper-shell-launcher");
        }

        public static void apply_window_mode (
            Gtk.Window window,
            WindowMode mode,
            GtkLayerShell.Layer layer,
            int floating_x = 0,
            int floating_y = 24,
            FloatingPosition position = FloatingPosition.CUSTOM,
            int edge_margin = 0
        ) {
            GtkLayerShell.set_layer (window, layer);
            // Floating menus respect panels' reserved space; fullscreen keeps
            // its intentional whole-output behavior.
            GtkLayerShell.set_exclusive_zone (window, mode == WindowMode.FLOATING ? 0 : -1);

            switch (mode) {
                case WindowMode.FLOATING:
                    bool manual = position == FloatingPosition.CUSTOM;
                    int horizontal = manual ? -1 : position.horizontal_alignment ();
                    int vertical = manual ? -1 : position.vertical_alignment ();
                    GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.TOP, vertical < 0);
                    GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.BOTTOM, vertical > 0);
                    GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.LEFT, horizontal < 0);
                    GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.RIGHT, horizontal > 0);
                    // Unanchored axes are centered by the compositor using the
                    // actual surface size, not an estimated requested size.
                    GtkLayerShell.set_margin (window, GtkLayerShell.Edge.TOP,
                        manual ? floating_y : (vertical < 0 ? edge_margin : 0));
                    GtkLayerShell.set_margin (window, GtkLayerShell.Edge.BOTTOM,
                        !manual && vertical > 0 ? edge_margin : 0);
                    GtkLayerShell.set_margin (window, GtkLayerShell.Edge.LEFT,
                        manual ? floating_x : (horizontal < 0 ? edge_margin : 0));
                    GtkLayerShell.set_margin (window, GtkLayerShell.Edge.RIGHT,
                        !manual && horizontal > 0 ? edge_margin : 0);
                    window.remove_css_class ("fullscreen");
                    window.add_css_class ("floating");
                    break;

                default:
                    GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.TOP, true);
                    GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.BOTTOM, true);
                    GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.LEFT, true);
                    GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.RIGHT, true);
                    GtkLayerShell.set_margin (window, GtkLayerShell.Edge.TOP, 0);
                    GtkLayerShell.set_margin (window, GtkLayerShell.Edge.BOTTOM, 0);
                    GtkLayerShell.set_margin (window, GtkLayerShell.Edge.LEFT, 0);
                    GtkLayerShell.set_margin (window, GtkLayerShell.Edge.RIGHT, 0);
                    window.remove_css_class ("floating");
                    window.add_css_class ("fullscreen");
                    break;
            }
        }
    }
}
