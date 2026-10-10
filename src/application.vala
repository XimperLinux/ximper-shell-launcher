namespace XimperShellLauncher {

    public class Application : Adw.Application {

        public ConfigManager config { get; private set; }
        public AppProvider app_provider { get; private set; }
        public LaunchHistory launch_history { get; private set; }
        public DockClient dock_client { get; private set; }
        public CompositorHelper compositor_helper { get; private set; }

        private GridWindow? grid_window;
        private LauncherDBusService? dbus_service;
        private GamepadController? gamepad;

        private OptionEntry[] options;

        public Application () {
            Object (
                application_id: "ru.ximperlinux.shell.Launcher",
                flags: ApplicationFlags.HANDLES_COMMAND_LINE
            );
            options = {
                { "toggle", 't', 0, OptionArg.NONE, null, _("Toggle the application launcher"), null },
                { "reload", 0, 0, OptionArg.NONE, null, _("Reload configuration from disk"), null },
                {
                    "describe", 0, 0, OptionArg.NONE, null,
                    _("Print configuration and parameter metadata as JSON"), null
                },
                { "preset", 0, 0, OptionArg.STRING, null, _("Apply a preset, replacing the current tile layout"), "NAME" },
                { "list-presets", 0, 0, OptionArg.NONE, null, _("List available presets"), null },
                { null }
            };
            add_main_option_entries (options);
        }

        private static string? preset_option_error (VariantDict options) {
            string? name = null;
            if (!options.lookup ("preset", "s", out name)) return null;
            if (name == null || !Presets.is_valid (name))
                return _("Invalid preset. Expected exactly: 8.1, 10, ximper, wofi.\n");
            if (options.contains ("describe") || options.contains ("reload") || options.contains ("list-presets"))
                return _("--preset cannot be combined with --describe, --reload or --list-presets.\n");
            return null;
        }

        protected override int handle_local_options (VariantDict options) {
            // Runs before registration/startup: invalid requests cannot create config.
            string? error = preset_option_error (options);
            if (error != null) {
                stderr.printf ("%s", error);
                return 1;
            }
            if (options.contains ("list-presets")) {
                stdout.printf ("%s", Presets.list_description ());
                return 0;
            }
            return -1;
        }

        protected override void startup () {
            base.startup ();

            config = new ConfigManager ();
            config.load ();

            app_provider = new AppProvider ();
            app_provider.scan ();

            launch_history = new LaunchHistory ();

            dock_client = new DockClient ();
            if (NiriHelper.is_available ()) {
                compositor_helper = new NiriHelper ();
            } else {
                compositor_helper = new HyprlandHelper ();
            }
            message ("Using %s compositor helper", compositor_helper.name);

            load_css ();
        }

        protected override bool dbus_register (DBusConnection conn, string object_path) throws Error {
            base.dbus_register (conn, object_path);
            dbus_service = new LauncherDBusService (this);
            conn.register_object ("/ru/ximperlinux/shell/Launcher", dbus_service);
            return true;
        }

        protected override int command_line (ApplicationCommandLine cmdline) {
            var options = cmdline.get_options_dict ();

            string? error = preset_option_error (options);
            if (error != null) {
                cmdline.printerr ("%s", error);
                return 1;
            }
            string? preset = null;
            if (options.lookup ("preset", "s", out preset)) {
                if (grid_window != null && grid_window.layout_busy) {
                    cmdline.printerr ("%s", _("Cannot apply a preset while a tile drag is active.\n"));
                    return 1;
                }
                // Preserve unrelated settings as currently saved on disk,
                // even if an external editor changed them since startup.
                config.load ();
                app_provider.scan ();
                Presets.apply (preset, config, app_provider.apps);
                config.save ();
                if (grid_window != null) {
                    grid_window.settle_transition ();
                    grid_window.reload_from_config ();
                }
                cmdline.print (_("Preset '%s' applied; the previous tile layout was replaced.\n"), preset);
                activate ();
                if (options.contains ("toggle")) toggle_grid ();
                return 0;
            }

            if (options.contains ("describe")) {
                cmdline.print ("%s", describe_json (config));
                return 0;
            }

            activate ();

            if (options.contains ("toggle")) {
                toggle_grid ();
                return 0;
            }

            if (options.contains ("reload")) {
                reload_config ();
                return 0;
            }

            return 0;
        }

        public void toggle_grid () {
            if (grid_window == null) return;
            grid_window.toggle_menu ();
        }

        public void reload_config () {
            if (grid_window != null) grid_window.settle_transition ();
            config.load ();
            app_provider.scan ();
            if (grid_window != null)
                grid_window.reload_from_config ();
        }

        protected override void activate () {
            if (grid_window != null) return;

            grid_window = new GridWindow (this);
            add_window (grid_window);

            gamepad = new GamepadController (grid_window);
            gamepad.device_connected_notify.connect ((name) => {
                grid_window.show_toast (_("Gamepad connected: ") + name);
            });
        }

        public void pin_to_dock (string desktop_id) {
            dock_client.pin (desktop_id);
        }

        public void unpin_from_dock (string desktop_id) {
            dock_client.unpin (desktop_id);
        }

        public bool is_dock_running () {
            return dock_client.is_available ();
        }

        public bool is_pinned_in_dock (string desktop_id) {
            return dock_client.is_pinned (desktop_id);
        }

        private void load_css () {
            var css_provider = new Gtk.CssProvider ();

            string css_path = Path.build_filename (
                Environment.get_user_data_dir (), "ximper-shell-launcher", "ximper-shell-launcher.css"
            );

            if (FileUtils.test (css_path, FileTest.EXISTS)) {
                css_provider.load_from_path (css_path);
            } else {
                string system_css = Path.build_filename (
                    "/etc", "xdg", "ximper-shell", "launcher", "style.css"
                );
                if (FileUtils.test (system_css, FileTest.EXISTS)) {
                    css_provider.load_from_path (system_css);
                } else {
                    try {
                        string self_path = FileUtils.read_link ("/proc/self/exe");
                        string bin_dir = Path.get_dirname (self_path);
                        string local_css = Path.build_filename (
                            bin_dir, "..", "..", "data", "ximper-shell-launcher.css"
                        );
                        if (FileUtils.test (local_css, FileTest.EXISTS)) {
                            css_provider.load_from_path (local_css);
                        }
                    } catch (FileError e) {}
                }
            }

            Gtk.StyleContext.add_provider_for_display (
                Gdk.Display.get_default (),
                css_provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );

            // Prefer Launcher CSS, but keep existing Tile Menu customizations working.
            string user_css = Path.build_filename (
                Environment.get_user_config_dir (), "ximper-shell", "launcher", "style.css"
            );
            if (!FileUtils.test (user_css, FileTest.EXISTS)) {
                user_css = Path.build_filename (
                    Environment.get_user_config_dir (), "ximper-shell", "tile-menu", "style.css"
                );
            }
            if (FileUtils.test (user_css, FileTest.EXISTS)) {
                var user_provider = new Gtk.CssProvider ();
                user_provider.load_from_path (user_css);
                Gtk.StyleContext.add_provider_for_display (
                    Gdk.Display.get_default (),
                    user_provider,
                    Gtk.STYLE_PROVIDER_PRIORITY_USER
                );
            }
        }
    }
}
