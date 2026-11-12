namespace XimperShellLauncher {
    public enum AnimationEffect {
        NONE, FADE, SLIDE, ZOOM, POP;
        public string to_string () {
            switch (this) {
            case NONE: return "none";
            case FADE: return "fade";
            case SLIDE: return "slide";
            case ZOOM: return "zoom";
            default: return "pop";
            }
        }
        public static AnimationEffect from_string (string value, AnimationEffect fallback = POP) {
            switch (value) {
            case "none": return NONE;
            case "fade": return FADE;
            case "slide": return SLIDE;
            case "zoom": return ZOOM;
            case "pop": return POP;
            default: return fallback;
            }
        }
    }

    public enum AnimationDirection {
        LEFT, RIGHT, TOP, BOTTOM;
        public string to_string () {
            switch (this) {
            case LEFT: return "left";
            case RIGHT: return "right";
            case TOP: return "top";
            default: return "bottom";
            }
        }
        public static AnimationDirection from_string (string value, AnimationDirection fallback = BOTTOM) {
            switch (value) {
            case "left": return LEFT;
            case "right": return RIGHT;
            case "top": return TOP;
            case "bottom": return BOTTOM;
            default: return fallback;
            }
        }
    }

    // Per-effect tuning is retained independently in each opening/hiding profile.
    public class AnimationProfile : Object {
        public AnimationEffect effect = AnimationEffect.SLIDE;
        public int fade_duration_ms = 180;
        public AnimationDirection slide_direction = AnimationDirection.TOP;
        // Legacy field retained on disk; Slide now derives travel from output geometry.
        public int slide_distance = 80;
        public int slide_duration_ms = 400;
        public int zoom_scale_percent = 85;
        public int zoom_duration_ms = 200;
        public int pop_scale_percent = 85;
        public int pop_damping_percent = 65;
        public int pop_stiffness = 300;
        public const double SPRING_MASS = 1.0;

        public static AnimationProfile opening () { return new AnimationProfile (); }
        public static AnimationProfile hiding () {
            var profile = new AnimationProfile ();
            profile.fade_duration_ms = 140;
            return profile;
        }
        public AnimationProfile copy () {
            var result = new AnimationProfile ();
            result.effect = effect;
            result.fade_duration_ms = fade_duration_ms;
            result.slide_direction = slide_direction;
            result.slide_distance = slide_distance;
            result.slide_duration_ms = slide_duration_ms;
            result.zoom_scale_percent = zoom_scale_percent;
            result.zoom_duration_ms = zoom_duration_ms;
            result.pop_scale_percent = pop_scale_percent;
            result.pop_damping_percent = pop_damping_percent;
            result.pop_stiffness = pop_stiffness;
            return result;
        }
        public static Json.Object? object_member (Json.Object parent, string name) {
            if (!parent.has_member (name)) return null;
            var node = parent.get_member (name);
            return node.get_node_type () == Json.NodeType.OBJECT ? node.get_object () : null;
        }
        private static string? string_member (Json.Object parent, string name) {
            if (!parent.has_member (name)) return null;
            var node = parent.get_member (name);
            return node.get_node_type () == Json.NodeType.VALUE && node.get_value_type () == typeof (string)
                ? node.get_string () : null;
        }
        private static int integer (Json.Object parent, string name, int fallback, int min, int max) {
            if (!parent.has_member (name)) return fallback;
            var node = parent.get_member (name);
            if (node.get_node_type () != Json.NodeType.VALUE || node.get_value_type () != typeof (int64))
                return fallback;
            // Clamp before narrowing, including values outside the range of int.
            int64 value = node.get_int ();
            return (int) value.clamp (min, max);
        }
        public void read (Json.Object obj) {
            var value = string_member (obj, "effect");
            if (value != null) effect = AnimationEffect.from_string (value, effect);
            var section = object_member (obj, "fade");
            if (section != null) fade_duration_ms = integer (section, "duration_ms", fade_duration_ms, 0, 2000);
            section = object_member (obj, "slide");
            if (section != null) {
                value = string_member (section, "direction");
                if (value != null) slide_direction = AnimationDirection.from_string (value, slide_direction);
                slide_distance = integer (section, "distance", slide_distance, 0, 512);
                slide_duration_ms = integer (section, "duration_ms", slide_duration_ms, 0, 2000);
            }
            section = object_member (obj, "zoom");
            if (section != null) {
                zoom_scale_percent = integer (section, "scale_percent", zoom_scale_percent, 50, 100);
                zoom_duration_ms = integer (section, "duration_ms", zoom_duration_ms, 0, 2000);
            }
            section = object_member (obj, "pop");
            if (section != null) {
                pop_scale_percent = integer (section, "scale_percent", pop_scale_percent, 50, 100);
                pop_damping_percent = integer (section, "damping_percent", pop_damping_percent, 30, 200);
                pop_stiffness = integer (section, "stiffness", pop_stiffness, 50, 1200);
            }
        }
        private static void add_int (Json.Builder builder, string key, int value) {
            builder.set_member_name (key);
            builder.add_int_value (value);
        }
        public void serialize (Json.Builder builder) {
            builder.begin_object ();
            builder.set_member_name ("effect"); builder.add_string_value (effect.to_string ());
            builder.set_member_name ("fade"); builder.begin_object ();
            add_int (builder, "duration_ms", fade_duration_ms); builder.end_object ();
            builder.set_member_name ("slide"); builder.begin_object ();
            builder.set_member_name ("direction"); builder.add_string_value (slide_direction.to_string ());
            add_int (builder, "duration_ms", slide_duration_ms); builder.end_object ();
            builder.set_member_name ("zoom"); builder.begin_object ();
            add_int (builder, "scale_percent", zoom_scale_percent);
            add_int (builder, "duration_ms", zoom_duration_ms); builder.end_object ();
            builder.set_member_name ("pop"); builder.begin_object ();
            add_int (builder, "scale_percent", pop_scale_percent);
            add_int (builder, "damping_percent", pop_damping_percent);
            add_int (builder, "stiffness", pop_stiffness); builder.end_object ();
            builder.end_object ();
        }
    }
}
