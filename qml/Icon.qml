import QtQuick
import QtQuick.Controls.impl

// Иконка Solar из qml/icons/<name>.svg, перекрашиваемая в color
IconImage {
    id: root

    property string iconName: ""
    property int size: 20

    source: iconName !== "" ? Qt.resolvedUrl("icons/" + iconName + ".svg") : ""
    sourceSize.width: size
    sourceSize.height: size
    width: size
    height: size
    color: Theme.iconFg
    fillMode: Image.PreserveAspectFit
}
