namespace XimperShellLauncher {

    public string describe_json (ConfigManager config, bool running = true) {
        var provider_manager = new SearchProviderManager (config);
        provider_manager.scan_providers (true);

        var builder = new Json.Builder ();
        builder.begin_object ();
        builder.set_member_name ("api_version");
        builder.add_int_value (1);
        builder.set_member_name ("write_protocol");
        builder.add_string_value ("locked-json-v1");
        if (!FileUtils.test (config.config_file, FileTest.EXISTS)) {
            builder.set_member_name ("initial_config");
            builder.add_value (config.initial_document ());
        }
        builder.set_member_name ("config");
        builder.begin_object ();
        builder.set_member_name ("max_columns");
        builder.add_int_value (config.max_columns);
        builder.set_member_name ("cell_size");
        builder.add_int_value (config.cell_size);
        builder.set_member_name ("tile_icon_size");
        builder.add_int_value (config.tile_icon_size);
        builder.set_member_name ("tile_square_labels");
        builder.add_boolean_value (config.tile_square_labels);
        builder.set_member_name ("layer");
        builder.add_string_value (config.layer);
        builder.set_member_name ("launcher_mode");
        builder.add_string_value (config.launcher_mode.to_string ());
        builder.set_member_name ("tile_mode");
        builder.add_string_value (config.tile_mode.to_string ());
        builder.set_member_name ("group_layout");
        builder.add_string_value (config.group_layout.to_string ());
        builder.set_member_name ("groups_enabled");
        builder.add_boolean_value (config.groups_enabled);
        builder.set_member_name ("app_list_side");
        builder.add_string_value (config.app_list_side.to_string ());
        builder.set_member_name ("app_list_sort");
        builder.add_string_value (config.app_list_sort.to_string ());
        builder.set_member_name ("search_sort");
        builder.add_string_value (config.search_sort.to_string ());
        builder.set_member_name ("window_mode");
        builder.add_string_value (config.window_mode.to_string ());
        builder.set_member_name ("close_on_focus_loss");
        builder.add_boolean_value (config.close_on_focus_loss);
        builder.set_member_name ("floating_position");
        builder.add_string_value (config.floating_position.to_string ());
        builder.set_member_name ("floating_margin");
        builder.add_int_value (config.floating_margin);
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
        builder.set_member_name ("animation_open");
        config.animation_open.serialize (builder);
        builder.set_member_name ("animation_hide");
        config.animation_hide.serialize (builder);
        builder.set_member_name ("search_providers_enabled");
        builder.add_boolean_value (config.search_providers_enabled);
        builder.set_member_name ("search_providers");
        add_config_search_provider_array (builder, config);
        builder.set_member_name ("sidebar");
        config.sidebar.serialize (builder, false);
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
        builder.add_boolean_value (running);
        builder.end_object ();
        builder.set_member_name ("paths");
        builder.begin_object ();
        builder.set_member_name ("config");
        builder.add_string_value (config.config_file);
        builder.end_object ();

        builder.set_member_name ("metadata");
        builder.begin_object ();
        builder.set_member_name ("search_providers");
        add_search_provider_array (builder, provider_manager.providers);
        builder.set_member_name ("storage_paths");
        builder.begin_object ();
        builder.set_member_name ("search_providers");
        builder.begin_array (); builder.add_string_value ("search"); builder.add_string_value ("providers"); builder.end_array ();
        builder.end_object ();
        // Additive schema namespace: existing flat property consumers are unchanged.
        builder.set_member_name ("object_properties");
        builder.begin_object ();
        add_animation_schema (builder, "animation_open", AnimationProfile.opening ());
        add_animation_schema (builder, "animation_hide", AnimationProfile.hiding ());
        add_sidebar_schema (builder);
        builder.end_object ();
        builder.set_member_name ("properties");
        builder.begin_object ();
        builder.set_member_name ("output");
        builder.begin_object ();
        builder.set_member_name ("type"); builder.add_string_value ("array");
        builder.set_member_name ("items"); builder.begin_object ();
        builder.set_member_name ("type"); builder.add_string_value ("string"); builder.end_object ();
        builder.end_object ();
        builder.set_member_name ("groups");
        builder.begin_object ();
        builder.set_member_name ("type"); builder.add_string_value ("array");
        builder.set_member_name ("items"); builder.begin_object ();
        builder.set_member_name ("type"); builder.add_string_value ("object"); builder.end_object ();
        builder.set_member_name ("readOnly"); builder.add_boolean_value (true);
        builder.end_object ();
        builder.set_member_name ("search_providers");
        builder.begin_object ();
        builder.set_member_name ("type"); builder.add_string_value ("array");
        builder.set_member_name ("items"); builder.begin_object ();
        builder.set_member_name ("type"); builder.add_string_value ("object"); builder.end_object ();
        builder.end_object ();
        add_integer_property (
            builder, "max_columns", "Maximum columns (0 = automatic)", 0, 0, 20
        );
        add_integer_property (
            builder, "cell_size", "Tile cell size (0 = automatic)", 0, 0, 512
        );
        add_integer_property (builder, "tile_icon_size", "Tile icon size (0 = automatic)", 0, 0, 128);
        add_boolean_property (builder, "tile_square_labels", "Show names on square tiles", false);
        add_boolean_property (builder, "groups_enabled", "Show tile groups", true);
        add_enum_property (
            builder, "layer", "Layer-shell layer", "overlay",
            { "background", "bottom", "top", "overlay" }
        );
        add_enum_property (
            builder, "launcher_mode", "Launcher mode", "tiles", { "tiles", "wofi", "combined" }
        );
        add_enum_property (
            builder, "tile_mode", "Tile mode", "all", { "all", "pinned" }
        );
        add_enum_property (
            builder, "group_layout", "Group layout", "vertical", { "vertical", "horizontal" }
        );
        add_enum_property (
            builder, "app_list_side", "Application list side", "left", { "left", "right" }
        );
        add_enum_property (
            builder, "app_list_sort", "Application list sorting", "alphabetical", { "relevance", "alphabetical" }
        );
        add_enum_property (
            builder, "search_sort", "Local search sorting", "relevance", { "relevance", "alphabetical" }
        );
        add_enum_property (
            builder, "window_mode", "Window mode", "floating", { "floating", "fullscreen" }
        );
        add_boolean_property (builder, "close_on_focus_loss", "Close on focus loss", true);
        add_enum_property (
            builder, "floating_position", "Floating window position", "custom",
            { "custom", "top-left", "top", "top-right", "left", "center", "right",
              "bottom-left", "bottom", "bottom-right" }
        );
        add_integer_property (builder, "floating_margin", "Floating edge margin", 16, 0, 512);
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

    private void add_sidebar_schema (Json.Builder builder) {
        builder.set_member_name ("sidebar"); builder.begin_object ();
        builder.set_member_name ("type"); builder.add_string_value ("object");
        builder.set_member_name ("consumer_compatibility"); builder.add_string_value ("unverified");
        builder.set_member_name ("default"); new SidebarConfig ().serialize (builder);
        builder.set_member_name ("properties"); builder.begin_object ();
        add_boolean_property (builder, "enabled", "Show action panel", false);
        add_enum_property (builder, "position", "Action panel position", "left",
            { "left", "right", "above-search", "below-search", "in-search" });
        add_boolean_property (builder, "show_labels", "Show action labels", false);
        add_integer_property (builder, "background_opacity", "Panel background opacity (%)", 0, 0, 100);
        add_integer_property (builder, "width", "Vertical panel width (0 = automatic)", 0, 0, 400);
        add_integer_property (builder, "height", "Horizontal panel height (0 = automatic)", 0, 0, 160);
        add_integer_property (builder, "icon_size", "Action icon size", 24, 8, 64);
        add_integer_property (builder, "button_height", "Button height", 44, 24, 96);
        add_integer_property (builder, "spacing", "Button spacing", 4, 0, 32);
        add_integer_property (builder, "padding", "Panel padding", 6, 0, 24);
        string[] sections = { "start", "end" };
        foreach (string section in sections) {
            builder.set_member_name (section); builder.begin_object ();
            builder.set_member_name ("type"); builder.add_string_value ("array");
            builder.set_member_name ("items"); builder.begin_object ();
            builder.set_member_name ("type"); builder.add_string_value ("object");
            builder.set_member_name ("action_types"); builder.begin_array ();
            foreach (string kind in new string[] { "command", "application", "folder", "menu", "separator" }) builder.add_string_value (kind);
            builder.end_array ();
            builder.set_member_name ("fields"); builder.begin_array ();
            foreach (string field in new string[] { "type", "label", "icon", "confirm", "close_launcher", "argv", "cwd", "desktop_id", "path", "items" }) builder.add_string_value (field);
            builder.end_array ();
            builder.set_member_name ("max_menu_depth"); builder.add_int_value (8);
            builder.set_member_name ("implicit_shell"); builder.add_boolean_value (false);
            builder.end_object (); builder.end_object ();
        }
        builder.end_object (); builder.end_object ();
    }

    private void add_animation_schema (Json.Builder builder, string name, AnimationProfile defaults) {
        builder.set_member_name (name);
        builder.begin_object ();
        builder.set_member_name ("type"); builder.add_string_value ("object");
        builder.set_member_name ("consumer_compatibility"); builder.add_string_value ("unverified");
        builder.set_member_name ("scope"); builder.add_string_value ("local-selected-monitor");
        builder.set_member_name ("default"); defaults.serialize (builder);
        builder.set_member_name ("properties"); builder.begin_object ();
        add_enum_property (builder, "effect", "Effect (none disables)", defaults.effect.to_string (),
            { "none", "fade", "slide", "zoom", "pop" });
        string[] sections = { "fade", "slide", "zoom", "pop" };
        foreach (var section in sections) {
            builder.set_member_name (section); builder.begin_object ();
            builder.set_member_name ("type"); builder.add_string_value ("object");
            builder.set_member_name ("properties"); builder.begin_object ();
            switch (section) {
            case "fade":
                add_integer_property (builder, "duration_ms", "Duration (ms)", defaults.fade_duration_ms, 0, 2000);
                break;
            case "slide":
                add_enum_property (builder, "direction", "Screen edge", defaults.slide_direction.to_string (), { "left", "right", "top", "bottom" });
                add_integer_property (builder, "duration_ms", "Flight duration (ms; opening spring settles afterwards)", defaults.slide_duration_ms, 0, 2000);
                break;
            case "zoom":
                add_integer_property (builder, "scale_percent", "Scale (%)", 85, 50, 100);
                add_integer_property (builder, "duration_ms", "Duration (ms)", 200, 0, 2000);
                break;
            case "pop":
                add_integer_property (builder, "scale_percent", "Scale (%)", 85, 50, 100);
                add_integer_property (builder, "damping_percent", "Damping (%)", 65, 30, 200);
                add_integer_property (builder, "stiffness", "Spring stiffness (mass fixed at 1)", 300, 50, 1200);
                break;
            }
            builder.end_object (); builder.end_object ();
        }
        builder.end_object (); builder.end_object ();
    }

    private void add_config_search_provider_array (Json.Builder builder, ConfigManager config) {
        builder.begin_array ();
        for (uint i = 0; i < config.search_providers.length; i++) {
            var provider = config.search_providers[i];
            builder.begin_object ();
            builder.set_member_name ("id");
            builder.add_string_value (provider.id);
            builder.set_member_name ("enabled");
            builder.add_boolean_value (provider.enabled);
            builder.end_object ();
        }
        builder.end_array ();
    }

    private void add_search_provider_array (
        Json.Builder builder,
        GenericArray<SearchProviderInfo> providers
    ) {
        builder.begin_array ();
        for (uint i = 0; i < providers.length; i++) {
            var provider = providers[i];
            builder.begin_object ();
            builder.set_member_name ("id");
            builder.add_string_value (provider.desktop_id);
            builder.set_member_name ("name");
            builder.add_string_value (provider.name ?? provider.desktop_id);
            builder.set_member_name ("bus_name");
            builder.add_string_value (provider.bus_name);
            builder.set_member_name ("object_path");
            builder.add_string_value (provider.object_path);
            builder.set_member_name ("icon");
            if (provider.icon != null) {
                builder.add_string_value (provider.icon.to_string ());
            } else {
                builder.add_null_value ();
            }
            builder.end_object ();
        }
        builder.end_array ();
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
        if (name == "cell_size") {
            builder.set_member_name ("unit"); builder.add_string_value ("px");
            builder.set_member_name ("special_values"); builder.begin_object ();
            builder.set_member_name ("0"); builder.add_string_value ("automatic");
            builder.end_object ();
        }
        builder.end_object ();
    }
}
