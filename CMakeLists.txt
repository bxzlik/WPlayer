cmake_minimum_required(VERSION 3.21)

project(WPlayer VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT MSVC)
    message(FATAL_ERROR "WPlayer собирается только MSVC (Visual Studio 2022 / Build Tools)")
endif()

# Плоская папка установки: WPlayer.exe и всё рядом. Задаётся до
# qt_standard_project_setup() — тот сам подключает GNUInstallDirs и иначе
# первым запишет в кэш bin.
set(CMAKE_INSTALL_BINDIR "." CACHE STRING "Куда ставить WPlayer.exe относительно префикса")

find_package(Qt6 6.7 REQUIRED COMPONENTS Gui Quick QuickControls2 OpenGL Network Svg)
qt_standard_project_setup(REQUIRES 6.7)

# Путь установки «.» (плоская папка) — нормализуется как есть
if(POLICY CMP0177)
    cmake_policy(SET CMP0177 NEW)
endif()

# ---------------------------------------------------------------------------
# libmpv
#
# В MPV_DIR должны лежать include/mpv/*.h и libmpv-2.dll (сборка shinchiro,
# скачивается scripts/fetch-deps.ps1). Если рядом нет mpv.lib, import-библиотека
# для MSVC генерируется из экспортов DLL (dumpbin + lib).
# ---------------------------------------------------------------------------
set(MPV_DIR "${CMAKE_SOURCE_DIR}/third_party/mpv" CACHE PATH "Папка с libmpv (include/, libmpv-2.dll)")

find_path(MPV_INCLUDE_DIR mpv/client.h PATHS "${MPV_DIR}/include" NO_DEFAULT_PATH REQUIRED)
find_file(MPV_DLL NAMES libmpv-2.dll mpv-2.dll PATHS "${MPV_DIR}" NO_DEFAULT_PATH REQUIRED)

if(EXISTS "${MPV_DIR}/mpv.lib")
    set(MPV_IMPLIB "${MPV_DIR}/mpv.lib")
else()
    set(MPV_IMPLIB "${CMAKE_BINARY_DIR}/mpv.lib")
    if(NOT EXISTS "${MPV_IMPLIB}" OR "${MPV_DLL}" IS_NEWER_THAN "${MPV_IMPLIB}")
        get_filename_component(_msvc_bin "${CMAKE_LINKER}" DIRECTORY)
        find_program(MPV_DUMPBIN dumpbin HINTS "${_msvc_bin}" REQUIRED)

        execute_process(
            COMMAND "${MPV_DUMPBIN}" /NOLOGO /EXPORTS "${MPV_DLL}"
            OUTPUT_VARIABLE _exports
            RESULT_VARIABLE _rc)
        if(NOT _rc EQUAL 0)
            message(FATAL_ERROR "dumpbin не смог прочитать ${MPV_DLL}")
        endif()

        get_filename_component(_dll_name "${MPV_DLL}" NAME)
        set(_def "LIBRARY ${_dll_name}\nEXPORTS\n")
        string(REPLACE "\n" ";" _lines "${_exports}")
        foreach(_line IN LISTS _lines)
            # "    ordinal hint RVA      name"
            if(_line MATCHES "^ +[0-9]+ +[0-9A-Fa-f]+ +[0-9A-Fa-f]+ +([A-Za-z_][A-Za-z0-9_]*)")
                string(APPEND _def "    ${CMAKE_MATCH_1}\n")
            endif()
        endforeach()
        file(WRITE "${CMAKE_BINARY_DIR}/mpv.def" "${_def}")

        execute_process(
            COMMAND "${CMAKE_AR}" /NOLOGO /DEF:mpv.def /OUT:mpv.lib /MACHINE:X64
            WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
            RESULT_VARIABLE _rc)
        if(NOT _rc EQUAL 0)
            message(FATAL_ERROR "Не удалось сгенерировать mpv.lib")
        endif()
        message(STATUS "Сгенерирована import-библиотека: ${MPV_IMPLIB}")
    endif()
endif()

add_library(mpv SHARED IMPORTED)
set_target_properties(mpv PROPERTIES
    IMPORTED_LOCATION "${MPV_DLL}"
    IMPORTED_IMPLIB "${MPV_IMPLIB}"
    INTERFACE_INCLUDE_DIRECTORIES "${MPV_INCLUDE_DIR}")

# ---------------------------------------------------------------------------
# Приложение
# ---------------------------------------------------------------------------
qt_add_executable(WPlayer WIN32 src/main.cpp res/WPlayer.rc)

set(WPLAYER_QML
    qml/Main.qml
    qml/Theme.qml
    qml/ControlBar.qml
    qml/SeekBar.qml
    qml/FlatSlider.qml
    qml/IconButton.qml
    qml/PillButton.qml
    qml/FloatingPopup.qml
    qml/ChoicePopup.qml
    qml/OpenUrlDialog.qml
    qml/SettingsPanel.qml
    qml/InfoPanel.qml
    qml/History.qml
    qml/HistoryRow.qml
    qml/HistoryPanel.qml
    qml/QueuePanel.qml
    qml/SettingCard.qml
    qml/Segmented.qml
    qml/ColorPicker.qml
    qml/ModalDialog.qml
    qml/UiSwitch.qml
    qml/UiTextField.qml
    qml/Icon.qml
    qml/Toast.qml
    qml/TitleBar.qml
    qml/CaptionButton.qml
)

# Иконки (Solar, CC BY 4.0) и шрифт Inter (OFL) — внутри модуля по путям icons/… и fonts/…
file(GLOB WPLAYER_ICONS RELATIVE "${CMAKE_SOURCE_DIR}" CONFIGURE_DEPENDS qml/icons/*.svg qml/icons/*.png)
file(GLOB WPLAYER_FONTS RELATIVE "${CMAKE_SOURCE_DIR}" CONFIGURE_DEPENDS qml/fonts/*.ttf)
foreach(_res IN LISTS WPLAYER_ICONS WPLAYER_FONTS)
    string(REGEX REPLACE "^qml/" "" _alias "${_res}")
    set_source_files_properties("${_res}" PROPERTIES QT_RESOURCE_ALIAS "${_alias}")
endforeach()

# Кладём QML в корень модуля, чтобы файлы видели друг друга без импортов
foreach(_qml IN LISTS WPLAYER_QML)
    get_filename_component(_name "${_qml}" NAME)
    set_source_files_properties("${_qml}" PROPERTIES QT_RESOURCE_ALIAS "${_name}")
endforeach()
set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(WPlayer
    URI WPlayer
    VERSION 1.0
    DEPENDENCIES QtQuick
    QML_FILES ${WPLAYER_QML}
    RESOURCES ${WPLAYER_ICONS} ${WPLAYER_FONTS}
    SOURCES
        src/MpvObject.h src/MpvObject.cpp
        src/MpvRenderThread.h src/MpvRenderThread.cpp
        src/YtDlp.h src/YtDlp.cpp
        src/Anime4K.h src/Anime4K.cpp
        src/WindowChrome.h src/WindowChrome.cpp
)

target_compile_options(WPlayer PRIVATE /utf-8 /W3)
target_compile_definitions(WPlayer PRIVATE WPLAYER_VERSION="${PROJECT_VERSION}")
# Сгенерированная регистрация QML-типов подключает заголовки по имени
target_include_directories(WPlayer PRIVATE "${CMAKE_SOURCE_DIR}/src")

target_link_libraries(WPlayer PRIVATE
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::OpenGL
    Qt6::Network
    Qt6::Svg
    mpv
    dwmapi)

# ---------------------------------------------------------------------------
# Рядом с exe: libmpv-2.dll, shaders/, yt-dlp.exe и Qt (windeployqt),
# чтобы собранный плеер сразу запускался из папки сборки.
# ---------------------------------------------------------------------------
add_custom_command(TARGET WPlayer POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${MPV_DLL}" "$<TARGET_FILE_DIR:WPlayer>"
    COMMAND "${CMAKE_COMMAND}"
            "-DSRC_DIR=${CMAKE_SOURCE_DIR}"
            "-DDST_DIR=$<TARGET_FILE_DIR:WPlayer>"
            -P "${CMAKE_SOURCE_DIR}/cmake/CopyRuntimeFiles.cmake"
    VERBATIM)

option(WPLAYER_DEPLOY_QT "Запускать windeployqt после сборки" ON)
if(WPLAYER_DEPLOY_QT AND TARGET Qt6::windeployqt)
    add_custom_command(TARGET WPlayer POST_BUILD
        COMMAND Qt6::windeployqt
                --qmldir "${CMAKE_SOURCE_DIR}/qml"
                --no-translations
                --no-compiler-runtime
                --no-system-d3d-compiler
                --no-system-dxc-compiler
                --no-opengl-sw
                "$<TARGET_FILE:WPlayer>"
        VERBATIM)
endif()

# ---------------------------------------------------------------------------
# Установка: cmake --install build --prefix dist
# Плоская папка, как у обычной Windows-программы: WPlayer.exe и всё рядом.
# ---------------------------------------------------------------------------
include(GNUInstallDirs)

install(TARGETS WPlayer RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
install(FILES "${MPV_DLL}" THIRD_PARTY_NOTICES.txt DESTINATION "${CMAKE_INSTALL_BINDIR}")
install(FILES LICENSE DESTINATION "${CMAKE_INSTALL_BINDIR}" RENAME LICENSE.txt)
install(DIRECTORY shaders/ DESTINATION "${CMAKE_INSTALL_BINDIR}/shaders" OPTIONAL)
install(FILES third_party/yt-dlp.exe DESTINATION "${CMAKE_INSTALL_BINDIR}" OPTIONAL)

# Среда выполнения MSVC (vcruntime140.dll и др.) — рядом с exe, чтобы плеер
# запускался на чистой Windows без установки vc_redist
set(CMAKE_INSTALL_SYSTEM_RUNTIME_DESTINATION "${CMAKE_INSTALL_BINDIR}")
set(CMAKE_INSTALL_UCRT_LIBRARIES OFF)
include(InstallRequiredSystemLibraries)

qt_generate_deploy_qml_app_script(
    TARGET WPlayer
    OUTPUT_SCRIPT _deploy_script
    NO_UNSUPPORTED_PLATFORM_ERROR
    DEPLOY_TOOL_OPTIONS --no-compiler-runtime --no-opengl-sw --no-system-d3d-compiler --no-system-dxc-compiler
                        --no-translations --skip-plugin-types qmltooling)
install(SCRIPT "${_deploy_script}")

# ---------------------------------------------------------------------------
# Установщик .msi (CPack + WiX 3): cpack -G WIX --config build/CPackConfig.cmake
# Ставится для текущего пользователя без прав администратора — так yt-dlp
# может обновлять себя в папке программы. Установщик .exe собирается NSIS
# из той же папки установки (installer/WPlayer.nsi).
# ---------------------------------------------------------------------------
set(CPACK_PACKAGE_NAME "WPlayer")
set(CPACK_PACKAGE_VENDOR "bxzlik")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Видеоплеер для аниме на основе mpv")
set(CPACK_PACKAGE_HOMEPAGE_URL "https://github.com/bxzlik/WPlayer")
set(CPACK_PACKAGE_INSTALL_DIRECTORY "WPlayer")
set(CPACK_PACKAGE_FILE_NAME "WPlayer-${PROJECT_VERSION}")
set(CPACK_PACKAGE_EXECUTABLES "WPlayer" "WPlayer")
set(CPACK_CREATE_DESKTOP_LINKS "WPlayer")
# WiX принимает только .txt/.rtf — копия LICENSE с расширением
configure_file(LICENSE "${CMAKE_BINARY_DIR}/LICENSE.txt" COPYONLY)
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_BINARY_DIR}/LICENSE.txt")

set(CPACK_WIX_UPGRADE_GUID "6F3E9C2A-8B41-4D7E-9A15-3C2B7E0D4F81")  # не менять: по нему MSI обновляет старую версию
set(CPACK_WIX_PRODUCT_ICON "${CMAKE_SOURCE_DIR}/res/WPlayer.ico")
set(CPACK_WIX_INSTALL_SCOPE "perUser")
# Без этих двух свойств ProgramFiles64Folder указывает на C:\Program Files, и установка
# без прав администратора падает. С ними Windows ставит в %LOCALAPPDATA%\Programs.
set(CPACK_WIX_PROPERTY_ALLUSERS "2")
set(CPACK_WIX_PROPERTY_MSIINSTALLPERUSER "1")
set(CPACK_WIX_PROGRAM_MENU_FOLDER ".")
set(CPACK_WIX_CULTURES "ru-RU")
set(CPACK_WIX_PROPERTY_ARPURLINFOABOUT "https://github.com/bxzlik/WPlayer")

set(CPACK_GENERATOR "WIX")
include(CPack)