namespace XimperShellTileMenu {

    public class LayerShellHelper {

        public static void setup_overlay (Gtk.Window window) {
            GtkLayerShell.init_for_window (window);
            GtkLayerShell.set_layer (window, GtkLayerShell.Layer.OVERLAY);
            GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.TOP, true);
            GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.BOTTOM, true);
            GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.LEFT, true);
            GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.RIGHT, true);
            GtkLayerShell.set_keyboard_mode (window, GtkLayerShell.KeyboardMode.ON_DEMAND);
            GtkLayerShell.set_namespace (window, "ximper-shell-tile-menu");
        }
    }
}
