namespace XimperShellTileMenu {

    public class LayerShellHelper {

        public static GtkLayerShell.Layer parse_layer (int val) {
            return (GtkLayerShell.Layer) val.clamp (0, 3);
        }

        public static void setup_overlay (Gtk.Window window, GtkLayerShell.Layer layer) {
            GtkLayerShell.init_for_window (window);
            GtkLayerShell.set_layer (window, layer);
            GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.TOP, true);
            GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.BOTTOM, true);
            GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.LEFT, true);
            GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.RIGHT, true);
            GtkLayerShell.set_keyboard_mode (window, GtkLayerShell.KeyboardMode.ON_DEMAND);
            GtkLayerShell.set_namespace (window, "ximper-shell-tile-menu");
        }
    }
}
