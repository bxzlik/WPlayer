# Скачивает зависимости проекта:
#   third_party/mpv/     — libmpv (сборка shinchiro: include/, libmpv-2.dll)
#   third_party/yt-dlp.exe
#   shaders/             — GLSL-шейдеры Anime4K v4
#
# Запуск:  powershell -ExecutionPolicy Bypass -File scripts\fetch-deps.ps1 [-Force]

param([switch]$Force)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # иначе Invoke-WebRequest качает в разы медленнее

$root    = Split-Path -Parent $PSScriptRoot
$tp      = Join-Path $root 'third_party'
$shaders = Join-Path $root 'shaders'
$tmp     = Join-Path ([IO.Path]::GetTempPath()) 'wplayer-deps'
$headers = @{ 'User-Agent' = 'WPlayer-fetch-deps' }
# В GitHub Actions — с токеном, иначе API GitHub быстро упирается в лимит запросов
if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN" }

New-Item -ItemType Directory -Force $tp, $tmp | Out-Null

function Expand-7z([string]$archive, [string]$dest) {
    New-Item -ItemType Directory -Force $dest | Out-Null
    $sevenZip = @((Get-Command 7z -ErrorAction SilentlyContinue).Source,
                  "$env:ProgramFiles\7-Zip\7z.exe") | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if ($sevenZip) {
        & $sevenZip x $archive "-o$dest" -y | Out-Null
    } else {
        # tar.exe в Windows 11 (libarchive) умеет распаковывать .7z
        tar -xf $archive -C $dest
    }
    if ($LASTEXITCODE -ne 0) { throw "Не удалось распаковать $archive (установите 7-Zip)" }
}

# ---------- libmpv ----------
$mpvDir = Join-Path $tp 'mpv'
if ($Force -or -not (Test-Path (Join-Path $mpvDir 'include\mpv\client.h'))) {
    Write-Host '==> libmpv: ищу последнюю сборку shinchiro/mpv-winbuild-cmake'
    $rel = Invoke-RestMethod 'https://api.github.com/repos/shinchiro/mpv-winbuild-cmake/releases/latest' -Headers $headers
    # x86_64 без -v3: работает на любых 64-битных CPU
    $asset = $rel.assets | Where-Object { $_.name -match '^mpv-dev-x86_64-\d{8}-git-.+\.7z$' } | Select-Object -First 1
    if (-not $asset) { throw 'В последнем релизе не найден архив mpv-dev-x86_64' }

    $archive = Join-Path $tmp $asset.name
    Write-Host "    скачиваю $($asset.name)"
    Invoke-WebRequest $asset.browser_download_url -OutFile $archive -Headers $headers

    if (Test-Path $mpvDir) { Remove-Item -Recurse -Force $mpvDir }
    Expand-7z $archive $mpvDir
    Write-Host "    готово: $mpvDir"
} else {
    Write-Host '==> libmpv: уже есть (для обновления запустите с -Force)'
}

# ---------- yt-dlp ----------
$ytdlp = Join-Path $tp 'yt-dlp.exe'
if ($Force -or -not (Test-Path $ytdlp)) {
    Write-Host '==> yt-dlp: скачиваю последнюю версию'
    Invoke-WebRequest 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe' -OutFile $ytdlp -Headers $headers
} else {
    Write-Host '==> yt-dlp: уже есть'
}

# ---------- Anime4K ----------
if ($Force -or -not (Test-Path (Join-Path $shaders 'Anime4K_Clamp_Highlights.glsl'))) {
    Write-Host '==> Anime4K: скачиваю шейдеры v4.0.1'
    $zip = Join-Path $tmp 'Anime4K_v4.0.zip'
    Invoke-WebRequest 'https://github.com/bloc97/Anime4K/releases/download/v4.0.1/Anime4K_v4.0.zip' -OutFile $zip -Headers $headers

    $unpacked = Join-Path $tmp 'anime4k'
    if (Test-Path $unpacked) { Remove-Item -Recurse -Force $unpacked }
    Expand-Archive $zip -DestinationPath $unpacked

    New-Item -ItemType Directory -Force $shaders | Out-Null
    Get-ChildItem $unpacked -Recurse -Filter 'Anime4K_*.glsl' | Copy-Item -Destination $shaders -Force
    Write-Host "    готово: $((Get-ChildItem $shaders -Filter *.glsl).Count) шейдеров в $shaders"
} else {
    Write-Host '==> Anime4K: шейдеры уже есть'
}

Write-Host ''
Write-Host 'Все зависимости на месте.'
