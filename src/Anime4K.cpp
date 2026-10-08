#include "Anime4K.h"

namespace Anime4K {

QStringList shaderFiles(const QString& mode, bool fast)
{
    // Цепочки повторяют GLSL_Windows_High-end / Low-end из инструкции Anime4K v4.
    const QString restore      = fast ? QStringLiteral("Restore_CNN_M")            : QStringLiteral("Restore_CNN_VL");
    const QString restoreSoft  = fast ? QStringLiteral("Restore_CNN_Soft_M")       : QStringLiteral("Restore_CNN_Soft_VL");
    const QString upscale      = fast ? QStringLiteral("Upscale_CNN_x2_M")         : QStringLiteral("Upscale_CNN_x2_VL");
    const QString upDenoise    = fast ? QStringLiteral("Upscale_Denoise_CNN_x2_M") : QStringLiteral("Upscale_Denoise_CNN_x2_VL");
    const QString upscale2     = fast ? QStringLiteral("Upscale_CNN_x2_S")         : QStringLiteral("Upscale_CNN_x2_M");
    const QString restore2     = fast ? QStringLiteral("Restore_CNN_S")            : QStringLiteral("Restore_CNN_M");
    const QString restoreSoft2 = fast ? QStringLiteral("Restore_CNN_Soft_S")       : QStringLiteral("Restore_CNN_Soft_M");
    const QString down2        = QStringLiteral("AutoDownscalePre_x2");
    const QString down4        = QStringLiteral("AutoDownscalePre_x4");

    QStringList chain;
    if (mode == QLatin1String("A"))
        chain = {restore, upscale, down2, down4, upscale2};
    else if (mode == QLatin1String("B"))
        chain = {restoreSoft, upscale, down2, down4, upscale2};
    else if (mode == QLatin1String("C"))
        chain = {upDenoise, down2, down4, upscale2};
    else if (mode == QLatin1String("AA"))
        chain = {restore, upscale, restore2, down2, down4, upscale2};
    else if (mode == QLatin1String("BB"))
        chain = {restoreSoft, upscale, down2, down4, restoreSoft2, upscale2};
    else if (mode == QLatin1String("CA"))
        chain = {upDenoise, down2, down4, restore2, upscale2};
    else
        return {};

    chain.prepend(QStringLiteral("Clamp_Highlights"));
    for (QString& name : chain)
        name = QStringLiteral("Anime4K_") + name + QStringLiteral(".glsl");
    return chain;
}

} // namespace Anime4K
