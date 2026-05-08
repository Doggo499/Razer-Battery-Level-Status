import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    preferredRepresentation: compactRepresentation

    property int batteryPercent: -1
    property bool isCharging: false
    property bool mouseFound: false
    property string errorMsg: ""
    property string currentDevicePath: ""

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            const stdout = (data["stdout"] || "").trim()
            executable.disconnectSource(sourceName)

            if (sourceName.includes("find_device")) {
                handleFindResult(stdout)
            } else if (sourceName.includes("read_battery")) {
                handleBatteryRead(stdout)
            } else if (sourceName.includes("read_charging")) {
                handleChargingRead(stdout)
            }
        }
    }

    function updateBattery() {
        const cmd = `find_device|bash -c '
        CHARGE_FILE=$(find -L /sys/bus/hid/drivers/razermouse/ -name "charge_level" 2>/dev/null | head -1)
        if [ -z "$CHARGE_FILE" ]; then
            CHARGE_FILE=$(find /sys -name "charge_level" 2>/dev/null | head -1)
            fi
            if [ -n "$CHARGE_FILE" ]; then
                echo "$CHARGE_FILE"
                fi
                '`
                executable.connectSource(cmd)
    }

    function handleFindResult(stdout) {
        const path = stdout.trim()

        if (path && path.includes("/charge_level")) {
            currentDevicePath = path.replace(/\/charge_level$/, "")
            mouseFound = true
            errorMsg = ""
            readBatteryAndCharging()
        } else {
            mouseFound = false
            batteryPercent = -1
            errorMsg = "Path charge_level not found.\nReconnect mouse or check env."
        }
    }

    function readBatteryAndCharging() {
        if (!currentDevicePath) return

            const batteryCmd = `read_battery|bash -c 'cat "${currentDevicePath}/charge_level" 2>/dev/null | { read val; echo $((val * 100 / 255)); } || echo -1'`
            const chargingCmd = `read_charging|bash -c 'cat "${currentDevicePath}/charge_status" 2>/dev/null || echo 0'`

            executable.connectSource(batteryCmd)
            executable.connectSource(chargingCmd)
    }

    function handleBatteryRead(stdout) {
        const val = parseInt(stdout, 10)
        if (!isNaN(val) && val >= 0) {
            batteryPercent = Math.min(100, Math.max(0, val))
            errorMsg = ""
        }
    }

    function handleChargingRead(stdout) {
        const val = stdout.trim().toLowerCase()
        isCharging = (val === "1" || val === "charging")
    }

    function batteryColor() {
        if (batteryPercent < 0) return Kirigami.Theme.disabledTextColor
            if (batteryPercent <= 15) return "#ff4444"
                if (batteryPercent <= 30) return "#ffaa00"
                    return "#00cc66"
    }

    // ==================== UI ====================
    compactRepresentation: Item {
        Layout.minimumWidth: compactRow.implicitWidth + 8
        Layout.minimumHeight: compactRow.implicitHeight

        RowLayout {
            id: compactRow
            anchors.centerIn: parent
            spacing: 4

            Kirigami.Icon {
                source: "input-mouse"
                width: Kirigami.Units.iconSizes.small
                height: Kirigami.Units.iconSizes.small
                color: batteryColor()
            }

            PlasmaComponents.Label {
                text: batteryPercent >= 0 ? batteryPercent + "%" : "—"
                font.pixelSize: 12
                font.bold: true
                color: batteryColor()
            }

            PlasmaComponents.Label {
                text: "⚡"
                visible: isCharging
                font.pixelSize: 11
                color: "#00ff41"
            }
        }

        PlasmaCore.ToolTipArea {
            anchors.fill: parent
            mainText: "Razer Mouse charge status"
            subText: batteryPercent < 0 ? errorMsg : "Charge: " + batteryPercent + "%" + (isCharging ? " ⚡" : "")
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }
    }

    fullRepresentation: Item {
        Layout.minimumWidth: 280
        Layout.minimumHeight: 100
        Layout.maximumWidth: 280
        Layout.maximumHeight: 100

        Rectangle {
            anchors.centerIn: parent
            width: childrenRect.width + 24
            height: childrenRect.height + 24
            color: "#0d0d0d"
            radius: 5
            border.color: "#00ff41"
            border.width: 1

            ColumnLayout {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: 12
                width: 260
                spacing: 8

                // Topper
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Kirigami.Icon { source: "input-mouse"; width: 22; height: 22; color: "#00ff41" }

                    PlasmaComponents.Label {
                        text: "Razer Mouse charge status"
                        font.pixelSize: 12
                        font.bold: true
                        color: "white"
                        Layout.fillWidth: true
                    }

                    PlasmaComponents.ToolButton {
                        icon.name: "view-refresh"
                        onClicked: updateBattery()
                    }
                }

                // Charges
                ColumnLayout {
                    visible: batteryPercent >= 0
                    spacing: 6
                    Layout.fillWidth: true

                    RowLayout {
                        Layout.fillWidth: true

                        PlasmaComponents.Label {
                            text: isCharging ? "Charging ⚡" : "Battery level"
                            font.pixelSize: 10
                            color: "#aaaaaa"
                        }

                        Item { Layout.fillWidth: true }

                        PlasmaComponents.Label {
                            text: batteryPercent + "%"
                            font.pixelSize: 18
                            font.bold: true
                            color: batteryColor()
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 10
                        radius: 3
                        color: "#222"

                        Rectangle {
                            width: parent.width * batteryPercent / 100
                            height: parent.height
                            radius: 3
                            color: batteryColor()
                        }
                    }
                }

                // Error
                PlasmaComponents.Label {
                    visible: batteryPercent < 0
                    text: errorMsg
                    color: "#ff6666"
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

            }
        }
    }

    Timer {
        interval: 25000
        running: true
        repeat: true
        onTriggered: updateBattery()
    }

    Component.onCompleted: updateBattery()
}
