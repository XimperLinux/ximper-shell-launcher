namespace XimperShellTileMenu {

    public class HyprlandHelper : CompositorHelper {

        public override string name { owned get { return "Hyprland"; } }

        public override string? get_active_monitor_connector () {
            try {
                string stdout_buf;
                int exit_status;

                Process.spawn_command_line_sync (
                    "hyprctl activeworkspace -j",
                    out stdout_buf,
                    null,
                    out exit_status
                );

                if (exit_status != 0 || stdout_buf == null || stdout_buf.length == 0) {
                    return null;
                }

                var parser = new Json.Parser ();
                parser.load_from_data (stdout_buf);
                var root = parser.get_root ().get_object ();
                if (!root.has_member ("monitor")) return null;

                return root.get_string_member ("monitor");
            } catch (Error e) {
                return null;
            }
        }
    }
}
