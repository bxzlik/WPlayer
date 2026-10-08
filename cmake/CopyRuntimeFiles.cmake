# Вызывается после сборки: cmake -DSRC_DIR=... -DDST_DIR=... -P CopyRuntimeFiles.cmake
#
# shaders/ копируется всегда (файлы могли обновиться).
# yt-dlp.exe — только если его ещё нет: плеер сам обновляет свою копию
# (yt-dlp -U), и пересборка не должна откатывать её на старую версию.

file(GLOB _shaders "${SRC_DIR}/shaders/*.glsl")
if(_shaders)
    file(COPY ${_shaders} DESTINATION "${DST_DIR}/shaders")
endif()

if(EXISTS "${SRC_DIR}/third_party/yt-dlp.exe" AND NOT EXISTS "${DST_DIR}/yt-dlp.exe")
    file(COPY "${SRC_DIR}/third_party/yt-dlp.exe" DESTINATION "${DST_DIR}")
endif()
