namespace XimperShellTileMenu {

    public class FolderAnimator {

        private weak Gtk.Widget owner;

        public double slide_progress { get; set; default = 1.0; }
        public double cascade_progress { get; set; default = 1.0; }

        private Adw.TimedAnimation? slide_anim;
        private Adw.TimedAnimation? cascade_anim;

        public delegate void Callback ();

        public FolderAnimator (Gtk.Widget owner) {
            this.owner = owner;
        }

        public void cancel () {
            if (slide_anim != null) {
                slide_anim.pause ();
                slide_anim = null;
            }
            if (cascade_anim != null) {
                cascade_anim.pause ();
                cascade_anim = null;
            }
        }

        public void reset () {
            cancel ();
            slide_progress = 1.0;
            cascade_progress = 1.0;
        }

        public void run_slide (double from, double to, owned Callback? then) {
            slide_progress = from;
            var target = new Adw.CallbackAnimationTarget ((val) => {
                slide_progress = val;
                owner.queue_resize ();
                owner.queue_allocate ();
            });
            slide_anim = new Adw.TimedAnimation (owner, from, to, 200, target);
            if (then != null) {
                slide_anim.done.connect (() => {
                    Idle.add (() => { then (); return Source.REMOVE; });
                });
            }
            slide_anim.play ();
        }

        public void run_cascade (double from, double to, owned Callback? then) {
            cascade_progress = from;
            int duration = to > from ? 350 : 200;
            var ct = new Adw.CallbackAnimationTarget ((val) => {
                cascade_progress = val;
                owner.queue_allocate ();
            });
            cascade_anim = new Adw.TimedAnimation (owner, from, to, duration, ct);
            if (then != null) {
                cascade_anim.done.connect (() => {
                    Idle.add (() => { then (); return Source.REMOVE; });
                });
            }
            cascade_anim.play ();
        }

        public double compute_item_opacity (int item_index, int total_items) {
            int total = total_items > 1 ? total_items - 1 : 1;
            double tile_start = 0.6 * item_index / total;
            double progress = (cascade_progress - tile_start) / 0.4;
            if (progress < 0.0) progress = 0.0;
            if (progress > 1.0) progress = 1.0;
            return progress;
        }
    }
}
