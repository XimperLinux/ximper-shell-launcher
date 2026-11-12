using XimperShellLauncher;

private void test_save_layout_after_external_edit () {
    try {
        var dir = DirUtils.make_tmp ("ximper-launcher-merge-XXXXXX");
        Environment.set_variable ("XDG_CONFIG_HOME", dir, true);
        var config = new ConfigManager ();
        DirUtils.create_with_parents (Path.get_dirname (config.config_file), 0700);
        FileUtils.set_contents (config.config_file, "{\"cell_size\":32,\"groups\":[]}");
        config.load ();
        FileUtils.set_contents (config.config_file, "{\"cell_size\":64,\"groups\":[],\"extra\":true}");
        config.pin_in_launcher ("app.desktop");

        var parser = new Json.Parser ();
        parser.load_from_file (config.config_file);
        var obj = parser.get_root ().get_object ();
        assert (obj.get_int_member ("cell_size") == 64);
        assert (obj.get_boolean_member ("extra"));
        assert (obj.get_array_member ("groups").get_length () == 1);
    } catch (Error e) {
        error ("%s", e.message);
    }
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/config/save-layout-after-external-edit", test_save_layout_after_external_edit);
    return Test.run ();
}
