namespace XimperShellLauncher {

    public class TileModel {

        public GenericArray<TileConfig> tiles;

        public TileModel (GenericArray<TileConfig> tiles) {
            this.tiles = tiles;
        }

        public int find_index (string id) {
            for (uint i = 0; i < tiles.length; i++) {
                if (id.has_prefix ("folder:")) {
                    if (tiles[i].folder_name == id.substring ("folder:".length))
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
                    tiles[i].folder_items != null &&
                    tiles[i].folder_items.length > 0)
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

        // --- Mutations (return true if data changed) ---

        public bool handle_drop (string source_id, string target_id) {
            if (target_id.has_prefix ("folder:") && !source_id.has_prefix ("folder:")) {
                return add_to_folder (target_id.substring ("folder:".length), source_id);
            }

            // If source is inside a folder, extract it first
            int idx_a = find_index (source_id);
            if (idx_a < 0 && !source_id.has_prefix ("folder:")) {
                extract_from_any_folder (source_id);
                idx_a = find_index (source_id);
            }

            int idx_b = find_index (target_id);
            if (idx_a >= 0 && idx_b >= 0 && idx_a != idx_b) {
                var tmp = tiles[idx_a];
                tiles[idx_a] = tiles[idx_b];
                tiles[idx_b] = tmp;
                return true;
            }
            return false;
        }

        private void extract_from_any_folder (string desktop_id) {
            for (uint i = 0; i < tiles.length; i++) {
                var tc = tiles[i];
                if (tc.size != TileSize.FOLDER || tc.folder_items == null) continue;
                for (uint j = 0; j < tc.folder_items.length; j++) {
                    if (tc.folder_items[j] == desktop_id) {
                        tc.folder_items.remove_index (j);
                        if (tc.folder_items.length == 0) {
                            tiles.remove_index (i);
                        }
                        tiles.add (new TileConfig (desktop_id, TileSize.SMALL));
                        return;
                    }
                }
            }
        }

        public bool add_to_folder (string folder_name, string desktop_id) {
            for (uint i = 0; i < tiles.length; i++) {
                var tc = tiles[i];
                if (tc.size == TileSize.FOLDER && tc.folder_name == folder_name && tc.folder_items != null) {
                    // Already in folder?
                    for (uint j = 0; j < tc.folder_items.length; j++) {
                        if (tc.folder_items[j] == desktop_id) return false;
                    }
                    tc.folder_items.add (desktop_id);
                    break;
                }
            }
            // Remove standalone tile
            for (uint i = 0; i < tiles.length; i++) {
                if (tiles[i].desktop_id == desktop_id && tiles[i].size != TileSize.FOLDER) {
                    tiles.remove_index (i);
                    break;
                }
            }
            return true;
        }

        public bool remove_from_folder (string folder_name, string desktop_id) {
            for (uint i = 0; i < tiles.length; i++) {
                var tc = tiles[i];
                if (tc.size == TileSize.FOLDER && tc.folder_name == folder_name && tc.folder_items != null) {
                    for (uint j = 0; j < tc.folder_items.length; j++) {
                        if (tc.folder_items[j] == desktop_id) {
                            tc.folder_items.remove_index (j);
                            break;
                        }
                    }
                    // Remove empty folder
                    if (tc.folder_items.length == 0) {
                        tiles.remove_index (i);
                    }
                    break;
                }
            }
            // Add as standalone tile
            tiles.add (new TileConfig (desktop_id, TileSize.SMALL));
            return true;
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
                    if (idx_a >= 0 && idx_b >= 0 && idx_a != idx_b) {
                        var tmp = tc.folder_items[idx_a];
                        tc.folder_items[idx_a] = tc.folder_items[idx_b];
                        tc.folder_items[idx_b] = tmp;
                        return true;
                    }
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
            tiles.insert (idx, new TileConfig.folder (app_name, items));
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
                // If folder has fewer than 2 items, ungroup
                if (tc.size == TileSize.FOLDER && tc.folder_items.length < 2) {
                    var insert_pos = (int) i + 1;
                    for (uint k = 0; k < tc.folder_items.length; k++) {
                        tiles.insert (insert_pos, new TileConfig (tc.folder_items[k], TileSize.SMALL));
                        insert_pos++;
                    }
                    tiles.remove_index (i);
                    changed = true;
                    i--;
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

        public GroupConfig to_group_config (string group_name) {
            var config = new GroupConfig (group_name);
            for (uint i = 0; i < tiles.length; i++) {
                var tc = new TileConfig (tiles[i].desktop_id, tiles[i].size);
                tc.folder_name = tiles[i].folder_name;
                tc.folder_items = tiles[i].folder_items;
                config.tiles.add (tc);
            }
            return config;
        }
    }
}
