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

    var app = new XimperShellTileMenu.Application ();
    return app.run (args);
}
