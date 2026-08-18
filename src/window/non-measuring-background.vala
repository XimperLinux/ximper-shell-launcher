namespace XimperShellLauncher {

    private class NonMeasuringBackground : Gtk.Widget {
        private Gtk.Picture picture;

        public NonMeasuringBackground (Gtk.Picture picture) {
            this.picture = picture;
            picture.set_parent (this);
        }

        public override void measure (Gtk.Orientation orientation, int for_size,
                                     out int minimum, out int natural,
                                     out int minimum_baseline, out int natural_baseline) {
            minimum = 0;
            natural = 0;
            minimum_baseline = -1;
            natural_baseline = -1;
        }

        public override void size_allocate (int width, int height, int baseline) {
            picture.allocate (width, height, baseline, null);
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            snapshot_child (picture, snapshot);
        }
    }
}
