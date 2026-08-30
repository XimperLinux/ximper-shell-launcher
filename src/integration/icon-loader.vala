namespace XimperShellLauncher {

    private class IconLoadState : Object {
        public Cancellable? cancellable;
        public uint generation;
    }

    private class IconCacheEntry : Object {
        public string key;
        public Gdk.Texture texture;

        public IconCacheEntry (string key, Gdk.Texture texture) {
            this.key = key;
            this.texture = texture;
        }
    }

    // Shared bounded icon decoder. Per-image generations make it safe to reuse
    // Gtk.Image instances while an earlier asynchronous load is still pending.
    public class IconLoader : Object {
        // Cover the complete installed-app grid without repeated eviction,
        // while keeping the decoded texture cache strictly bounded.
        private const uint CACHE_LIMIT = 512;
        private static GenericArray<IconCacheEntry>? cache;

        private static GenericArray<IconCacheEntry> get_cache () {
            if (cache == null) cache = new GenericArray<IconCacheEntry> ();
            return cache;
        }

        private static IconLoadState image_state (Gtk.Image image) {
            var state = image.get_data<IconLoadState> ("icon-load-state");
            if (state == null) {
                state = new IconLoadState ();
                image.set_data<IconLoadState> ("icon-load-state", state);
            }
            return state;
        }

        public static void cancel (Gtk.Image image) {
            var state = image_state (image);
            state.generation++;
            if (state.cancellable != null) {
                state.cancellable.cancel ();
                state.cancellable = null;
            }
        }

        public static void clear (Gtk.Image image) {
            image.paintable = null;
            image.gicon = null;
            image.icon_name = null;
            image.visible = false;
        }

        public static void cancel_and_clear (Gtk.Image image) {
            cancel (image);
            clear (image);
        }

        private static Gdk.Texture? lookup (string key) {
            var entries = get_cache ();
            for (uint i = 0; i < entries.length; i++) {
                if (entries[i].key == key) {
                    var entry = entries[i];
                    entries.remove_index (i);
                    entries.add (entry);
                    return entry.texture;
                }
            }
            return null;
        }

        private static void store (string key, Gdk.Texture texture) {
            var entries = get_cache ();
            entries.add (new IconCacheEntry (key, texture));
            if (entries.length > CACHE_LIMIT) entries.remove_index (0);
        }

        public static void set_image_icon (Gtk.Image image, Icon? icon,
                                           int logical_size, bool fallback) {
            cancel_and_clear (image);
            image.pixel_size = logical_size;

            if (icon == null) {
                if (fallback) {
                    image.icon_name = "application-x-executable-symbolic";
                    image.visible = true;
                }
                return;
            }

            int scale = int.max (1, image.scale_factor);
            var loadable = icon as LoadableIcon;
            if (loadable == null) {
                var theme = Gtk.IconTheme.get_for_display (image.get_display ());
                var paintable = theme.lookup_by_gicon (icon, logical_size, scale,
                    image.get_direction (), Gtk.IconLookupFlags.NONE);
                var themed_file = paintable.get_file ();
                var basename = themed_file != null ? themed_file.get_basename () : null;
                bool symbolic = basename != null && basename.contains ("-symbolic.");
                if (themed_file != null && themed_file.is_native () && !symbolic) {
                    loadable = new FileIcon (themed_file);
                } else {
                    image.gicon = icon;
                    image.visible = true;
                    return;
                }
            }

            string? uri = null;
            var file_icon = loadable as FileIcon;
            if (file_icon != null) {
                if (!file_icon.file.is_native ()) {
                    show_fallback (image, fallback);
                    return;
                }
                uri = file_icon.file.get_uri ();
            } else {
                uri = icon.to_string ();
            }
            if (uri == null) {
                show_fallback (image, fallback);
                return;
            }

            int physical_size = logical_size * scale;
            string key = "%s|%d|%d".printf (uri, physical_size, scale);
            var cached = lookup (key);
            if (cached != null) {
                image.paintable = cached;
                image.visible = true;
                return;
            }

            var state = image_state (image);
            state.cancellable = new Cancellable ();
            uint generation = state.generation;
            load_async.begin (loadable, physical_size, state.cancellable, (obj, res) => {
                Gdk.Texture? texture = null;
                try { texture = load_async.end (res); } catch (Error e) {}
                if (state.generation != generation || state.cancellable == null ||
                    state.cancellable.is_cancelled ()) return;
                state.cancellable = null;
                if (texture != null) {
                    store (key, texture);
                    image.paintable = texture;
                    image.visible = true;
                } else {
                    show_fallback (image, fallback);
                }
            });
        }

        private static void show_fallback (Gtk.Image image, bool fallback) {
            if (fallback) {
                image.icon_name = "application-x-executable-symbolic";
                image.visible = true;
            }
        }

        private static async Gdk.Texture load_async (LoadableIcon icon, int size,
                                                     Cancellable cancellable)
                                                     throws Error {
            string? content_type = null;
            InputStream stream = yield icon.load_async (size, cancellable, out content_type);
            var pixbuf = yield new Gdk.Pixbuf.from_stream_at_scale_async (
                stream, size, size, true, cancellable);
            try { yield stream.close_async (Priority.DEFAULT, cancellable); }
            catch (Error e) {}
            var format = pixbuf.has_alpha
                ? Gdk.MemoryFormat.R8G8B8A8
                : Gdk.MemoryFormat.R8G8B8;
            return new Gdk.MemoryTexture (
                pixbuf.width,
                pixbuf.height,
                format,
                pixbuf.read_pixel_bytes (),
                (size_t) pixbuf.rowstride
            );
        }
    }
}
