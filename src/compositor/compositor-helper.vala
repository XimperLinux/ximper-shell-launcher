namespace XimperShellLauncher {

    public abstract class CompositorHelper : Object {
        public abstract string name { owned get; }
        public abstract string? get_active_monitor_connector ();
    }
}
