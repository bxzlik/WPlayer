<div align="center">

<img src="docs/logo.png" width="96" height="96" alt="WPlayer" />

# WPlayer

**A video player made for anime.**

A Windows desktop player built on mpv: local files and links, Anime4K upscaling and video from one link with audio from another

[**📦 Releases**](https://github.com/bxzlik/WPlayer/releases)

**English** · [Русский](README.ru.md)

</div>

## ✨ Features

| Feature | Notes |
| --- | --- |
| 🎬 **Files and links** | Local files, direct links and site pages via yt-dlp |
| 🎧 **Video + audio** | Picture from one link, sound from another — for dubs from a different source, with audio delay control |
| ✨ **Anime4K** | Modes A / B / C / A+A / B+B / C+A, quality and fast variants |
| 🎨 **Accent color** | Palette or any custom color |
| 🖥️ **Native window** | Custom title bar with Snap Layouts, smooth playback while the UI stays responsive |

## 🚀 Development

```powershell
# libmpv, yt-dlp and Anime4K shaders → third_party/ and shaders/
powershell -ExecutionPolicy Bypass -File scripts\fetch-deps.ps1

scripts\build.cmd                                  # Release → build\Release\WPlayer.exe
scripts\build.cmd Debug C:\Qt\6.8.3\msvc2022_64    # configuration and Qt path
```

Requires [Visual Studio 2022 Build Tools](https://visualstudio.microsoft.com/downloads/) (C++ workload) and [Qt 6.7+](https://www.qt.io/download-qt-installer) for MSVC 2022 64-bit.

## 📄 License

WPlayer is licensed under the [GNU General Public License v3.0](LICENSE). Copyright © 2026 bxzlik.

Third-party components and their licenses are listed in [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt).
