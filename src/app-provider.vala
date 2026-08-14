namespace XimperShellLauncher {

    public class AppProvider : Object {

        public GenericArray<AppEntry> apps;

        private AppInfoMonitor monitor;

        public signal void apps_changed ();

        public AppProvider () {
            apps = new GenericArray<AppEntry> ();
        }

        public void scan () {
            apps = new GenericArray<AppEntry> ();

            var all_apps = AppInfo.get_all ();
            foreach (var info in all_apps) {
                if (info is DesktopAppInfo) {
                    var dinfo = (DesktopAppInfo) info;
                    if (dinfo.should_show ()) {
                        apps.add (new AppEntry (dinfo));
                    }
                }
            }

            apps.sort ((a, b) => {
                return a.name.collate (b.name);
            });

            if (monitor == null) {
                monitor = AppInfoMonitor.get ();
                monitor.changed.connect (() => {
                    scan ();
                    apps_changed ();
                });
            }
        }

        public GenericArray<AppEntry> search (string query) {
            var scored = new GenericArray<AppEntry> ();
            var scores = new GenericArray<int> ();

            for (uint i = 0; i < apps.length; i++) {
                int s = apps[i].match_score (query);
                if (s > 0) {
                    scored.add (apps[i]);
                    scores.add (s);
                }
            }

            // Sort by score descending
            for (int i = 0; i < (int) scored.length - 1; i++) {
                for (int j = i + 1; j < (int) scored.length; j++) {
                    if (scores[j] > scores[i]) {
                        var tmp_e = scored[i]; scored[i] = scored[j]; scored[j] = tmp_e;
                        var tmp_s = scores[i]; scores[i] = scores[j]; scores[j] = tmp_s;
                    }
                }
            }

            return scored;
        }

        public AppEntry? find_by_desktop_id (string desktop_id) {
            for (uint i = 0; i < apps.length; i++) {
                if (apps[i].desktop_id == desktop_id) {
                    return apps[i];
                }
            }
            return null;
        }
    }
}
