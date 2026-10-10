namespace XimperShellLauncher {
    public class TileGrid : Gtk.Box {
        private weak Application app;
        private GenericArray<TileBoard> boards = new GenericArray<TileBoard> ();
        private GenericArray<string> names = new GenericArray<string> ();
        private bool rebuild_pending;
        private weak TileBoard? drag_source;
        private string? drag_id;
        private bool drag_committed;
        private Gtk.Box? new_group_zone;
        private Gtk.Picture? new_group_preview;
        private uint rebuild_idle;
        private int drop_viewport_width;
        private int drop_viewport_height;
        private int last_board_height = 160;
        private bool horizontal_groups { get { return app.config.groups_enabled && app.config.group_layout == GroupLayout.HORIZONTAL; } }
        public bool has_active_drag { get { return drag_source != null && !drag_committed; } }
        public signal void drag_state_changed (bool active);
        public signal void layout_changing (bool active);

        public void set_drop_viewport_size (int width, int height) {
            drop_viewport_width = width;
            drop_viewport_height = height;
            if (new_group_zone == null) return;
            bool horizontal = horizontal_groups;
            int tail = int.max (horizontal ? 160 : 72, (horizontal ? width : height) / 2);
            int old_width, old_height;
            new_group_zone.get_size_request (out old_width, out old_height);
            if (old_width != (horizontal ? tail : -1) || old_height != (horizontal ? -1 : tail))
                new_group_zone.set_size_request (horizontal ? tail : -1, horizontal ? -1 : tail);
        }

        public void begin_drag (TileBoard source, string id) {
            drag_source = source; drag_id = id; drag_committed = false;
            if (new_group_zone != null) { new_group_zone.opacity = 1; new_group_zone.can_target = true; }
            drag_state_changed (true);
        }
        public bool is_cross_drag (TileBoard destination, string id) {
            return drag_source != null && drag_source != destination && drag_id == id;
        }
        public bool source_matches (string id) { return drag_source != null && drag_id == id; }
        public GenericArray<TileConfig>? preview_drop (TileBoard destination, string id, int boundary, string? folder) {
            if (drag_committed) return null;
            if (is_cross_drag (destination, id)) {
                GenericArray<TileConfig> remaining;
                var source = drag_source.drag_model.detached_source (id, out remaining);
                return source == null ? null : destination.drag_model.preview_receive (source, boundary, folder);
            }
            // External app/Dock payloads may add missing apps, never duplicate
            // an existing app from a different launcher group.
            if (drag_source == null && !id.has_prefix ("folder:")) {
                for (uint i = 0; i < boards.length; i++)
                    if (boards[i] != destination && boards[i].drag_model.contains_app (id)) return null;
            }
            bool allow_new = app.app_provider.find_by_desktop_id (id) != null;
            return folder == null ? destination.drag_model.preview_insert (id, boundary, allow_new) :
                destination.drag_model.preview_folder_insert (folder, id, boundary, allow_new);
        }
        public bool commit_drop (TileBoard destination, string id, GenericArray<TileConfig> candidate) {
            if (drag_committed) return false;
            if (is_cross_drag (destination, id)) {
                GenericArray<TileConfig> remaining;
                if (drag_source.drag_model.detached_source (id, out remaining) == null) return false;
                // Both independent candidates have been validated before either
                // live model is replaced; no signals/saves between replacements.
                drag_source.apply_drag_candidate (remaining);
                destination.apply_drag_candidate (candidate);
                destination.show_committed_preview (drag_source.drag_image);
                drag_source.commit_source_transfer ();
                drag_committed = true;
                rebuild_pending = true;
                save_layout (drag_source);
                return true;
            }
            bool changed = destination.drag_model.commit_candidate (candidate);
            if (changed) {
                if (source_matches (id)) destination.show_committed_preview (drag_source.drag_image);
                save_layout ();
            }
            return changed;
        }
        public void end_drag (TileBoard board) {
            if (board == drag_source) {
                drag_source = null; drag_id = null; drag_committed = false;
                if (new_group_zone != null) {
                    if (new_group_preview == null) new_group_zone.opacity = 0;
                    new_group_zone.can_target = false;
                    new_group_zone.remove_css_class ("drop-active");
                }
            }
            // A destination can still be finishing after the source's drag-end.
            // Notify again when the final board settles, including cancellation
            // paths that do not request a root rebuild.
            if (drag_source == null && !other_board_dragging ())
                drag_state_changed (false);
            schedule_rebuild ();
        }

        private void schedule_rebuild () {
            if (!rebuild_pending || other_board_dragging () || rebuild_idle != 0) return;
            weak TileGrid owner = this;
            // Coalesce drag-end notifications and run before GTK redraw, while
            // still leaving the GtkDragSource signal stack before destruction.
            rebuild_idle = Idle.add (() => {
                var grid = owner;
                if (grid != null) {
                    grid.rebuild_idle = 0;
                    if (grid.rebuild_pending && !grid.other_board_dragging ()) grid.build_from_config ();
                }
                return Source.REMOVE;
            }, Priority.HIGH_IDLE);
        }

        private Gtk.Popover? group_popover;
        public signal void tile_activated (AppEntry entry);
        public signal void pin_requested (string desktop_id);
        public signal void unpin_requested (string desktop_id);

        public TileGrid (Application app) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 16);
            this.app = app;
            add_css_class ("tile-grid");
            hexpand = true;
            vexpand = true;
            margin_top = 16;
            margin_bottom = 16;
            build_from_config ();
        }

        public bool other_board_dragging (TileBoard? except = null) {
            for (uint i = 0; i < boards.length; i++)
                if (boards[i] != except && boards[i].drag_in_progress) return true;
            return false;
        }

        public void build_from_config () {
            if (other_board_dragging ()) { rebuild_pending = true; return; }
            layout_changing (true);
            rebuild_pending = false;
            // Horizontal boards share the same content height. Seed replacement
            // boards with that allocation, not the startup fallback; an interim
            // two-row layout would change scroll bounds for one frame.
            if (orientation == Gtk.Orientation.HORIZONTAL) {
                for (uint i = 0; i < boards.length; i++) {
                    int height = boards[i].get_height ();
                    if (height > 0) { last_board_height = height; break; }
                }
            }
            for (uint i = 0; i < boards.length; i++) boards[i].cleanup ();
            boards = new GenericArray<TileBoard> ();
            names = new GenericArray<string> ();
            if (group_popover != null) { group_popover.unparent (); group_popover = null; }
            new_group_zone = null;
            new_group_preview = null;
            while (get_first_child () != null) remove (get_first_child ());
            orientation = horizontal_groups ?
                Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL;
            if (orientation == Gtk.Orientation.HORIZONTAL) add_css_class ("horizontal-groups");
            else remove_css_class ("horizontal-groups");
            // Boards own deep snapshots. ALL catalog entries are transient;
            // only explicitly edited/moved entries become launcher pins.
            var groups = new GenericArray<GroupConfig> ();
            if (app.config.groups != null) {
                for (uint i = 0; i < app.config.groups.length; i++) {
                    var original = app.config.groups[i];
                    var copy = new GroupConfig (original.name);
                    for (uint j = 0; j < original.tiles.length; j++) {
                        var tc = original.tiles[j];
                        var tile = new TileConfig (tc.desktop_id, tc.size);
                        tile.folder_name = tc.folder_name;
                        if (tc.folder_items != null) {
                            tile.folder_items = new GenericArray<string> ();
                            for (uint k = 0; k < tc.folder_items.length; k++) tile.folder_items.add (tc.folder_items[k]);
                        }
                        copy.tiles.add (tile);
                    }
                    groups.add (copy);
                }
            }
            if (!app.config.groups_enabled && groups.length > 0) {
                var flat = new GroupConfig ("");
                var folder_names = new HashTable<string, bool> (str_hash, str_equal);
                for (uint i = 0; i < groups.length; i++) {
                    for (uint j = 0; j < groups[i].tiles.length; j++) {
                        var tile = groups[i].tiles[j];
                        if (tile.size == TileSize.FOLDER) {
                            string original = tile.folder_name ?? _("Folder");
                            string name = original;
                            int suffix = 2;
                            while (folder_names.contains (name)) name = "%s (%d)".printf (original, suffix++);
                            tile.folder_name = name;
                            tile.desktop_id = "folder:" + name;
                            folder_names.insert (name, true);
                        }
                        flat.tiles.add (tile);
                    }
                }
                groups = new GenericArray<GroupConfig> ();
                groups.add (flat);
            }
            if (groups.length == 0) groups.add (new GroupConfig (""));
            int default_index = -1;
            var known = new HashTable<string, bool> (str_hash, str_equal);
            for (uint i = 0; i < groups.length; i++) {
                if (groups[i].name == "" && default_index < 0) default_index = (int) i;
                for (uint j = 0; j < groups[i].tiles.length; j++) {
                    var tc = groups[i].tiles[j];
                    if (tc.size != TileSize.FOLDER) known.insert (tc.desktop_id, true);
                    if (tc.folder_items != null)
                        for (uint k = 0; k < tc.folder_items.length; k++) known.insert (tc.folder_items[k], true);
                }
            }
            if (app.config.tile_mode == TileMode.ALL) {
                var apps = app.app_provider.apps;
                for (uint i = 0; i < apps.length; i++) {
                    if (known.contains (apps[i].desktop_id)) continue;
                    // Create a catalog shelf only when an unrepresented app
                    // needs it; never resurrect an emptied group otherwise.
                    if (default_index < 0) { default_index = (int) groups.length; groups.add (new GroupConfig ("")); }
                    var tile = new TileConfig (apps[i].desktop_id, TileSize.SMALL);
                    tile.transient = true;
                    groups[default_index].tiles.add (tile);
                }
            }
            for (uint i = 0; i < groups.length; i++) {
                uint index = i;
                var section = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
                section.add_css_class ("tile-group");
                section.hexpand = !horizontal_groups;
                section.valign = horizontal_groups ? Gtk.Align.FILL : Gtk.Align.START;
                if (app.config.groups_enabled) {
                    var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
                    header.add_css_class ("tile-group-header");
                    header.margin_start = GridPacker.MIN_MARGIN;
                    header.margin_end = GridPacker.MIN_MARGIN;
                    var title = new Gtk.Label (groups[i].name == "" ? _("Applications") : groups[i].name);
                    title.add_css_class ("heading");
                    title.hexpand = true;
                    title.ellipsize = Pango.EllipsizeMode.END;
                    title.xalign = 0;
                    header.append (title);
                    var actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
                    actions.add_css_class ("tile-group-actions");
                    actions.opacity = 0;
                    actions.can_target = false;
                    var fade = new Adw.TimedAnimation (header, 0, 0, 150,
                        new Adw.PropertyAnimationTarget (actions, "opacity"));
                    fade.easing = Adw.Easing.EASE_OUT_CUBIC;
                    var motion = new Gtk.EventControllerMotion ();
                    var focus = new Gtk.EventControllerFocus ();
                    motion.enter.connect (() => fade_group_actions (actions, fade, true));
                    motion.leave.connect (() => fade_group_actions (actions, fade, focus.contains_focus));
                    focus.enter.connect (() => fade_group_actions (actions, fade, true));
                    focus.leave.connect (() => fade_group_actions (actions, fade, motion.contains_pointer));
                    header.add_controller (motion);
                    header.add_controller (focus);
                    var rename = new Gtk.Button.from_icon_name ("document-edit-symbolic");
                    rename.add_css_class ("flat");
                    rename.tooltip_text = _("Rename group");
                    rename.clicked.connect (() => name_editor (rename, groups[index].name, (text) => {
                        save_layout (); app.config.groups[index].name = text; persist_rebuild ();
                    }));
                    actions.append (rename);
                    var folder = new Gtk.Button.from_icon_name ("folder-new-symbolic");
                    folder.add_css_class ("flat");
                    folder.tooltip_text = _("Create Folder");
                    folder.clicked.connect (() => name_editor (folder, _("Folder"), (text) => {
                        save_layout ();
                        var model = new TileModel (app.config.groups[index].tiles);
                        if (model.has_folder (text)) return;
                        model.tiles.add (new TileConfig.folder (text, new GenericArray<string> ()));
                        persist_rebuild ();
                    }));
                    actions.append (folder);
                    var create = new Gtk.Button.from_icon_name ("list-add-symbolic");
                    create.add_css_class ("flat");
                    create.tooltip_text = _("Create group");
                    create.clicked.connect (() => name_editor (create, "", (text) => {
                        save_layout (); app.config.groups.add (new GroupConfig (text)); persist_rebuild ();
                    }));
                    header.append (actions);
                    if (groups.length == 1 && groups[index].tiles.length == 0)
                        header.append (create);
                    else
                        actions.append (create);
                    section.append (header);
                }
                var board = new TileBoard (app, groups[i].tiles, last_board_height);
                board.group_grid = this;
                board.vexpand = horizontal_groups;
                boards.add (board); names.add (groups[i].name);
                weak TileGrid weak_grid = this;
                board.tile_activated.connect ((e) => { var grid = weak_grid; if (grid != null) grid.tile_activated (e); });
                board.pin_requested.connect ((id) => { var grid = weak_grid; if (grid != null) grid.pin_requested (id); });
                board.unpin_requested.connect ((id) => { var grid = weak_grid; if (grid != null) grid.unpin_requested (id); });
                board.layout_changed.connect (() => { var grid = weak_grid; if (grid != null) grid.save_layout (); });
                board.layout_changing.connect ((active) => { var grid = weak_grid; if (grid != null) grid.layout_changing (active); });
                board.extend_menu.connect ((menu, popover, id) => { var grid = weak_grid; if (grid != null) grid.extend_tile_menu (index, menu, popover, id); });
                board.drag_finished.connect (() => {
                    var grid = weak_grid;
                    if (grid != null) grid.schedule_rebuild ();
                });
                section.append (board);
                append (section);
            }
            if (app.config.groups_enabled) append_new_group_zone ();
            layout_changing (false);
        }

        private void append_new_group_zone () {
            var zone = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            zone.add_css_class ("new-group-drop-zone");
            // Keep the tail in measurement even outside DnD, so users can
            // scroll beyond the last group before starting a drag.
            zone.opacity = 0;
            zone.can_target = false;
            bool horizontal = horizontal_groups;
            zone.set_size_request (horizontal ? 160 : -1, horizontal ? -1 : 72);
            zone.hexpand = !horizontal;
            zone.vexpand = horizontal;
            var label = new Gtk.Label (_("New group"));
            label.hexpand = true;
            label.vexpand = true;
            zone.append (label);
            var target = new Gtk.DropTarget (typeof (string), Gdk.DragAction.MOVE);
            target.preload = true;
            weak TileGrid owner = this;
            weak Gtk.Box hover_zone = zone;
            target.accept.connect (() => owner != null && owner.drag_source != null && !owner.drag_committed);
            target.enter.connect (() => {
                if (owner == null || owner.drag_source == null || owner.drag_committed) return (Gdk.DragAction) 0;
                if (hover_zone != null) hover_zone.add_css_class ("drop-active");
                return Gdk.DragAction.MOVE;
            });
            target.leave.connect (() => { if (hover_zone != null) hover_zone.remove_css_class ("drop-active"); });
            target.drop.connect ((value, x, y) => {
                var grid = owner;
                string? id = value.get_string ();
                return grid != null && id != null && grid.commit_new_group (id);
            });
            zone.add_controller (target);
            new_group_zone = zone;
            set_drop_viewport_size (drop_viewport_width, drop_viewport_height);
            append (zone);
        }

        private bool commit_new_group (string id) {
            if (drag_committed || !source_matches (id)) return false;
            GenericArray<TileConfig> remaining;
            var tile = drag_source.drag_model.detached_source (id, out remaining);
            if (tile == null) return false;
            // Create no live board yet: keep the GtkDragSource alive through
            // drag_end and commit the removal/new group with exactly one save.
            drag_source.apply_drag_candidate (remaining);
            drag_source.commit_source_transfer ();
            var groups = collect_layout (drag_source);
            var group = new GroupConfig (_("Group"));
            tile.transient = false;
            group.tiles.add (tile);
            groups.add (group);
            if (new_group_zone != null && drag_source.drag_image != null) {
                var label = new_group_zone.get_first_child ();
                if (label != null) { label.vexpand = false; label.halign = Gtk.Align.START; }
                var image = drag_source.drag_image;
                new_group_preview = new Gtk.Picture.for_paintable (image);
                new_group_preview.can_shrink = true;
                new_group_preview.can_target = false;
                new_group_preview.halign = Gtk.Align.START;
                new_group_preview.valign = Gtk.Align.START;
                new_group_preview.set_size_request (int.max (1, image.get_intrinsic_width ()), int.max (1, image.get_intrinsic_height ()));
                new_group_zone.append (new_group_preview);
            }
            drag_committed = true;
            rebuild_pending = true;
            app.config.groups = groups;
            app.config.save ();
            return true;
        }

        private static void fade_group_actions (Gtk.Widget actions, Adw.TimedAnimation fade, bool visible) {
            double destination = visible ? 1.0 : 0.0;
            actions.can_target = visible;
            if (fade.value_to == destination && fade.state == Adw.AnimationState.PLAYING) return;
            fade.pause ();
            // Reverse a running fade from the current opacity, without jumping.
            fade.value_from = actions.opacity;
            fade.value_to = destination;
            // Adw.Animation respects gtk-enable-animations automatically.
            fade.play ();
        }

        private delegate void NameAccepted (string text);
        private void name_editor (Gtk.Widget anchor, string initial, owned NameAccepted accepted) {
            if (other_board_dragging ()) return;
            var popover = new Gtk.Popover ();
            popover.set_parent (anchor);
            group_popover = popover;
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            var entry = new Gtk.Entry (); entry.text = initial;
            var ok = new Gtk.Button.with_label (_("OK"));
            box.append (entry); box.append (ok); popover.set_child (box);
            ok.clicked.connect (() => {
                var text = entry.text.strip ();
                if (text == "" || other_board_dragging ()) return;
                popover.popdown ();
                // Allow GTK to close/unparent the popover before replacing boards.
                Idle.add (() => { if (!other_board_dragging ()) accepted (text); return Source.REMOVE; });
            });
            entry.activate.connect (() => ok.clicked ());
            popover.closed.connect (() => { if (group_popover == popover) group_popover = null; popover.unparent (); });
            popover.popup (); entry.grab_focus ();
        }

        private void extend_tile_menu (uint source, Gtk.Box menu, Gtk.Popover popover, string id) {
            if (!id.has_prefix ("folder:")) {
                bool pinned = app.config.is_pinned_in_launcher (id);
                var pin = new Gtk.Button.with_label (pinned ? _("Unpin from Launcher") : _("Pin to Launcher"));
                pin.add_css_class ("flat");
                pin.clicked.connect (() => {
                    popover.popdown ();
                    Idle.add (() => {
                        if (!other_board_dragging ()) {
                            if (pinned) app.config.unpin_from_launcher (id);
                            else app.config.pin_in_launcher (id);
                        }
                        return Source.REMOVE;
                    });
                });
                menu.append (pin);
            }
            for (uint i = 0; i < boards.length; i++) {
                if (i == source) continue;
                uint destination = i;
                var move = new Gtk.Button.with_label (_("Move to group: %s").printf (names[i] == "" ? _("Applications") : names[i]));
                move.add_css_class ("flat");
                move.clicked.connect (() => {
                    popover.popdown ();
                    Idle.add (() => { move_tile (source, destination, id, false); return Source.REMOVE; });
                });
                menu.append (move);
            }
            if (app.config.groups_enabled && id.has_prefix ("folder:")) {
                var convert = new Gtk.Button.with_label (_("Convert folder to group"));
                convert.add_css_class ("flat");
                convert.clicked.connect (() => {
                    popover.popdown ();
                    Idle.add (() => { move_tile (source, 0, id, true); return Source.REMOVE; });
                });
                menu.append (convert);
            }
        }

        private void move_tile (uint source, uint destination, string id, bool convert) {
            if (other_board_dragging ()) return;
            if (source >= boards.length) return;
            var snapshot = new TileModel (boards[source].to_config (names[source], true).tiles);
            int snapshot_index = snapshot.find_index (id);
            GenericArray<TileConfig> remaining;
            bool emptied_source = snapshot.detached_source (id, out remaining) != null && remaining.length == 0;
            TileConfig? tile = snapshot_index >= 0 ? snapshot.tiles[snapshot_index] : null;
            save_layout ();
            var groups = app.config.groups;
            if (source >= groups.length || (!convert && destination >= groups.length)) return;
            var model = new TileModel (groups[source].tiles);
            int index = model.find_index (id);
            if (index >= 0) tile = model.tiles[index];
            if (convert) {
                if (tile == null || tile.size != TileSize.FOLDER) return;
                var group = new GroupConfig (tile.folder_name ?? _("Group"));
                if (tile.folder_items != null)
                    for (uint i = 0; i < tile.folder_items.length; i++) group.tiles.add (new TileConfig (tile.folder_items[i], TileSize.SMALL));
                if (index >= 0) model.tiles.remove_index (index);
                groups.add (group);
            } else {
                var target = new TileModel (groups[destination].tiles);
                if (target.find_index (id) >= 0) return;
                if (tile != null && tile.size == TileSize.FOLDER && target.has_folder (tile.folder_name)) return;
                if (index >= 0) model.tiles.remove_index (index);
                else {
                    for (uint i = 0; i < model.tiles.length && tile == null; i++) {
                        var items = model.tiles[i].folder_items;
                        if (items == null) continue;
                        for (uint j = 0; j < items.length; j++) if (items[j] == id) {
                            items.remove_index (j); tile = new TileConfig (id, TileSize.SMALL); break;
                        }
                    }
                }
                if (tile == null) return;
                target.tiles.add (tile);
            }
            // Preserve intentionally empty groups and transient catalog items.
            if (emptied_source) groups.remove_index (source);
            persist_rebuild ();
        }

        private void persist_rebuild () { app.config.save (); build_from_config (); }
        private GenericArray<GroupConfig> collect_layout (TileBoard? emptied_source = null) {
            var groups = new GenericArray<GroupConfig> ();
            for (uint i = 0; i < boards.length; i++) {
                if (boards[i] == emptied_source && boards[i].drag_model.tiles.length == 0) continue;
                groups.add (boards[i].to_config (names[i]));
            }
            return groups;
        }
        public void save_layout (TileBoard? emptied_source = null) {
            app.config.groups = collect_layout (emptied_source);
            app.config.save ();
        }
        private TileBoard? focused_board () {
            var window = get_root () as Gtk.Window;
            var focus = window != null ? window.get_focus () : null;
            if (focus != null) {
                for (uint i = 0; i < boards.length; i++)
                    if (focus == boards[i] || focus.is_ancestor (boards[i])) return boards[i];
            }
            for (uint i = 0; i < boards.length; i++) if (boards[i].get_focused_index () >= 0 || boards[i].get_active_popover () != null) return boards[i];
            return boards.length > 0 ? boards[0] : null;
        }
        public void extract_from_open_folder (string id) { for (uint i = 0; i < boards.length; i++) if (boards[i].has_open_folder ()) boards[i].try_extract_from_folder (id); }
        public void focus_first_tile () { for (uint i = 0; i < boards.length; i++) if (boards[i].focus_first ()) return; }
        public bool is_at_top_row () { var b = focused_board (); return b == null || (b == boards[0] && b.get_focused_y () < 10); }
        public void clear_other_focus (TileBoard board) {
            for (uint i = 0; i < boards.length; i++) if (boards[i] != board) boards[i].clear_tile_focus ();
        }
        public void gamepad_navigate (int dx, int dy) { navigate_groups (dx, dy); }
        public bool navigate_groups (int dx, int dy) {
            var b = focused_board (); if (b == null) return false;
            if (b.navigate_focus (dx, dy)) return true;
            int direction = orientation == Gtk.Orientation.HORIZONTAL ? dx : dy;
            if (direction == 0) return false;
            for (uint i = 0; i < boards.length; i++) if (boards[i] == b) {
                int next = (int) i + (direction > 0 ? 1 : -1);
                while (next >= 0 && next < boards.length) { if (boards[next].focus_first ()) return true; next += direction > 0 ? 1 : -1; }
                break;
            }
            return false;
        }
        public void gamepad_activate () { var b = focused_board (); if (b != null) b.activate_focused (); }
        public bool has_open_folder () { for (uint i = 0; i < boards.length; i++) if (boards[i].has_open_folder ()) return true; return false; }
        public Gtk.Popover? get_active_popover () { if (group_popover != null) return group_popover; for (uint i = 0; i < boards.length; i++) { var p = boards[i].get_active_popover (); if (p != null) return p; } return null; }
        public void gamepad_context_menu () { var b = focused_board (); if (b != null) b.show_focused_context_menu (); }
        public void gamepad_close_folder () { for (uint i = 0; i < boards.length; i++) boards[i].close_open_folder (); }
    }
}
