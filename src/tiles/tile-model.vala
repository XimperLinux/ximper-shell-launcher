namespace XimperShellLauncher {

    public class TileModel {

        public GenericArray<TileConfig> tiles;

        public TileModel (GenericArray<TileConfig> tiles) {
            this.tiles = tiles;
        }

        public int find_index (string id) {
            for (uint i = 0; i < tiles.length; i++) {
                if (id.has_prefix ("folder:")) {
                    if (tiles[i].size == TileSize.FOLDER &&
                        tiles[i].folder_name == id.substring ("folder:".length))
                        return (int) i;
                } else {
                    if (tiles[i].desktop_id == id && tiles[i].size != TileSize.FOLDER)
                        return (int) i;
                }
            }
            return -1;
        }

        public TileConfig? find_folder (string name) {
            for (uint i = 0; i < tiles.length; i++) {
                if (tiles[i].size == TileSize.FOLDER && tiles[i].folder_name == name)
                    return tiles[i];
            }
            return null;
        }

        public bool has_folder (string name) {
            for (uint i = 0; i < tiles.length; i++) {
                if (tiles[i].size == TileSize.FOLDER &&
                    tiles[i].folder_name == name &&
                    tiles[i].folder_items != null)
                    return true;
            }
            return false;
        }

        public int count_folder_items (string name, AppProvider provider) {
            var fc = find_folder (name);
            if (fc == null || fc.folder_items == null) return 0;
            int count = 0;
            for (uint i = 0; i < fc.folder_items.length; i++) {
                if (provider.find_by_desktop_id (fc.folder_items[i]) != null)
                    count++;
            }
            return count;
        }

        public GenericArray<TileConfig> copy_tiles () {
            var result = new GenericArray<TileConfig> ();
            for (uint i = 0; i < tiles.length; i++) {
                var tc = new TileConfig (tiles[i].desktop_id, tiles[i].size);
                tc.folder_name = tiles[i].folder_name;
                tc.transient = tiles[i].transient;
                if (tiles[i].folder_items != null) {
                    tc.folder_items = new GenericArray<string> ();
                    for (uint j = 0; j < tiles[i].folder_items.length; j++)
                        tc.folder_items.add (tiles[i].folder_items[j]);
                }
                result.add (tc);
            }
            return result;
        }

        // Remove only from the private candidate. Report any removed top-level index.
        private TileConfig? take_source (GenericArray<TileConfig> candidate, string id,
                                        out int removed_index) {
            removed_index = -1;
            int index = find_index (id);
            if (index >= 0) {
                var source = candidate[index];
                candidate.remove_index (index);
                removed_index = index;
                return source;
            }
            if (id.has_prefix ("folder:")) return null;
            for (uint i = 0; i < candidate.length; i++) {
                var folder = candidate[i];
                if (folder.size != TileSize.FOLDER || folder.folder_items == null) continue;
                for (uint j = 0; j < folder.folder_items.length; j++) {
                    if (folder.folder_items[j] != id) continue;
                    folder.folder_items.remove_index (j);
                    return new TileConfig (id, TileSize.SMALL);
                }
            }
            return null;
        }

        public TileConfig? detached_source (string id, out GenericArray<TileConfig> remaining) {
            remaining = copy_tiles ();
            int removed;
            return take_source (remaining, id, out removed);
        }

        public bool contains_app (string id) {
            if (find_index (id) >= 0) return true;
            for (uint i = 0; i < tiles.length; i++) {
                var items = tiles[i].folder_items;
                for (uint j = 0; items != null && j < items.length; j++)
                    if (items[j] == id) return true;
            }
            return false;
        }

        public GenericArray<TileConfig>? preview_receive (TileConfig source, int boundary, string? folder_name) {
            if (source.size == TileSize.FOLDER) {
                // Folder names identify widgets within one board; reject a
                // collision rather than silently merging unrelated folders.
                if (folder_name != null || find_folder (source.folder_name ?? "") != null) return null;
                if (source.folder_items != null)
                    for (uint i = 0; i < source.folder_items.length; i++)
                        if (contains_app (source.folder_items[i])) return null;
            } else if (contains_app (source.desktop_id)) return null;
            var candidate = copy_tiles ();
            source.transient = false;
            if (folder_name == null) {
                if (boundary < 0 || boundary > candidate.length) return null;
                candidate.insert (boundary, source);
            } else {
                if (source.size == TileSize.FOLDER) return null;
                TileConfig? folder = null;
                for (uint i = 0; i < candidate.length; i++)
                    if (candidate[i].size == TileSize.FOLDER && candidate[i].folder_name == folder_name) folder = candidate[i];
                if (folder == null) return null;
                if (folder.folder_items == null) folder.folder_items = new GenericArray<string> ();
                if (boundary < 0 || boundary > folder.folder_items.length) return null;
                folder.folder_items.insert (boundary, source.desktop_id);
            }
            return candidate;
        }

        // Boundary is an index in the ORIGINAL live array, not the candidate.
        public GenericArray<TileConfig>? preview_insert (string source_id, int boundary,
                                                        bool allow_new = false) {
            if (boundary < 0 || boundary > (int) tiles.length) return null;
            var candidate = copy_tiles ();
            int removed;
            var source = take_source (candidate, source_id, out removed);
            if (source == null) {
                if (!allow_new || source_id.has_prefix ("folder:")) return null;
                source = new TileConfig (source_id, TileSize.SMALL);
            }
            if (removed >= 0 && removed < boundary) boundary--;
            source.transient = false;
            candidate.insert (boundary, source);
            return candidate;
        }

        public GenericArray<TileConfig>? preview_folder_insert (string folder_name,
                                                               string source_id, int boundary,
                                                               bool allow_new = false) {
            var target = find_folder (folder_name);
            if (target == null || source_id.has_prefix ("folder:")) return null;
            int length = target.folder_items == null ? 0 : (int) target.folder_items.length;
            if (boundary < 0 || boundary > length) return null;
            int source_item = -1;
            if (target.folder_items != null) {
                for (uint j = 0; j < target.folder_items.length; j++)
                    if (target.folder_items[j] == source_id) source_item = (int) j;
            }
            var candidate = copy_tiles ();
            TileConfig? destination = null;
            for (uint i = 0; i < candidate.length; i++)
                if (candidate[i].size == TileSize.FOLDER && candidate[i].folder_name == folder_name)
                    destination = candidate[i];
            // Reordering within the destination must retain even a one-item folder.
            if (source_item >= 0) {
                destination.folder_items.remove_index (source_item);
                if (source_item < boundary) boundary--;
            } else {
                int removed;
                if (take_source (candidate, source_id, out removed) == null && !allow_new) return null;
            }
            if (destination.folder_items == null)
                destination.folder_items = new GenericArray<string> ();
            destination.folder_items.insert (boundary, source_id);
            return candidate;
        }

        public bool commit_candidate (GenericArray<TileConfig>? candidate) {
            if (candidate == null) return false;
            bool same = candidate.length == tiles.length;
            for (uint i = 0; same && i < tiles.length; i++) {
                var a = tiles[i];
                var b = candidate[i];
                same = a.desktop_id == b.desktop_id && a.size == b.size && a.folder_name == b.folder_name && a.transient == b.transient;
                if ((a.folder_items == null) != (b.folder_items == null)) same = false;
                if (same && a.folder_items != null && b.folder_items != null) {
                    same = a.folder_items.length == b.folder_items.length;
                    for (uint j = 0; same && j < a.folder_items.length; j++)
                        same = a.folder_items[j] == b.folder_items[j];
                }
            }
            if (same) return false;
            tiles = candidate;
            return true;
        }

        // --- Mutations (return true if data changed) ---

        public bool handle_drop (string source_id, string target_id) {
            if (target_id.has_prefix ("folder:") && !source_id.has_prefix ("folder:")) {
                return add_to_folder (target_id.substring ("folder:".length), source_id);
            }

            int boundary = find_index (target_id);
            if (boundary < 0) return false;
            return commit_candidate (preview_insert (source_id, boundary));
        }

        public bool add_to_folder (string folder_name, string desktop_id) {
            var folder = find_folder (folder_name);
            if (folder == null) return false;
            int boundary = folder.folder_items == null ? 0 : (int) folder.folder_items.length;
            return commit_candidate (preview_folder_insert (folder_name, desktop_id, boundary));
        }

        public bool remove_from_folder (string folder_name, string desktop_id) {
            var folder = find_folder (folder_name);
            if (folder == null || folder.folder_items == null) return false;
            for (uint j = 0; j < folder.folder_items.length; j++) {
                if (folder.folder_items[j] == desktop_id)
                    return commit_candidate (preview_insert (desktop_id, (int) tiles.length));
            }
            return false;
        }

        public bool ungroup_folder (string folder_name) {
            int folder_idx = -1;
            GenericArray<string>? items = null;

            for (uint i = 0; i < tiles.length; i++) {
                if (tiles[i].size == TileSize.FOLDER && tiles[i].folder_name == folder_name) {
                    folder_idx = (int) i;
                    items = tiles[i].folder_items;
                    break;
                }
            }
            if (folder_idx < 0) return false;

            tiles.remove_index (folder_idx);

            if (items != null) {
                for (int i = (int) items.length - 1; i >= 0; i--) {
                    tiles.insert (folder_idx, new TileConfig (items[i], TileSize.SMALL));
                }
            }
            return true;
        }

        public bool rename_folder (string old_name, string new_name) {
            if (old_name != new_name && has_folder (new_name)) return false;
            for (uint i = 0; i < tiles.length; i++) {
                if (tiles[i].size == TileSize.FOLDER && tiles[i].folder_name == old_name) {
                    tiles[i].folder_name = new_name;
                    tiles[i].desktop_id = "folder:" + new_name;
                    return true;
                }
            }
            return false;
        }

        public bool reorder_in_folder (string folder_name, string id_a, string id_b) {
            for (uint i = 0; i < tiles.length; i++) {
                var tc = tiles[i];
                if (tc.size == TileSize.FOLDER && tc.folder_name == folder_name && tc.folder_items != null) {
                    int idx_a = -1, idx_b = -1;
                    for (uint j = 0; j < tc.folder_items.length; j++) {
                        if (tc.folder_items[j] == id_a) idx_a = (int) j;
                        if (tc.folder_items[j] == id_b) idx_b = (int) j;
                    }
                    if (idx_a >= 0 && idx_b >= 0)
                        return commit_candidate (preview_folder_insert (folder_name, id_a, idx_b));
                    break;
                }
            }
            return false;
        }

        public bool change_tile_size (string desktop_id, TileSize new_size) {
            for (uint i = 0; i < tiles.length; i++) {
                if (tiles[i].desktop_id == desktop_id) {
                    tiles[i] = new TileConfig (desktop_id, new_size);
                    return true;
                }
            }
            return false;
        }

        public bool remove_tile (string desktop_id) {
            for (uint i = 0; i < tiles.length; i++) {
                if (tiles[i].desktop_id == desktop_id) {
                    tiles.remove_index (i);
                    return true;
                }
            }
            return false;
        }

        public bool create_folder (string desktop_id, string app_name) {
            int idx = -1;
            for (uint i = 0; i < tiles.length; i++) {
                if (tiles[i].desktop_id == desktop_id && tiles[i].size != TileSize.FOLDER) {
                    idx = (int) i;
                    break;
                }
            }
            if (idx < 0) return false;

            tiles.remove_index (idx);

            var items = new GenericArray<string> ();
            items.add (desktop_id);
            string name = app_name;
            int suffix = 2;
            while (has_folder (name)) name = "%s (%d)".printf (app_name, suffix++);
            tiles.insert (idx, new TileConfig.folder (name, items));
            return true;
        }

        public bool purge_missing (AppProvider provider) {
            bool changed = false;

            // Remove missing apps from folder items
            for (uint i = 0; i < tiles.length; i++) {
                var tc = tiles[i];
                if (tc.folder_items == null) continue;
                for (int j = (int) tc.folder_items.length - 1; j >= 0; j--) {
                    if (provider.find_by_desktop_id (tc.folder_items[j]) == null) {
                        tc.folder_items.remove_index (j);
                        changed = true;
                    }
                }
            }

            // Remove standalone tiles for missing apps
            for (int i = (int) tiles.length - 1; i >= 0; i--) {
                var tc = tiles[i];
                if (tc.size == TileSize.FOLDER) continue;
                if (provider.find_by_desktop_id (tc.desktop_id) == null) {
                    tiles.remove_index (i);
                    changed = true;
                }
            }

            return changed;
        }

        public GroupConfig to_group_config (string group_name, bool include_transient = false) {
            var config = new GroupConfig (group_name);
            for (uint i = 0; i < tiles.length; i++) {
                if (tiles[i].transient && !include_transient) continue;
                var tc = new TileConfig (tiles[i].desktop_id, tiles[i].size);
                tc.folder_name = tiles[i].folder_name;
                if (tiles[i].folder_items != null) {
                    tc.folder_items = new GenericArray<string> ();
                    for (uint j = 0; j < tiles[i].folder_items.length; j++)
                        tc.folder_items.add (tiles[i].folder_items[j]);
                }
                config.tiles.add (tc);
            }
            return config;
        }
    }
}
