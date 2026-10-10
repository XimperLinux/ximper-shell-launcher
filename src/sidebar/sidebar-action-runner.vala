namespace XimperShellLauncher {
    public class SidebarActionRunner : Object {
        public signal void failed (string label, string detail);

        private static void detach_child () { c_setsid (); }

        private static void observe_child (SidebarActionRunner runner, Pid pid, string label) {
            var reference = new SidebarWeakReference (runner);
            ChildWatch.add (pid, (child, status) => {
                Process.close_pid (child);
                try { Process.check_wait_status (status); }
                catch (Error e) {
                    var owner = reference.get () as SidebarActionRunner;
                    if (owner != null) owner.failed (label, _("Command finished unsuccessfully"));
                }
            });
        }

        public async bool launch (SidebarItem item, Cancellable cancel) {
            if (cancel.is_cancelled () || !item.valid) return false;
            string label = item.display_label ();
            try {
                switch (item.kind) {
                    case SidebarItemKind.COMMAND:
                        // Copy before crossing any asynchronous boundary. No shell
                        // parsing/substitution; DO_NOT_REAP_CHILD is paired with watch.
                        string[] argv = {};
                        foreach (string arg in item.argv) argv += arg;
                        string? cwd = item.cwd != "" ? SidebarItem.local_path (item.cwd) : null;
                        Pid pid;
                        Process.spawn_async (cwd, argv, null,
                            SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
                            detach_child, out pid);
                        observe_child (this, pid, label);
                        return true;
                    case SidebarItemKind.APPLICATION:
                        var info = new DesktopAppInfo (item.desktop_id);
                        if (info == null) throw new IOError.NOT_FOUND ("Missing application");
                        var entry = new AppEntry (info);
                        if (!entry.launch ()) throw new IOError.FAILED ("Launch failed");
                        return true;
                    case SidebarItemKind.FOLDER:
                        var path = SidebarItem.local_path (item.path);
                        if (path == null) throw new IOError.INVALID_ARGUMENT ("Invalid folder");
                        var file = File.new_for_path (path);
                        var details = yield file.query_info_async (FileAttribute.STANDARD_TYPE,
                            FileQueryInfoFlags.NONE, Priority.DEFAULT, cancel);
                        if (details.get_file_type () != FileType.DIRECTORY)
                            throw new IOError.NOT_DIRECTORY ("Not a directory");
                        if (cancel.is_cancelled ()) return false;
                        var display = Gdk.Display.get_default ();
                        AppLaunchContext? context = display != null ? display.get_app_launch_context () : null;
                        yield AppInfo.launch_default_for_uri_async (file.get_uri (), context, cancel);
                        return true;
                    default:
                        return false;
                }
            } catch (Error e) {
                // Error messages may contain a full private path/command. Keep
                // notifications useful without exposing arguments or URI data.
                if (!cancel.is_cancelled ()) failed (label, _("Could not start action"));
                return false;
            }
        }
    }
}
