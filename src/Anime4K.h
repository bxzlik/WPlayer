#pragma once

#include <QStringList>

namespace Anime4K {

// Режимы: "A", "B", "C", "AA", "BB", "CA" (как в официальных input.conf Anime4K v4).
// fast = цепочка для слабых видеокарт (модели M/S вместо VL/M).
// Возвращает имена .glsl-файлов в порядке применения или пустой список для
// неизвестного режима / "off".
QStringList shaderFiles(const QString& mode, bool fast);

} // namespace Anime4K
