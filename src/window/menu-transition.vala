namespace XimperShellLauncher {
    // The native surface stays fixed. A usable-output host carries whole-menu Slide.
    public class MenuTransition : Gtk.Widget {
        private Gtk.Widget content;
        private Adw.Animation? motion;
        private bool scale_spring;
        private Adw.TimedAnimation? fade;
        private uint completion_idle;
        private uint generation;
        private double x;
        private double y;
        private double scale = 1;
        private double alpha = 1;
        private int allocated_width;
        private int allocated_height;
        private int horizontal;
        private int vertical;
        private int margin_x;
        private int margin_y;
        private bool prepared;
        private AnimationProfile? pending_open;
        public bool hosted { get; private set; }
        public Gdk.Rectangle menu_rect;
        public bool running { get; private set; }
        public signal void settled ();
        public signal void allocation_changed ();

        public MenuTransition (Gtk.Widget content) {
            this.content = content;
            set_layout_manager (null);
            content.set_parent (this);
        }
        public void configure_host (bool enabled, int horizontal, int vertical, int margin_x, int margin_y) {
            hosted = enabled;
            this.horizontal = horizontal;
            this.vertical = vertical;
            this.margin_x = margin_x;
            this.margin_y = margin_y;
            queue_resize ();
        }
        protected override void measure (Gtk.Orientation orientation, int for_size,
            out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            if (hosted) {
                minimum = natural = 0;
                minimum_baseline = natural_baseline = -1;
            } else {
                content.measure (orientation, for_size, out minimum, out natural,
                    out minimum_baseline, out natural_baseline);
            }
        }
        protected override void size_allocate (int width, int height, int baseline) {
            bool changed = allocated_width > 0 && allocated_height > 0 &&
                (width != allocated_width || height != allocated_height);
            allocated_width = width;
            allocated_height = height;
            menu_rect = Gdk.Rectangle () { x = 0, y = 0, width = width, height = height };
            if (hosted) {
                int minimum, natural, min_baseline, nat_baseline;
                content.measure (Gtk.Orientation.HORIZONTAL, -1, out minimum, out natural, out min_baseline, out nat_baseline);
                MenuPlacement.axis (width, int.max (minimum, natural), horizontal, margin_x, out menu_rect.x, out menu_rect.width);
                content.measure (Gtk.Orientation.VERTICAL, menu_rect.width, out minimum, out natural, out min_baseline, out nat_baseline);
                MenuPlacement.axis (height, int.max (minimum, natural), vertical, margin_y, out menu_rect.y, out menu_rect.height);
            }
            var transform = new Gsk.Transform ().translate (Graphene.Point () { x = menu_rect.x, y = menu_rect.y });
            content.allocate (menu_rect.width, menu_rect.height, baseline, transform);
            allocation_changed ();
            if (pending_open != null) {
                if (completion_idle == 0) {
                    weak MenuTransition owner = this;
                    completion_idle = Idle.add (() => {
                        if (owner == null) return Source.REMOVE;
                        owner.completion_idle = 0;
                        var profile = owner.pending_open;
                        if (profile == null) return Source.REMOVE;
                        owner.pending_open = null;
                        owner.prepared = false;
                        owner.visual_endpoint (profile, out owner.x, out owner.y, out owner.scale);
                        owner.alpha = profile.effect == AnimationEffect.SLIDE ? 1 : 0;
                        run (owner, true, profile);
                        return Source.REMOVE;
                    });
                }
            } else if (changed && running) {
                cancel ();
                weak MenuTransition owner = this;
                completion_idle = Idle.add (() => {
                    if (owner == null) return Source.REMOVE;
                    owner.completion_idle = 0;
                    owner.settled ();
                    return Source.REMOVE;
                });
            }
        }
        protected override void snapshot (Gtk.Snapshot snapshot) {
            snapshot.save ();
            snapshot.push_opacity (alpha);
            float cx = menu_rect.x + menu_rect.width / 2.0f;
            float cy = menu_rect.y + menu_rect.height / 2.0f;
            snapshot.translate (Graphene.Point () { x = (float) x + cx, y = (float) y + cy });
            snapshot.scale ((float) scale, (float) scale);
            snapshot.translate (Graphene.Point () { x = -cx, y = -cy });
            if (hosted) {
                Gsk.Shadow shadow = Gsk.Shadow () {
                    color = Gdk.RGBA () { red = 0, green = 0, blue = 0, alpha = 0.25f },
                    dx = 0, dy = 8, radius = 24
                };
                snapshot.push_shadow ({ shadow });
            }
            snapshot_child (content, snapshot);
            if (hosted) snapshot.pop ();
            snapshot.pop ();
            snapshot.restore ();
        }
        public static void endpoint (AnimationProfile profile, out double tx, out double ty, out double ts) {
            tx = ty = 0;
            ts = 1;
            if (profile.effect == AnimationEffect.ZOOM) ts = profile.zoom_scale_percent / 100.0;
            else if (profile.effect == AnimationEffect.POP) ts = profile.pop_scale_percent / 100.0;
        }
        private void visual_endpoint (AnimationProfile profile, out double tx, out double ty, out double ts) {
            endpoint (profile, out tx, out ty, out ts);
            if (profile.effect == AnimationEffect.SLIDE)
                MenuPlacement.slide (profile.slide_direction, menu_rect, get_width (), get_height (), out tx, out ty);
        }
        public void prepare (AnimationProfile profile) {
            cancel ();
            prepared = true;
            // Blank until the compositor supplies the usable output allocation.
            alpha = 0;
            queue_draw ();
        }
        public void cancel () {
            generation++;
            pending_open = null;
            prepared = false;
            if (completion_idle != 0) { Source.remove (completion_idle); completion_idle = 0; }
            if (motion != null) motion.pause ();
            if (fade != null) fade.pause ();
            motion = null;
            scale_spring = false;
            fade = null;
            running = false;
        }
        public void finish (bool open) {
            cancel ();
            x = y = 0;
            scale = 1;
            alpha = open ? 1 : 0;
            queue_draw ();
        }
        public void transition (bool open, AnimationProfile profile) {
            if (open && prepared) {
                pending_open = profile.copy ();
                running = true;
                queue_allocate ();
                return;
            }
            if (!open && pending_open != null) {
                finish (false);
                settled ();
                return;
            }
            run (this, open, profile);
        }
        private static void run (MenuTransition widget, bool open, AnimationProfile profile) {
            weak MenuTransition self = widget;
            double velocity = (self.scale_spring && self.motion is Adw.SpringAnimation) ? ((Adw.SpringAnimation) self.motion).velocity : 0;
            self.cancel ();
            uint token = self.generation;
            double tx, ty, ts;
            self.visual_endpoint (profile, out tx, out ty, out ts);
            if (open) { tx = ty = 0; ts = 1; }
            uint duration = (uint) profile.fade_duration_ms;
            if (profile.effect == AnimationEffect.SLIDE) duration = (uint) profile.slide_duration_ms;
            if (profile.effect == AnimationEffect.ZOOM) duration = (uint) profile.zoom_duration_ms;
            if (profile.effect == AnimationEffect.POP) duration = 180;
            if (profile.effect == AnimationEffect.NONE || duration == 0 || !self.get_settings ().gtk_enable_animations) {
                self.finish (open);
                self.settled ();
                return;
            }
            self.running = true;
            if (profile.effect == AnimationEffect.SLIDE) {
                // Slide is translation-only, including a switch from another effect.
                self.alpha = 1;
                self.scale = 1;
                run_slide (self, token, open, duration, tx, ty);
                return;
            }
            double sx = self.x, sy = self.y, ss = self.scale, sa = self.alpha;
            bool motion_done = false;
            bool fade_done = false;
            var target = new Adw.CallbackAnimationTarget ((value) => {
                if (self == null || self.generation != token) return;
                if (profile.effect == AnimationEffect.POP) self.scale = value;
                else self.scale = ss + (ts - ss) * value;
                self.queue_draw ();
            });
            if (profile.effect == AnimationEffect.POP) {
                var spring = new Adw.SpringAnimation (widget, self.scale, ts,
                    new Adw.SpringParams (profile.pop_damping_percent / 100.0, AnimationProfile.SPRING_MASS, profile.pop_stiffness), target);
                spring.initial_velocity = velocity;
                self.motion = spring;
                self.scale_spring = true;
            } else {
                var timed = new Adw.TimedAnimation (widget, 0, 1, duration, target);
                timed.easing = Adw.Easing.EASE_OUT_CUBIC;
                self.motion = timed;
            }
            self.fade = new Adw.TimedAnimation (widget, 0, 1, duration, new Adw.CallbackAnimationTarget ((value) => {
                if (self == null || self.generation != token) return;
                double target_alpha = (open || profile.effect == AnimationEffect.SLIDE) ? 1 : 0;
                self.alpha = sa + (target_alpha - sa) * value;
                self.x = sx + (tx - sx) * value;
                self.y = sy + (ty - sy) * value;
                self.queue_draw ();
            }));
            self.fade.done.connect (() => {
                fade_done = true;
                if (motion_done && self != null && self.generation == token)
                    schedule_completion (self, token, open);
            });
            self.motion.done.connect (() => {
                motion_done = true;
                if (fade_done && self != null && self.generation == token)
                    schedule_completion (self, token, open);
            });
            self.fade.play ();
            self.motion.play ();
        }
        private static void run_slide (MenuTransition widget, uint token, bool open,
                                       uint duration, double tx, double ty) {
            weak MenuTransition owner = widget;
            double sx = widget.x, sy = widget.y;
            // Finish the timed flight slightly beyond the resting point. Its
            // zero terminal velocity gives the physical spring a smooth handoff.
            double distance = double.max (sx.abs (), sy.abs ());
            if (open && distance > 0) {
                double overshoot = double.min (16, distance * 0.04);
                tx = -sx / distance * overshoot;
                ty = -sy / distance * overshoot;
            }
            var flight = new Adw.TimedAnimation (widget, 0, 1, duration,
                new Adw.CallbackAnimationTarget ((value) => {
                    if (owner == null || owner.generation != token) return;
                    owner.x = sx + (tx - sx) * value;
                    owner.y = sy + (ty - sy) * value;
                    owner.queue_draw ();
                }));
            flight.easing = Adw.Easing.EASE_OUT_CUBIC;
            flight.done.connect (() => {
                if (owner == null || owner.generation != token) return;
                if (!open) {
                    schedule_completion (owner, token, false);
                    return;
                }
                // Never replace an animation inside its own done emission.
                owner.completion_idle = Idle.add (() => {
                    if (owner == null || owner.generation != token) return Source.REMOVE;
                    owner.completion_idle = 0;
                    settle_slide (owner, token);
                    return Source.REMOVE;
                });
            });
            widget.motion = flight;
            flight.play ();
        }
        private static void settle_slide (MenuTransition widget, uint token) {
            weak MenuTransition owner = widget;
            double sx = widget.x, sy = widget.y;
            var spring = new Adw.SpringAnimation (widget, 1, 0,
                new Adw.SpringParams (0.5, 1, 400),
                new Adw.CallbackAnimationTarget ((value) => {
                    if (owner == null || owner.generation != token) return;
                    owner.x = sx * value;
                    owner.y = sy * value;
                    owner.queue_draw ();
                }));
            spring.done.connect (() => {
                if (owner != null && owner.generation == token)
                    schedule_completion (owner, token, true);
            });
            widget.motion = spring;
            spring.play ();
        }
        private static void schedule_completion (MenuTransition widget, uint token, bool open) {
            weak MenuTransition owner = widget;
            widget.completion_idle = Idle.add (() => {
                if (owner == null || owner.generation != token) return Source.REMOVE;
                owner.completion_idle = 0;
                owner.finish (open);
                owner.settled ();
                return Source.REMOVE;
            });
        }
        protected override void dispose () {
            cancel ();
            if (content != null) { content.unparent (); content = null; }
            base.dispose ();
        }
    }
}
