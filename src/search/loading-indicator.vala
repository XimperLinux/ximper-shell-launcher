namespace XimperShellLauncher {

    // Original GTK rendering inspired by Zen's indefinitely moving 75% segment.
    // It runs immediately here, then returns to a compact capsule before fading.
    // Reference (MPL-2.0; no browser assets or source are embedded here):
    // https://github.com/zen-browser/desktop/blob/dev/src/zen/common/sys/ui/ZenProgressBar.sys.mjs
    // https://github.com/zen-browser/desktop/blob/dev/src/zen/common/styles/zen-single-components.css
    // https://github.com/zen-browser/desktop/blob/dev/src/zen/common/styles/zen-animations.css
    public class LoadingIndicator : Gtk.DrawingArea {
        private const double SETTLE_SECONDS = 0.3;
        private const double FADE_SECONDS = 0.3;
        private bool loading = false;
        private int64 started = 0;
        private int64 transition_started = 0;
        private double amount = 0;
        private double expansion = 0;
        private double segment_left = 0;
        private double segment_width = 1;
        private double from_amount = 0;
        private double from_expansion = 0;
        private double from_left = 0;
        private double from_width = 1;
        private uint tick_id = 0;
        private ulong settings_handler = 0;

        public LoadingIndicator () {
            Object (content_height: 16);
            can_target = false;
            focusable = false;
            add_css_class ("loading-indicator");
            weak LoadingIndicator weak_self = this;
            settings_handler = get_settings ().notify["gtk-enable-animations"].connect (() => {
                var self = weak_self;
                if (self == null) return;
                if (!self.animations_enabled ()) self.snap_to_static ();
                self.capture_transition (get_monotonic_time ());
                self.ensure_tick ();
                self.queue_draw ();
            });
            set_draw_func ((area, cr, width, height) => {
                var self = weak_self;
                if (self != null) self.draw_indicator (cr, width, height);
            });
        }

        public void set_loading (bool loading) {
            if (this.loading == loading) return;
            int64 now = get_monotonic_time ();
            update_animation (now);
            capture_transition (now);
            this.loading = loading;
            if (loading) started = now;
            if (!animations_enabled ()) snap_to_static ();
            ensure_tick ();
            queue_draw ();
        }

        private void capture_transition (int64 now) {
            from_amount = amount;
            from_expansion = expansion;
            from_left = segment_left;
            from_width = segment_width;
            transition_started = now;
        }

        private bool animations_enabled () {
            return get_settings ().gtk_enable_animations;
        }

        private void snap_to_static () {
            amount = loading ? 1 : 0;
            expansion = segment_left = 0;
            segment_width = 1;
        }

        private void update_animation (int64 now) {
            if (!animations_enabled ()) {
                snap_to_static ();
                return;
            }
            double elapsed = (now - transition_started) / 1000000.0;
            double settle = Adw.Easing.EASE_OUT_CUBIC.ease ((elapsed / SETTLE_SECONDS).clamp (0, 1));
            if (loading) {
                double appear = Adw.Easing.EASE_OUT_CUBIC.ease ((elapsed / 0.4).clamp (0, 1));
                amount = from_amount + (1 - from_amount) * appear;
                expansion = from_expansion + (1 - from_expansion) * settle;
                double running = (now - started) / 1000000.0;
                double phase = running - (int64) running;
                double runner_left = -1 + 2 * Adw.Easing.EASE_IN_OUT_CUBIC.ease (phase);
                segment_left = from_left + (runner_left - from_left) * settle;
                segment_width = from_width + (0.75 - from_width) * settle;
            } else {
                // First restore the short, solid default capsule. Only after
                // that transition is complete may its opacity start falling.
                expansion = from_expansion * (1 - settle);
                segment_left = from_left * (1 - settle);
                segment_width = from_width + (1 - from_width) * settle;
                double fade = Adw.Easing.EASE_OUT_CUBIC.ease (
                    ((elapsed - SETTLE_SECONDS) / FADE_SECONDS).clamp (0, 1));
                amount = from_amount * (1 - fade);
            }
        }

        private void ensure_tick () {
            if (tick_id != 0 || !get_mapped () || (!loading && amount == 0)) return;
            weak LoadingIndicator weak_self = this;
            tick_id = add_tick_callback ((widget, clock) => {
                var self = weak_self;
                if (self == null) return Source.REMOVE;
                self.update_animation (get_monotonic_time ());
                self.queue_draw ();
                if (!self.animations_enabled () || (!self.loading && self.amount == 0)) {
                    self.tick_id = 0;
                    return Source.REMOVE;
                }
                return Source.CONTINUE;
            });
        }

        private void draw_indicator (Cairo.Context cr, int width, int height) {
            if (amount <= 0 || width <= 12) return;
            double available = width - 12;
            double compact = double.min (72, available);
            double expanded = double.min (160, available);
            double capsule_width = compact + (expanded - compact) * expansion;
            double x = (width - capsule_width) / 2;
            double y = (height - 4) / 2.0;
            var color = get_color ();

            // Dim track behind the moving rounded segment (no gradient shimmer).
            capsule (cr, x, y, capsule_width, 4);
            cr.set_source_rgba (color.red, color.green, color.blue, amount * 0.12 * expansion);
            cr.fill ();
            cr.save ();
            capsule (cr, x, y, capsule_width, 4);
            cr.clip ();
            double moving_x = x + segment_left * capsule_width;
            double moving_width = segment_width * capsule_width;
            capsule (cr, moving_x, y, moving_width, 4);
            cr.set_source_rgba (color.red, color.green, color.blue, amount * 0.9);
            cr.fill ();
            cr.restore ();
        }

        private static void capsule (Cairo.Context cr, double x, double y, double width, double height) {
            double radius = height / 2;
            cr.new_sub_path ();
            cr.arc (x + width - radius, y + radius, radius, -Math.PI / 2, Math.PI / 2);
            cr.arc (x + radius, y + radius, radius, Math.PI / 2, 3 * Math.PI / 2);
            cr.close_path ();
        }

        protected override void map () {
            base.map ();
            update_animation (get_monotonic_time ());
            queue_draw ();
            ensure_tick ();
        }

        protected override void unmap () {
            if (tick_id != 0) remove_tick_callback (tick_id);
            tick_id = 0;
            base.unmap ();
        }

        protected override void dispose () {
            if (settings_handler != 0) get_settings ().disconnect (settings_handler);
            settings_handler = 0;
            if (tick_id != 0) remove_tick_callback (tick_id);
            tick_id = 0;
            base.dispose ();
        }
    }
}
