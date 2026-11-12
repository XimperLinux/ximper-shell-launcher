int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "");
    string locale_dir = BuildConfig.LOCALEDIR;
    try {
        string self_path = FileUtils.read_link ("/proc/self/exe");
        string build_locale_dir = Path.build_filename (
            Path.get_dirname (self_path), "..", "po"
        );
        string translation = Path.build_filename (
            build_locale_dir, "ru", "LC_MESSAGES", BuildConfig.GETTEXT_PACKAGE + ".mo"
        );
        if (FileUtils.test (translation, FileTest.EXISTS)) locale_dir = build_locale_dir;
    } catch (FileError e) {}
    Intl.bindtextdomain (BuildConfig.GETTEXT_PACKAGE, locale_dir);
    Intl.bind_textdomain_codeset (BuildConfig.GETTEXT_PACKAGE, "UTF-8");
    Intl.textdomain (BuildConfig.GETTEXT_PACKAGE);

    if (args.length == 2 && args[1] == "--describe") {
        try {
            var config = new XimperShellLauncher.ConfigManager ();
            config.load_config (false);
            bool running = false;
            try {
                var bus = Bus.get_sync (BusType.SESSION);
                var reply = bus.call_sync ("org.freedesktop.DBus", "/org/freedesktop/DBus",
                    "org.freedesktop.DBus", "NameHasOwner",
                    new Variant ("(s)", "ru.ximperlinux.shell.Launcher"),
                    new VariantType ("(b)"), DBusCallFlags.NONE, 1000);
                reply.get ("(b)", out running);
            } catch (Error e) {
                // Offline configuration is available without a session bus.
            }
            stdout.printf ("%s", XimperShellLauncher.describe_json (config, running));
            return 0;
        } catch (Error e) {
            stderr.printf ("%s\n", e.message);
            return 1;
        }
    }

    var app = new XimperShellLauncher.Application ();
    return app.run (args);
}
