import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtCore
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
    property string deviceName: ""
    property string deviceHint: ""
    property int pollIntervalMs: 60000
    property int chargingPollIntervalMs: 25000
    property int batteryPollIntervalMs: 70000
    property int errorPollIntervalMs: 15000
    property bool settingsLoaded: false
    property double lastManualRefreshMs: 0

    Settings {
        id: persistedSettings
        category: "RazerBatteryLevelStatus"
        property string deviceHint: ""
    }

    onDeviceHintChanged: {
        if (settingsLoaded) {
            persistedSettings.deviceHint = deviceHint
        }
    }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            const stdout = (data["stdout"] || "").trim()
            executable.disconnectSource(sourceName)

            if (sourceName.includes("find_device")) {
                handleFindResult(stdout)
            } else if (sourceName.includes("read_state")) {
                handleReadState(stdout)
            }
        }
    }

    function updateBattery(forceRescan = false) {
        if (!forceRescan && currentDevicePath) {
            readBatteryAndCharging()
            return
        }

        scanForDevice()
    }

    function scanForDevice() {
        const cmd = `: find_device; ls /sys/bus/hid/drivers/razermouse/*/charge_level 2>/dev/null`
        executable.connectSource(cmd)
    }

    function handleFindResult(stdout) {
        const candidates = stdout.split("\n")
            .map(path => path.trim())
            .filter(path => path && path.includes("/charge_level"))
        const hint = deviceHint.trim()
        let selectedPath = ""

        if (hint) {
            selectedPath = candidates.find(path => path.includes(hint)) || ""
        }

        if (!selectedPath && candidates.length > 0) {
            selectedPath = candidates[0]
        }

        if (selectedPath) {
            currentDevicePath = selectedPath.replace(/\/charge_level$/, "")
            mouseFound = true
            errorMsg = ""
            readBatteryAndCharging()
        } else {
            mouseFound = false
            batteryPercent = -1
            pollIntervalMs = errorPollIntervalMs
            errorMsg = "Path charge_level not found.\nReconnect mouse or adjust Device hint."
        }
    }

    function readBatteryAndCharging() {
        if (!currentDevicePath) {
            scanForDevice()
            return
        }

        const stateCmd = `: read_state;
        LEVEL=$(cat "${currentDevicePath}/charge_level" 2>/dev/null)
        STATUS=$(cat "${currentDevicePath}/charge_status" 2>/dev/null)
        NAME=$(cat "${currentDevicePath}/device_type" 2>/dev/null)

        if [ -z "$STATUS" ]; then STATUS=0; fi
        if [ -z "$NAME" ]; then NAME="Unknown Razer Device"; fi

        if [ -n "$LEVEL" ]; then
            PCT=$((LEVEL * 100 / 255))
            echo "BAT=$PCT"
            echo "CHG=$STATUS"
            echo "NAME=$NAME"
        else
            echo "ERROR=1"
        fi`

        executable.connectSource(stateCmd)
    }

    function handleReadState(stdout) {
        const values = {}
        stdout.split("\n")
            .map(line => line.trim())
            .filter(line => line.includes("="))
            .forEach(line => {
                const idx = line.indexOf("=")
                const key = line.slice(0, idx)
                const value = line.slice(idx + 1)
                values[key] = value
            })

        if (values["ERROR"] === "1" || values["BAT"] === undefined || values["CHG"] === undefined) {
            handleReadFailure()
            return
        }

        const bat = parseInt(values["BAT"], 10)
        if (isNaN(bat) || bat < 0) {
            handleReadFailure()
            return
        }

        batteryPercent = Math.min(100, Math.max(0, bat))
        const status = values["CHG"].trim().toLowerCase()
        isCharging = (status === "1" || status === "charging")
        deviceName = values["NAME"] || "Razer Mouse"
        pollIntervalMs = isCharging ? chargingPollIntervalMs : batteryPollIntervalMs
        mouseFound = true
        errorMsg = ""
    }

    function handleReadFailure() {
        currentDevicePath = ""
        deviceName = ""
        mouseFound = false
        batteryPercent = -1
        pollIntervalMs = errorPollIntervalMs
        errorMsg = "Device path changed or unavailable.\nTrying to re-detect..."
        scanForDevice()
    }

    function requestManualRefresh() {
        const now = Date.now()
        if ((now - lastManualRefreshMs) < 1500) {
            return
        }

        lastManualRefreshMs = now
        updateBattery(true)
    }

    function currentDeviceLabel() {
        if (!currentDevicePath) {
            return "No device selected"
        }

        if (deviceName) {
            return deviceName
        }

        const parts = currentDevicePath.split("/")
        if (parts.length >= 2) {
            return "Device: " + parts[parts.length - 2]
        }

        return "Device: " + currentDevicePath
    }

    function batteryColor() {
        if (batteryPercent < 0) return Kirigami.Theme.disabledTextColor
            if (batteryPercent <= 15) return "#ff4444"
                if (batteryPercent <= 30) return "#ffaa00"
                    return "#00cc66"
    }

    // ==================== UI ====================
    compactRepresentation: Item {
        id: compactRoot
        implicitWidth: parent ? parent.height * 1.2 : 32
        implicitHeight: parent ? parent.height : 32

        Item {
            anchors.fill: parent
            clip: false // Allow the icon to slightly exceed boundaries if needed

            Kirigami.Icon {
                id: mouseIcon
                anchors.centerIn: parent
                // Set size slightly larger than container to compensate for internal icon padding
                width: parent.height * 1.4
                height: parent.height * 1.4
                source: "input-mouse"
                color: batteryColor()
                opacity: 0.25
                smooth: true
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: -4

                PlasmaComponents.Label {
                    // Use strict concatenation without spaces
                    text: batteryPercent >= 0 ? batteryPercent + "%" : "—"
                    font.pixelSize: Math.max(9, compactRoot.height * 0.38) // Slightly reduced to fit the % sign
                    font.bold: true
                    color: batteryColor() // Sync color with icon (changes to red/orange on low battery)
                    Layout.alignment: Qt.AlignHCenter
                }

                PlasmaComponents.Label {
                    text: "⚡"
                    visible: isCharging
                    font.pixelSize: Math.max(8, compactRoot.height * 0.35)
                    color: "#00ff41"
                    Layout.alignment: Qt.AlignHCenter
                    style: Text.Outline
                    styleColor: "black"
                }
            }
        }

        PlasmaCore.ToolTipArea {
            anchors.fill: parent
            mainText: "Razer Mouse charge status"
            subText: batteryPercent < 0 ? errorMsg : "Charge: " + batteryPercent + "%" + (isCharging ? " ⚡" : "") + "\n" + currentDeviceLabel()
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }
    }

    fullRepresentation: Item {
        Layout.minimumWidth: 280
        Layout.minimumHeight: 180
        Layout.maximumWidth: 280
        Layout.maximumHeight: 180

        Rectangle {
            anchors.fill: parent
            color: "#0d0d0d"
            radius: 5
            border.color: "#00ff41"
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
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
                        onClicked: requestManualRefresh()
                    }
                }

                PlasmaComponents.Label {
                    text: currentDeviceLabel()
                    font.pixelSize: 10
                    color: "#aaaaaa"
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    TextField {
                        id: deviceHintField
                        Layout.fillWidth: true
                        placeholderText: "Device hint (optional)"
                        text: root.deviceHint
                    }

                    PlasmaComponents.ToolButton {
                        icon.name: "dialog-ok-apply"
                        onClicked: {
                            root.deviceHint = deviceHintField.text.trim()
                            updateBattery(true)
                        }
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
        interval: pollIntervalMs
        running: true
        repeat: true
        onTriggered: updateBattery()
    }

    Component.onCompleted: {
        deviceHint = persistedSettings.deviceHint
        settingsLoaded = true
        updateBattery()
    }
}
