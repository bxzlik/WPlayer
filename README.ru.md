<div align="center">

<img src="docs/logo.png" width="96" height="96" alt="WPlayer" />

# WPlayer

**Видеоплеер, сделанный под аниме.**

Десктопный плеер для Windows на основе mpv: локальные файлы и ссылки, апскейл Anime4K и видео из одной ссылки со звуком из другой

[**📦 Релизы**](https://github.com/bxzlik/WPlayer/releases)

[English](README.md) · **Русский**

</div>

## ✨ Возможности

| Возможность | Примечания |
| --- | --- |
| 🎬 **Файлы и ссылки** | Локальные файлы, прямые ссылки и страницы сайтов через yt-dlp |
| 🎧 **Видео + аудио** | Картинка из одной ссылки, звук из другой — для озвучки с другого источника, с подстройкой задержки |
| ✨ **Anime4K** | Режимы A / B / C / A+A / B+B / C+A, качественный и быстрый варианты |
| 🎨 **Цвет акцента** | Палитра или любой свой цвет |
| 🖥️ **Нативное окно** | Свой тайтлбар со Snap Layouts, плавное видео без подтормаживания интерфейса |

## 🚀 Разработка

```powershell
# libmpv, yt-dlp и шейдеры Anime4K → third_party/ и shaders/
powershell -ExecutionPolicy Bypass -File scripts\fetch-deps.ps1

scripts\build.cmd                                  # Release → build\Release\WPlayer.exe
scripts\build.cmd Debug C:\Qt\6.8.3\msvc2022_64    # конфигурация и путь к Qt
```

Требуются [Visual Studio 2022 Build Tools](https://visualstudio.microsoft.com/ru/downloads/) (нагрузка «Разработка классических приложений на C++») и [Qt 6.7+](https://www.qt.io/download-qt-installer) для MSVC 2022 64-bit.

## 📄 Лицензия

WPlayer распространяется под [GNU General Public License v3.0](LICENSE). Copyright © 2026 bxzlik.

Сторонние компоненты и их лицензии — в [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt).
