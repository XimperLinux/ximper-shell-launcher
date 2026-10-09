namespace XimperShellLauncher {

    // Keep the same list mounted while its edge slides over the tile area.
    // Tile geometry stays stable; only the uncovered region is drawn.
    public class CombinedView : Gtk.Widget {
        private Gtk.Widget? tiles;
        private Gtk.Widget? list;
        private AppListSide side = AppListSide.LEFT;
        private double progress = 0;
        private bool searching = false;
        private Adw.TimedAnimation? animation;
        private const int COLUMN_WIDTH = 280;

        public CombinedView () {
            set_layout_manager (null);
            hexpand = true;
            vexpand = true;
            overflow = Gtk.Overflow.HIDDEN;
        }

        public void attach (Gtk.Widget tiles, Gtk.Widget list, AppListSide side) {
            this.tiles = tiles;
            this.list = list;
            this.side = side;
            tiles.set_parent (this);
            list.set_parent (this);
            list.overflow = Gtk.Overflow.HIDDEN;
        }

        public void detach () {
            if (animation != null) animation.pause ();
            animation = null;
            if (tiles != null) {
                tiles.opacity = 1;
                tiles.can_target = true;
                tiles.set_child_visible (true);
                tiles.unparent ();
            }
            if (list != null) list.unparent ();
            tiles = null;
            list = null;
        }

        public void set_side (AppListSide side) {
            this.side = side;
            queue_allocate ();
        }

        public void set_searching (bool searching, bool animate) {
            double target = searching ? 1 : 0;
            if (this.searching == searching) {
                if (progress == target) return;
                if (animate && get_mapped () && animation != null &&
                    animation.state == Adw.AnimationState.PLAYING) return;
            }
            this.searching = searching;
            if (animation != null) animation.pause ();
            if (tiles != null) {
                tiles.can_target = !searching;
                tiles.set_child_visible (true);
            }
            if (!animate || !get_mapped ()) {
                progress = target;
                queue_allocate ();
                queue_draw ();
                return;
            }
            weak CombinedView weak_self = this;
            animation = new Adw.TimedAnimation (this, progress, target, 260,
                new Adw.CallbackAnimationTarget ((value) => {
                    var self = weak_self;
                    if (self == null) return;
                    self.progress = value;
                    self.queue_allocate ();
                    self.queue_draw ();
                }));
            animation.easing = Adw.Easing.EASE_OUT_CUBIC;
            animation.play ();
        }

        private int column_width (int width) {
            return int.min (COLUMN_WIDTH, int.max (1, width / 2));
        }

        private int list_width (int width) {
            int compact = column_width (width);
            return compact + (int) ((width - compact) * progress + 0.5);
        }

        protected override void size_allocate (int width, int height, int baseline) {
            if (tiles == null || list == null) return;
            int compact = column_width (width);
            int expanded = list_width (width);
            tiles.set_child_visible (progress < 1);
            if (tiles.get_child_visible ()) {
                var point = Graphene.Point ();
                point.init (side == AppListSide.LEFT ? compact : 0, 0);
                tiles.allocate (int.max (1, width - compact), height, baseline,
                    new Gsk.Transform ().translate (point));
            }
            var list_point = Graphene.Point ();
            list_point.init (side == AppListSide.LEFT ? 0 : width - expanded, 0);
            list.allocate (expanded, height, baseline,
                new Gsk.Transform ().translate (list_point));
        }

        protected override void snapshot (Gtk.Snapshot snapshot) {
            if (tiles == null || list == null) return;
            int width = get_width ();
            int expanded = list_width (width);
            if (tiles.get_child_visible ()) {
                var clip = Graphene.Rect ();
                clip.init (side == AppListSide.LEFT ? expanded : 0, 0,
                    int.max (0, width - expanded), get_height ());
                snapshot.push_clip (clip);
                snapshot_child (tiles, snapshot);
                snapshot.pop ();
            }
            snapshot_child (list, snapshot);
        }

        protected override void measure (Gtk.Orientation orientation, int for_size,
                                          out int minimum, out int natural,
                                          out int minimum_baseline, out int natural_baseline) {
            minimum_baseline = natural_baseline = -1;
            minimum = natural = 0;
            if (tiles == null || list == null) return;
            int tile_min, tile_nat, list_min, list_nat;
            tiles.measure (orientation, for_size, out tile_min, out tile_nat, null, null);
            list.measure (orientation, for_size, out list_min, out list_nat, null, null);
            if (orientation == Gtk.Orientation.HORIZONTAL) {
                minimum = tile_min + int.min (COLUMN_WIDTH, list_min);
                natural = int.max (minimum, COLUMN_WIDTH + tile_nat);
            } else {
                minimum = int.max (tile_min, list_min);
                natural = int.max (tile_nat, list_nat);
            }
        }

        protected override void dispose () {
            detach ();
            base.dispose ();
        }
    }
}
