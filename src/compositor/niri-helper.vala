namespace XimperShellLauncher {

    public class NiriHelper : CompositorHelper {

        public override string name { owned get { return "Niri"; } }

        public static bool is_available () {
            var socket = Environment.get_variable ("NIRI_SOCKET");
            return socket != null && socket.length > 0 && FileUtils.test (socket, FileTest.EXISTS);
        }

        public override string? get_active_monitor_connector () {
            try {
                string stdout_buf;
                int exit_status;

                Process.spawn_command_line_sync (
                    "niri msg --json workspaces",
                    out stdout_buf,
                    null,
                    out exit_status
                );

                if (exit_status != 0 || stdout_buf == null || stdout_buf.length == 0) {
                    return null;
                }

                var parser = new Json.Parser ();
                parser.load_from_data (stdout_buf);

                string? active_output = null;
                var array = parser.get_root ().get_array ();
                array.foreach_element ((arr, idx, node) => {
                    if (active_output != null) return;

                    var obj = node.get_object ();
                    if (!obj.has_member ("is_focused") || !obj.get_boolean_member ("is_focused")) return;
                    if (!obj.has_member ("output")) return;
                    if (obj.get_member ("output").get_node_type () == Json.NodeType.NULL) return;

                    active_output = obj.get_string_member ("output");
                });

                return active_output;
            } catch (Error e) {
                return null;
            }
        }
    }
}
