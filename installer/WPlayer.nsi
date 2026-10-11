; Установщик WPlayer (.exe) — NSIS, для текущего пользователя, без прав администратора.
; Ставит в %LOCALAPPDATA%\Programs\WPlayer: там yt-dlp может обновлять сам себя.
;
; makensis /INPUTCHARSET UTF8 /DVERSION=1.0.0 /DSRC=<папка cmake --install> /DOUTFILE=<путь к setup.exe> installer\WPlayer.nsi

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

; Регистрация для видеофайлов — то же самое для .msi в installer/FileAssociations.wxs
!define PROGID "WPlayer.Video"
!define CLASSES "Software\Classes"
!define CAPABILITIES "Software\${APP}\Capabilities"
!define APP_PATHS "Software\Microsoft\Windows\CurrentVersion\App Paths\WPlayer.exe"

; Те же расширения, что в фильтре «Открыть файл» (Main.qml) и в автозагрузке папки (MpvObject.cpp)
!macro ForEachVideoExt MACRO
  !insertmacro ${MACRO} mkv
  !insertmacro ${MACRO} mp4
  !insertmacro ${MACRO} avi
  !insertmacro ${MACRO} webm
  !insertmacro ${MACRO} mov
  !insertmacro ${MACRO} m2ts
  !insertmacro ${MACRO} ts
  !insertmacro ${MACRO} flv
  !insertmacro ${MACRO} wmv
  !insertmacro ${MACRO} m4v
!macroend

; Только «Открыть с помощью» и «Приложения по умолчанию»: программой по умолчанию
; Windows разрешает назначить только самому пользователю
!macro AssocVideoExt EXT
  WriteRegStr HKCU "${CLASSES}\.${EXT}\OpenWithProgids" "${PROGID}" ""
  WriteRegStr HKCU "${CLASSES}\Applications\WPlayer.exe\SupportedTypes" ".${EXT}" ""
  WriteRegStr HKCU "${CAPABILITIES}\FileAssociations" ".${EXT}" "${PROGID}"
!macroend

!macro UnassocVideoExt EXT
  DeleteRegValue HKCU "${CLASSES}\.${EXT}\OpenWithProgids" "${PROGID}"
  DeleteRegKey /ifempty HKCU "${CLASSES}\.${EXT}\OpenWithProgids"
  DeleteRegKey /ifempty HKCU "${CLASSES}\.${EXT}"
!macroend

; SHCNE_ASSOCCHANGED: проводник перечитывает сопоставления без перезапуска
!macro NotifyAssocChanged
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
!macroend

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

  ; Тип файла WPlayer: значок и команда открытия
  WriteRegStr HKCU "${CLASSES}\${PROGID}" "" "Видеофайл"
  WriteRegStr HKCU "${CLASSES}\${PROGID}\DefaultIcon" "" "$INSTDIR\WPlayer.exe,0"
  WriteRegStr HKCU "${CLASSES}\${PROGID}\shell\open\command" "" '"$INSTDIR\WPlayer.exe" "%1"'

  ; Название и команда в списке «Открыть с помощью»
  WriteRegStr HKCU "${CLASSES}\Applications\WPlayer.exe" "FriendlyAppName" "${APP}"
  WriteRegStr HKCU "${CLASSES}\Applications\WPlayer.exe\shell\open\command" "" '"$INSTDIR\WPlayer.exe" "%1"'

  ; «Параметры → Приложения по умолчанию → WPlayer»
  WriteRegStr HKCU "${CAPABILITIES}" "ApplicationName" "${APP}"
  WriteRegStr HKCU "${CAPABILITIES}" "ApplicationDescription" "Видеоплеер для аниме на основе mpv"
  WriteRegStr HKCU "${CAPABILITIES}" "ApplicationIcon" "$INSTDIR\WPlayer.exe,0"
  WriteRegStr HKCU "Software\RegisteredApplications" "${APP}" "${CAPABILITIES}"

  !insertmacro ForEachVideoExt AssocVideoExt

  ; Запуск по имени: «Win+R → WPlayer», start WPlayer из консоли и других программ
  WriteRegStr HKCU "${APP_PATHS}" "" "$INSTDIR\WPlayer.exe"
  WriteRegStr HKCU "${APP_PATHS}" "Path" "$INSTDIR"

  !insertmacro NotifyAssocChanged
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

  !insertmacro ForEachVideoExt UnassocVideoExt
  DeleteRegKey HKCU "${CLASSES}\${PROGID}"
  DeleteRegKey HKCU "${CLASSES}\Applications\WPlayer.exe"
  DeleteRegKey HKCU "${CAPABILITIES}"
  DeleteRegValue HKCU "Software\RegisteredApplications" "${APP}"
  DeleteRegKey HKCU "${APP_PATHS}"

  !insertmacro NotifyAssocChanged
SectionEnd
