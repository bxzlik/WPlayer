; Установщик WPlayer (.exe) — NSIS, для текущего пользователя, без прав администратора.
; Ставит в %LOCALAPPDATA%\Programs\WPlayer: там yt-dlp может обновлять сам себя.
;
; makensis /DVERSION=1.0.0 /DSRC=<папка cmake --install> /DOUTFILE=<путь к setup.exe> installer\WPlayer.nsi

Unicode true
SetCompressor /SOLID lzma

!ifndef VERSION
  !error "Передайте /DVERSION=x.y.z"
!endif
!ifndef SRC
  !error "Передайте /DSRC=<папка с установленным WPlayer>"
!endif
!ifndef OUTFILE
  !define OUTFILE "WPlayer-${VERSION}.exe"
!endif

!define APP "WPlayer"
!define PUBLISHER "bxzlik"
!define URL "https://github.com/bxzlik/WPlayer"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP}"

Name "${APP}"
OutFile "${OUTFILE}"
InstallDir "$LOCALAPPDATA\Programs\${APP}"
InstallDirRegKey HKCU "Software\${APP}" "InstallDir"
RequestExecutionLevel user
BrandingText "${APP} ${VERSION}"

VIProductVersion "${VERSION}.0"
VIAddVersionKey /LANG=0 "ProductName" "${APP}"
VIAddVersionKey /LANG=0 "ProductVersion" "${VERSION}"
VIAddVersionKey /LANG=0 "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=0 "FileDescription" "${APP} Setup"
VIAddVersionKey /LANG=0 "CompanyName" "${PUBLISHER}"
VIAddVersionKey /LANG=0 "LegalCopyright" "${PUBLISHER}"

!include "MUI2.nsh"

!define MUI_ICON "..\res\WPlayer.ico"
!define MUI_UNICON "..\res\WPlayer.ico"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\WPlayer.exe"

!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "Russian"
!insertmacro MUI_LANGUAGE "English"

Section "WPlayer"
  SetOutPath "$INSTDIR"
  File /r "${SRC}\*.*"

  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateShortcut "$SMPROGRAMS\${APP}.lnk" "$INSTDIR\WPlayer.exe"
  CreateShortcut "$DESKTOP\${APP}.lnk" "$INSTDIR\WPlayer.exe"

  WriteRegStr HKCU "Software\${APP}" "InstallDir" "$INSTDIR"

  ; «Приложения» в параметрах Windows
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "${APP}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "${PUBLISHER}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "URLInfoAbout" "${URL}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\WPlayer.exe"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "${UNINSTALL_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  Delete "$SMPROGRAMS\${APP}.lnk"
  Delete "$DESKTOP\${APP}.lnk"

  ; Только своё: папку могли выбрать общую, и стирать её целиком нельзя
  RMDir /r "$INSTDIR\plugins"
  RMDir /r "$INSTDIR\qml"
  RMDir /r "$INSTDIR\shaders"
  Delete "$INSTDIR\*.dll"
  Delete "$INSTDIR\WPlayer.exe"
  Delete "$INSTDIR\yt-dlp.exe"
  Delete "$INSTDIR\yt-dlp.exe.part"
  Delete "$INSTDIR\qt.conf"
  Delete "$INSTDIR\THIRD_PARTY_NOTICES.txt"
  Delete "$INSTDIR\LICENSE.txt"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"  ; удалится, только если опустела

  DeleteRegKey HKCU "${UNINSTALL_KEY}"
  ; Настройки плеера (HKCU\Software\WPlayer\WPlayer) не трогаем — только путь установки
  DeleteRegValue HKCU "Software\${APP}" "InstallDir"
SectionEnd
