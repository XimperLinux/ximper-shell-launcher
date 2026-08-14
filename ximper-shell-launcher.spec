Name: ximper-shell-launcher
Version: 0.1.0
Release: eter0
Summary: Ximper Shell tile application launcher
License: GPL-3.0-only
Group: Graphical desktop/Other
Url: https://gitlab.eterfund.ru/ximperlinux/%name

Source: %name-%version.tar

BuildRequires(pre): rpm-macros-meson
BuildRequires: meson
BuildRequires: vala
BuildRequires: pkgconfig(gtk4) >= 4.12
BuildRequires: pkgconfig(gtk4-layer-shell-0) >= 1.0
BuildRequires: libgtk4-layer-shell-devel-vala
BuildRequires: pkgconfig(json-glib-1.0)
BuildRequires: pkgconfig(libadwaita-1) >= 1.4
BuildRequires: pkgconfig(manette-0.2)

%description
Application launcher for Ximper Shell, built with GTK4, libadwaita and
gtk4-layer-shell. It supports Hyprland, Niri and gamepad navigation.

%prep
%setup

%build
%meson
%meson_build

%install
%meson_install
%find_lang %name

%check
%meson_test

%files -f %name.lang
%doc README.md LICENSE
%_bindir/%name
%dir %_sysconfdir/xdg/ximper-shell/launcher
%_sysconfdir/xdg/ximper-shell/launcher/style.css

%changelog
* Tue Aug 11 2026 Roman Alifanov <ximper@altlinux.org> 0.1.0-eter0
- Initial build
