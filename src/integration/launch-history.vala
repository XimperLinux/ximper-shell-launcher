namespace XimperShellLauncher {

    public class LaunchHistory : Object {

        private GenericArray<string> desktop_ids;
        private GenericArray<int> launch_counts;
        private string history_path;

        public LaunchHistory () {
            desktop_ids = new GenericArray<string> ();
            launch_counts = new GenericArray<int> ();
            history_path = Path.build_filename (
                Environment.get_user_data_dir (), "ximper-shell", "launcher", "launch-history.json"
            );
            load ();
        }

        public int get_count (string desktop_id) {
            for (uint i = 0; i < desktop_ids.length; i++) {
                if (desktop_ids[i] == desktop_id) return launch_counts[i];
            }
            return 0;
        }

        public void record_launch (string desktop_id) {
            if (desktop_id.length == 0) return;

            for (uint i = 0; i < desktop_ids.length; i++) {
                if (desktop_ids[i] == desktop_id) {
                    launch_counts[i] = launch_counts[i] + 1;
                    save ();
                    return;
                }
            }

            desktop_ids.add (desktop_id);
            launch_counts.add (1);
            save ();
        }

        private void load () {
            desktop_ids = new GenericArray<string> ();
            launch_counts = new GenericArray<int> ();

            if (!FileUtils.test (history_path, FileTest.EXISTS)) return;

            try {
                var parser = new Json.Parser ();
                parser.load_from_file (history_path);

                var root = parser.get_root ().get_object ();
                if (!root.has_member ("apps")) return;

                var apps = root.get_object_member ("apps");
                foreach (var id in apps.get_members ()) {
                    int64 count = apps.get_int_member (id);
                    if (id != null && id.length > 0 && count > 0) {
                        desktop_ids.add (id);
                        launch_counts.add ((int) count);
                    }
                }
            } catch (Error e) {
                warning ("Failed to load launch history: %s", e.message);
            }
        }

        private void save () {
            var builder = new Json.Builder ();

            builder.begin_object ();
            builder.set_member_name ("apps");
            builder.begin_object ();
            for (uint i = 0; i < desktop_ids.length; i++) {
                builder.set_member_name (desktop_ids[i]);
                builder.add_int_value (launch_counts[i]);
            }
            builder.end_object ();
            builder.end_object ();

            var generator = new Json.Generator ();
            generator.set_root (builder.get_root ());
            generator.pretty = true;
            generator.indent = 2;

            try {
                DirUtils.create_with_parents (Path.get_dirname (history_path), 0755);
                generator.to_file (history_path);
            } catch (Error e) {
                warning ("Failed to save launch history: %s", e.message);
            }
        }
    }
}
