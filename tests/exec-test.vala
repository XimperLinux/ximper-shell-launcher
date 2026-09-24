using XimperShellLauncher;

[DBus (name = "org.freedesktop.Application")]
private class FakeApplication : Object {
    public bool activated = false;
    public void activate (HashTable<string, Variant> platform_data) {
        activated = true;
    }
}

private void test_field_codes () {
    assert (AppEntry.strip_field_codes ("program --format=%% --file=%f") ==
        "program --format=% --file=");
}

private string write_desktop (string dir, string basename, string marker) throws Error {
    var desktop = Path.build_filename (dir, basename);
    FileUtils.set_contents (desktop, "[Desktop Entry]\nType=Application\nName=Test launcher\n" +
        "Exec=/usr/bin/touch " + marker + " %U\nDBusActivatable=true\n");
    return desktop;
}

private bool wait_for_file (string path, bool iterate_main_context) {
    for (int i = 0; i < 250 && !FileUtils.test (path, FileTest.EXISTS); i++) {
        if (iterate_main_context)
            while (MainContext.default ().iteration (false)) {}
        Thread.usleep (20000);
    }
    return FileUtils.test (path, FileTest.EXISTS);
}

private void test_invalid_dbus_name () {
    try {
        var dir = DirUtils.make_tmp ("ximper-launcher-exec-test-XXXXXX");
        var marker = Path.build_filename (dir, "launched");
        var info = new DesktopAppInfo.from_filename (write_desktop (dir, "max.desktop", marker));
        assert (info != null);
        assert (new AppEntry (info).launch ());
        assert (wait_for_file (marker, false));
    } catch (Error e) {
        error ("Test setup failed: %s", e.message);
    }
}

private void test_missing_service () {
    try {
        var dir = DirUtils.make_tmp ("ximper-launcher-bus-test-XXXXXX");
        var marker = Path.build_filename (dir, "fallback-launched");
        var basename = "org.ximperlinux.LauncherTest_" +
            Uuid.string_random ().replace ("-", "_") + ".desktop";
        var info = new DesktopAppInfo.from_filename (write_desktop (dir, basename, marker));
        assert (info != null);
        Test.expect_message (null, LogLevelFlags.LEVEL_WARNING,
            "*D-Bus activation failed*falling back to Exec*");
        assert (new AppEntry (info).launch ());
        assert (wait_for_file (marker, true));
        Test.assert_expected_messages ();
    } catch (Error e) {
        error ("Test setup failed: %s", e.message);
    }
}

private void test_desktop_filename_fallback () {
    try {
        var dir = DirUtils.make_tmp ("ximper-launcher-filename-test-XXXXXX");
        var desktop = Path.build_filename (dir,
            "org.ximperlinux.LauncherFilenameTest_" + Uuid.string_random ().replace ("-", "_") + ".desktop");
        var marker = Path.build_filename (dir, "copied-desktop");
        FileUtils.set_contents (desktop, "[Desktop Entry]\nType=Application\nName=Test filename\n" +
            "Exec=/usr/bin/cp %k " + marker + "\nDBusActivatable=true\n");
        var info = new DesktopAppInfo.from_filename (desktop);
        assert (info != null);
        Test.expect_message (null, LogLevelFlags.LEVEL_WARNING,
            "*D-Bus activation failed*falling back to Exec*");
        assert (new AppEntry (info).launch ());
        assert (wait_for_file (marker, true));
        string copied;
        FileUtils.get_contents (marker, out copied);
        assert (copied.contains ("DBusActivatable=true"));
        Test.assert_expected_messages ();
    } catch (Error e) {
        error ("Filename test failed: %s", e.message);
    }
}

private void test_valid_dbus_activation () {
    try {
        var dir = DirUtils.make_tmp ("ximper-launcher-valid-bus-test-XXXXXX");
        var desktop = Path.build_filename (dir, "org.ximperlinux.LaunchTestService.desktop");
        var marker = Path.build_filename (dir, "exec-should-not-run");
        FileUtils.set_contents (desktop, "[Desktop Entry]\nType=Application\nName=Test valid D-Bus\n" +
            "Exec=/usr/bin/touch " + marker + "\nDBusActivatable=true\n");
        var conn = Bus.get_sync (BusType.SESSION);
        var service = new FakeApplication ();
        var registration = conn.register_object ("/org/ximperlinux/LaunchTestService", service);
        conn.call_sync ("org.freedesktop.DBus", "/org/freedesktop/DBus",
            "org.freedesktop.DBus", "RequestName",
            new Variant ("(su)", "org.ximperlinux.LaunchTestService", 0u),
            new VariantType ("(u)"), DBusCallFlags.NONE, 1000);
        var info = new DesktopAppInfo.from_filename (desktop);
        assert (info != null);
        assert (new AppEntry (info).launch ());
        for (int i = 0; i < 100 && !service.activated; i++) {
            while (MainContext.default ().iteration (false)) {}
            Thread.usleep (20000);
        }
        assert (service.activated);
        assert (!FileUtils.test (marker, FileTest.EXISTS));
        conn.unregister_object (registration);
    } catch (Error e) {
        error ("D-Bus test setup failed: %s", e.message);
    }
}

int main (string[] args) {
    Test.init (ref args);
    var bus = new TestDBus (TestDBusFlags.NONE);
    bus.up ();
    Test.add_func ("/desktop-entry/exec-field-codes", test_field_codes);
    Test.add_func ("/desktop-entry/invalid-dbus-name", test_invalid_dbus_name);
    Test.add_func ("/desktop-entry/missing-service", test_missing_service);
    Test.add_func ("/desktop-entry/filename-fallback", test_desktop_filename_fallback);
    Test.add_func ("/desktop-entry/valid-dbus-activation", test_valid_dbus_activation);
    var result = Test.run ();
    bus.down ();
    return result;
}
