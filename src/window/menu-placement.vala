namespace XimperShellLauncher {
    // Layer-shell's single-edge/center placement in the allocated usable area.
    // This intentionally needs no global surface coordinates or panel heights.
    public class MenuPlacement : Object {
        public static void axis (int available, int requested, int alignment, int margin,
                                 out int origin, out int size) {
            int source = int.max (1, available - (alignment == 0 ? 0 : margin));
            size = int.max (1, int.min (requested, source));
            origin = alignment < 0 ? margin : (alignment > 0 ? source - size : source / 2 - size / 2);
        }

        public static void slide (AnimationDirection direction, Gdk.Rectangle menu,
                                  int width, int height, out double x, out double y) {
            // Include the menu shadow, so no pixels remain at the hidden endpoint.
            const int SHADOW_EXTENT = 40;
            x = y = 0;
            switch (direction) {
                case AnimationDirection.LEFT: x = -menu.x - menu.width - SHADOW_EXTENT; break;
                case AnimationDirection.RIGHT: x = width - menu.x + SHADOW_EXTENT; break;
                case AnimationDirection.TOP: y = -menu.y - menu.height - SHADOW_EXTENT; break;
                case AnimationDirection.BOTTOM: y = height - menu.y + SHADOW_EXTENT; break;
            }
        }
    }
}
