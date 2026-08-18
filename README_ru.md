# ximper-shell-launcher

Лаунчер приложений.
Компонент Ximper Shell.

Полноэкранный лаунчер приложений с режимом плиток, вдохновлённым Windows Phone 8.1. Поддерживает плитки разных размеров, папки с анимацией, перетаскивание, нечёткий поиск по всем полям `.desktop`-файлов, интеграцию с GNOME Search Providers и геймпад. Написан на Vala с GTK4, libadwaita, gtk4-layer-shell и libmanette.

Поддерживает Hyprland и Niri через вспомогательные модули композитора.

## Возможности

- Полноэкранный или плавающий лаунчер в режимах плиток и Wofi.
- Маленькие, средние и большие плитки приложений, анимированные папки, перестановка и управление папками перетаскиванием.
- Навигация с клавиатуры, нечёткий поиск приложений и результаты GNOME Search Providers.
- Необязательные фоновое изображение, затемнение и настройка прозрачности меню.
- Навигация с геймпада через libmanette.
- Необязательная интеграция с Ximper Shell Dock: приложение можно закрепить или открепить через контекстное меню плитки.

## Сборка

```sh
meson setup _build
ninja -C _build
./_build/src/ximper-shell-launcher
```

## CLI

```sh
# Открыть лаунчер, выбранный в launcher_mode
ximper-shell-launcher --toggle
ximper-shell-launcher --reload    # перечитать конфигурацию с диска и применить её к запущенному лаунчеру
ximper-shell-launcher --describe  # вывести текущую конфигурацию и поддерживаемые параметры в JSON
```

## Поддержка композиторов

Лаунчер использует модули композиторов для специфичного поведения:

- Hyprland: в плавающем режиме лаунчер может открываться на мониторе активного рабочего пространства через `hyprctl activeworkspace -j`.
- Niri: в плавающем режиме лаунчер может открываться на выходе рабочего пространства в фокусе через `niri msg --json workspaces`.

## Конфигурация

`~/.config/ximper-shell/launcher/config.json`

```json
{
  "max_columns": 0,
  "cell_size": 0,
  "layer": "overlay",
  "launcher_mode": "tiles",
  "window_mode": "floating",
  "close_on_focus_loss": true,
  "floating_x": 0,
  "floating_y": 24,
  "floating_width": 1120,
  "floating_height": 880,
  "floating_x_percent": 50,
  "floating_y_percent": 50,
  "output": [],
  "wallpaper_path": "",
  "wallpaper_fit": 2,
  "wallpaper_opacity": 100,
  "wallpaper_dim": 0,
  "background_opacity": 100,
  "search": {
    "providers_enabled": true,
    "providers": [
      { "id": "org.gnome.Nautilus.desktop", "enabled": true },
      { "id": "org.gnome.Calculator.desktop", "enabled": false }
    ]
  },
  "groups": [{
    "name": "",
    "tiles": [
      { "desktop_id": "firefox.desktop", "size": "small" },
      { "desktop_id": "folder:Internet", "size": "folder",
        "folder_name": "Internet",
        "folder_items": ["firefox.desktop", "org.gnome.Epiphany.desktop"] }
    ]
  }]
}
```

| Ключ | Тип | По умолчанию | Описание |
|-----|-----|-------------|----------|
| `max_columns` | int | `0` | Максимальное число столбцов плиток (0 = автоматически, до 18) |
| `cell_size` | int | `0` | Размер плитки в пикселях (0 = автоматически из ширины экрана) |
| `layer` | string | `"overlay"` | Слой layer-shell: `"background"`, `"bottom"`, `"top"` или `"overlay"`. Числовые значения из старых конфигураций автоматически переносятся при сохранении. |
| `launcher_mode` | string | `"tiles"` | Интерфейс лаунчера: `"tiles"` или компактный `"wofi"` |
| `window_mode` | string | `"floating"` | Режим окна для режимов плиток и Wofi: `"fullscreen"` или `"floating"` |
| `close_on_focus_loss` | bool | `true` | Закрывать плавающий лаунчер при потере фокуса |
| `floating_x` | int | `0` | Горизонтальное смещение плавающего лаунчера в пикселях |
| `floating_y` | int | `24` | Вертикальное смещение плавающего лаунчера в пикселях |
| `floating_width` | int | `1120` | Ширина плавающего лаунчера в пикселях; используется режимами плиток и Wofi |
| `floating_height` | int | `880` | Высота плавающего лаунчера в пикселях; используется режимами плиток и Wofi |
| `floating_x_percent` | int | `50` | Горизонтальная позиция: 0–100% доступного пространства; используется режимами плиток и Wofi |
| `floating_y_percent` | int | `50` | Вертикальная позиция: 0–100% доступного пространства; используется режимами плиток и Wofi |
| `output` | string[] | `[]` | Имя разъёма целевого монитора; пустой массив использует выход активного рабочего пространства, выбранный композитором |
| `wallpaper_path` | string | `""` | Абсолютный путь к локальному фоновому изображению; пустая строка отключает его |
| `wallpaper_fit` | int | `2` | Режим масштабирования: 0=заполнение, 1=вписать, 2=покрыть, 3=уменьшать |
| `wallpaper_opacity` | int | `100` | Прозрачность фонового изображения, 0–100% |
| `wallpaper_dim` | int | `0` | Степень чёрного затемнения поверх фонового изображения, 0–100% |
| `background_opacity` | int | `100` | Прозрачность фона меню, 0–100% |
| `search.providers_enabled` | bool | `true` | Глобально включить внешние GNOME Search Providers; локальный поиск приложений остаётся включённым при `false` |
| `search.providers` | array | `[]` | Упорядоченный список поставщиков поиска; у записи есть `id` desktop-файла и флаг `enabled` |
| `groups` | array | | Группы плиток и папки |

`monitor_index` принимается только для старой конфигурации и при сохранении заменяется на `output`. Используйте имя разъёма монитора: индексы дисплеев могут измениться.

Поставщики поиска находятся в пользовательском и системных XDG-каталогах `gnome-shell/search-providers`. Установите `search.providers_enabled` в `false`, чтобы отключить все внешние поставщики, сохранив локальный поиск приложений. Их порядок в `search.providers` определяет порядок секций результатов. Поставщики, отсутствующие в списке, остаются включёнными и следуют после настроенных в алфавитном порядке.


### Пользовательский CSS

Создайте `~/.config/ximper-shell/launcher/style.css`, чтобы изменить внешний вид лаунчера без редактирования установленных файлов. Эта таблица стилей загружается с пользовательским приоритетом и перекрывает правила из поставляемой таблицы. После изменения выполните Reload или перезапустите лаунчер.

Полный перечень доступных правил и хорошая основа для собственного файла — поставляемая таблица [`data/ximper-shell-launcher.css`](data/ximper-shell-launcher.css). В установленной системе она обычно находится по пути `/etc/xdg/ximper-shell/launcher/style.css`.

```sh
mkdir -p ~/.config/ximper-shell/launcher
cp /etc/xdg/ximper-shell/launcher/style.css \
  ~/.config/ximper-shell/launcher/style.css
```

Например, чтобы настроить фон лаунчера, скругление плиток и тень плавающего лаунчера:

```css
.window-background {
  background: @window_bg_color;
}

.tile {
  border-radius: 16px;
}

.grid-overlay.floating {
  box-shadow: 0 8px 24px @headerbar_shade_color;
}
```

Полезные селекторы: `.grid-overlay`, `.grid-overlay.floating`, `.window-background`, `.tile`, `.tile-name`, `.search-entry`, `.search-result-row`, `.folder-expanded` и `.wallpaper-dimmer`. Цвета тем GTK/libadwaita, например `@window_bg_color`, `@card_bg_color` и `@accent_bg_color`, следуют за активной системной темой.

## Геймпад

Геймпад поддерживается через libmanette. При подключении геймпада появляется уведомление.

| Кнопка | Действие |
|--------|----------|
| D-pad / левый стик | Навигация по плиткам |
| A (нижняя) | Запуск плитки / выбор пункта меню |
| B (правая) | Назад: закрыть папку, всплывающее меню или лаунчер |
| X (верхняя) | Открыть контекстное меню плитки в фокусе |
| Xbox / Guide | Переключить лаунчер |
| LB / RB | Прокрутка вверх / вниз |

Удерживайте D-pad или стик для непрерывной навигации.

## D-Bus

`ru.ximperlinux.shell.Launcher` по пути `/ru/ximperlinux/shell/Launcher`:

- `Toggle()` — показать или скрыть лаунчер
- `Reload()` — перечитать файл конфигурации и применить изменения без перезапуска

## Лицензия

GPLv3 — см. [LICENSE](LICENSE).
