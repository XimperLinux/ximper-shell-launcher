namespace XimperShellLauncher {

    public string describe_json (ConfigManager config) {
        var builder = new Json.Builder ();
        builder.begin_object ();
        builder.set_member_name ("config");
        builder.begin_object ();
        builder.set_member_name ("max_columns");
        builder.add_int_value (config.max_columns);
        builder.set_member_name ("cell_size");
        builder.add_int_value (config.cell_size);
        builder.set_member_name ("layer");
        builder.add_string_value (config.layer);
        builder.set_member_name ("launcher_mode");
        builder.add_string_value (config.launcher_mode.to_string ());
        builder.set_member_name ("window_mode");
        builder.add_string_value (config.window_mode.to_string ());
        builder.set_member_name ("close_on_focus_loss");
        builder.add_boolean_value (config.close_on_focus_loss);
        builder.set_member_name ("floating_x");
        builder.add_int_value (config.floating_x);
        builder.set_member_name ("floating_y");
        builder.add_int_value (config.floating_y);
        builder.set_member_name ("floating_width");
        builder.add_int_value (config.floating_width);
        builder.set_member_name ("floating_height");
        builder.add_int_value (config.floating_height);
        builder.set_member_name ("floating_x_percent");
        builder.add_int_value (config.floating_x_percent);
        builder.set_member_name ("floating_y_percent");
        builder.add_int_value (config.floating_y_percent);
        builder.set_member_name ("output");
        builder.begin_array ();
        for (uint i = 0; i < config.output.length; i++) {
            builder.add_string_value (config.output[i]);
        }
        builder.end_array ();
        builder.set_member_name ("wallpaper_path");
        builder.add_string_value (config.wallpaper_path);
        builder.set_member_name ("wallpaper_fit");
        builder.add_int_value (config.wallpaper_fit);
        builder.set_member_name ("wallpaper_opacity");
        builder.add_int_value (config.wallpaper_opacity);
        builder.set_member_name ("wallpaper_dim");
        builder.add_int_value (config.wallpaper_dim);
        builder.set_member_name ("background_opacity");
        builder.add_int_value (config.background_opacity);
        builder.set_member_name ("search_providers_enabled");
        builder.add_boolean_value (config.search_providers_enabled);
        builder.set_member_name ("groups");
        builder.begin_array ();
        for (uint i = 0; i < config.groups.length; i++) {
            var group = config.groups[i];
            builder.begin_object ();
            builder.set_member_name ("name");
            builder.add_string_value (group.name);
            builder.set_member_name ("tiles");
            builder.begin_array ();
            for (uint j = 0; j < group.tiles.length; j++) {
                var tile = group.tiles[j];
                builder.begin_object ();
                builder.set_member_name ("desktop_id");
                builder.add_string_value (tile.desktop_id);
                builder.set_member_name ("size");
                builder.add_string_value (tile.size.to_string ());
                if (tile.folder_name != null) {
                    builder.set_member_name ("folder_name");
                    builder.add_string_value (tile.folder_name);
                }
                if (tile.folder_items != null) {
                    builder.set_member_name ("folder_items");
                    builder.begin_array ();
                    for (uint k = 0; k < tile.folder_items.length; k++) {
                        builder.add_string_value (tile.folder_items[k]);
                    }
                    builder.end_array ();
                }
                builder.end_object ();
            }
            builder.end_array ();
            builder.end_object ();
        }
        builder.end_array ();
        builder.end_object ();

        builder.set_member_name ("runtime");
        builder.begin_object ();
        builder.set_member_name ("running");
        builder.add_boolean_value (true);
        builder.end_object ();
        builder.set_member_name ("paths");
        builder.begin_object ();
        builder.set_member_name ("config");
        builder.add_string_value (config.config_file);
        builder.end_object ();

        builder.set_member_name ("metadata");
        builder.begin_object ();
        builder.set_member_name ("properties");
        builder.begin_object ();
        add_integer_property (
            builder, "max_columns", "Maximum columns (0 = automatic)", 0, 0, 20
        );
        add_integer_property (
            builder, "cell_size", "Tile cell size (0 = automatic)", 0, 0, 512
        );
        add_enum_property (
            builder, "layer", "Layer-shell layer", "overlay",
            { "background", "bottom", "top", "overlay" }
        );
        add_enum_property (
            builder, "launcher_mode", "Launcher mode", "tiles", { "tiles", "wofi" }
        );
        add_enum_property (
            builder, "window_mode", "Window mode", "floating", { "floating", "fullscreen" }
        );
        add_boolean_property (builder, "close_on_focus_loss", "Close on focus loss", true);
        add_integer_property (builder, "floating_x", "Floating X offset", 0, -10000, 10000);
        add_integer_property (builder, "floating_y", "Floating Y offset", 24, -10000, 10000);
        add_integer_property (builder, "floating_width", "Floating width", 1120, 1, 10000);
        add_integer_property (builder, "floating_height", "Floating height", 880, 1, 10000);
        add_integer_property (
            builder, "floating_x_percent", "Floating horizontal position", 50, 0, 100
        );
        add_integer_property (
            builder, "floating_y_percent", "Floating vertical position", 50, 0, 100
        );
        add_integer_property (builder, "wallpaper_fit", "Wallpaper fit", 2, 0, 3);
        add_integer_property (builder, "wallpaper_opacity", "Wallpaper opacity", 100, 0, 100);
        add_integer_property (builder, "wallpaper_dim", "Wallpaper dimming", 0, 0, 100);
        add_integer_property (builder, "background_opacity", "Background opacity", 100, 0, 100);
        add_boolean_property (
            builder, "search_providers_enabled", "Enable search providers", true
        );
        add_string_property (builder, "wallpaper_path", "Wallpaper path", "");
        builder.end_object ();
        builder.end_object ();
        builder.end_object ();

        var generator = new Json.Generator ();
        generator.set_root (builder.get_root ());
        generator.set_pretty (true);
        return generator.to_data (null) + "\n";
    }

    private void add_property (Json.Builder builder, string name, string title, string type) {
        builder.set_member_name (name);
        builder.begin_object ();
        builder.set_member_name ("title");
        builder.add_string_value (title);
        builder.set_member_name ("type");
        builder.add_string_value (type);
    }

    private void add_boolean_property (
        Json.Builder builder,
        string name,
        string title,
        bool default_value
    ) {
        add_property (builder, name, title, "boolean");
        builder.set_member_name ("default");
        builder.add_boolean_value (default_value);
        builder.end_object ();
    }

    private void add_string_property (
        Json.Builder builder,
        string name,
        string title,
        string default_value
    ) {
        add_property (builder, name, title, "string");
        builder.set_member_name ("default");
        builder.add_string_value (default_value);
        builder.end_object ();
    }

    private void add_enum_property (
        Json.Builder builder,
        string name,
        string title,
        string default_value,
        string[] values
    ) {
        add_property (builder, name, title, "string");
        builder.set_member_name ("default");
        builder.add_string_value (default_value);
        builder.set_member_name ("enum");
        builder.begin_array ();
        foreach (var value in values) {
            builder.add_string_value (value);
        }
        builder.end_array ();
        builder.end_object ();
    }

    private void add_integer_property (
        Json.Builder builder,
        string name,
        string title,
        int default_value,
        int minimum,
        int maximum
    ) {
        add_property (builder, name, title, "integer");
        builder.set_member_name ("default");
        builder.add_int_value (default_value);
        builder.set_member_name ("minimum");
        builder.add_int_value (minimum);
        builder.set_member_name ("maximum");
        builder.add_int_value (maximum);
        builder.end_object ();
    }
}
