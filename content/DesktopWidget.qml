import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.PluginKit.Singletons

Item {
    id: root

    property var pluginApi
    property var screen
    property bool active: true
    property string density: "compact"
    property real s: 1
    property real widthBudget: 360

    readonly property var service: pluginApi ? pluginApi.mainInstance : null
    readonly property string playerPath: service ? service.bin("radio-player") : ""
    readonly property var processEnvironment: service ? service.stateEnv : []
    readonly property var favorites: service && Array.isArray(service.favorites)
        ? service.favorites : []
    readonly property var playingStation: playerStatus.station || ({})
    readonly property bool hasCurrentStation: playerStatus.running === true
        && String(playingStation.uuid || "") !== ""
    readonly property string currentStationName: String(playingStation.name
        || playerStatus.title || "Nothing playing").replace(/[\r\n\t]+/g, " ").slice(0, 100)
    readonly property int listHeight: Math.min(favorites.length * 38, 190)

    property var playerStatus: ({})
    property string playerError: ""
    property string pendingPlayedUuid: ""

    implicitWidth: widthBudget > 0 ? widthBudget : 360 * s
    implicitHeight: content.implicitHeight

    function refreshPlayer() {
        if (!active || !playerPath || statusProcess.running) return
        statusProcess.command = [playerPath, "status"]
        statusProcess.running = true
    }

    function applyPlayerStatus(raw) {
        try {
            var next = JSON.parse(raw)
            if (!next || typeof next !== "object")
                throw new Error("Status is not an object")
            playerStatus = next
            playerError = ""
        } catch (error) {
            playerError = "Radio player status could not be read"
            console.warn("Radio Atlas desktop status is invalid:", error)
        }
    }

    function runPlayer(action, uuid) {
        if (!playerPath || actionProcess.running) return
        playerError = ""
        pendingPlayedUuid = action === "play" ? String(uuid || "") : ""
        actionProcess.errorText = ""
        actionProcess.command = action === "play"
            ? [playerPath, action, pendingPlayedUuid, "favorites"]
            : [playerPath, action]
        actionProcess.running = true
    }

    Timer {
        interval: 1200
        repeat: true
        running: root.active && root.playerPath !== ""
        onTriggered: root.refreshPlayer()
    }

    Process {
        id: statusProcess
        environment: root.processEnvironment
        command: []
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyPlayerStatus(text)
        }
        onExited: function(exitCode) {
            if (exitCode !== 0)
                root.playerError = "Radio player status is unavailable"
        }
    }

    Process {
        id: actionProcess
        environment: root.processEnvironment
        property string errorText: ""
        command: []
        stdout: StdioCollector { waitForEnd: true }
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: actionProcess.errorText = text
        }
        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.playerError = actionProcess.errorText.trim()
                    || "Radio playback action failed"
            } else if (root.pendingPlayedUuid && root.service) {
                root.service.recordPlayed(root.pendingPlayedUuid)
            }
            root.pendingPlayedUuid = ""
            root.refreshPlayer()
        }
    }

    Component.onCompleted: root.refreshPlayer()
    onActiveChanged: if (active) root.refreshPlayer()
    onPlayerPathChanged: root.refreshPlayer()

    Column {
        id: content
        width: root.implicitWidth
        spacing: 8 * root.s

        Row {
            width: parent.width
            spacing: 7 * root.s

            Text {
                text: "\uf0ac"
                color: Theme.accent
                font.family: Theme.font
                font.pixelSize: 15 * root.s
            }

            Text {
                text: "Radio Atlas"
                color: Theme.bright
                font.family: Theme.font
                font.pixelSize: 15 * root.s
                font.weight: Font.DemiBold
            }

            Item { width: Math.max(0, parent.width - 210 * root.s); height: 1 }

            Text {
                text: root.favorites.length + " favorites"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 11 * root.s
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.border
            opacity: 0.55
        }

        Row {
            width: parent.width
            spacing: 8 * root.s

            Column {
                width: parent.width
                spacing: 2 * root.s

                Text {
                    width: parent.width
                    text: root.currentStationName
                    color: Theme.bright
                    font.family: Theme.font
                    font.pixelSize: 13 * root.s
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: root.hasCurrentStation
                        ? (root.playerStatus.paused ? "Paused" : "Playing")
                        : "Choose a favorite to start playback"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                    elide: Text.ElideRight
                }
            }
        }

        Row {
            spacing: 5 * root.s

            Repeater {
                model: [
                    { label: "Prev", action: "previous" },
                    { label: root.playerStatus.paused ? "Play" : "Pause", action: "toggle" },
                    { label: "Next", action: "next" },
                    { label: "Stop", action: "stop" },
                    { label: "Vol-", action: "volume-down" },
                    { label: "Vol+", action: "volume-up" },
                    { label: "Mute", action: "mute" }
                ]

                delegate: Rectangle {
                    required property var modelData
                    width: 44 * root.s
                    height: 27 * root.s
                    radius: 5 * root.s
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.border
                    opacity: root.hasCurrentStation && !actionProcess.running ? 1 : 0.45

                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        color: Theme.bright
                        font.family: Theme.font
                        font.pixelSize: 10 * root.s
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.hasCurrentStation && !actionProcess.running
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runPlayer(modelData.action, "")
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.border
            opacity: 0.55
        }

        Text {
            text: "Favorites"
            color: Theme.bright
            font.family: Theme.font
            font.pixelSize: 13 * root.s
            font.weight: Font.DemiBold
        }

        Text {
            visible: root.favorites.length === 0
            width: parent.width
            wrapMode: Text.WordWrap
            text: "No favorites yet. Add stations with the star in the Radio Atlas panel."
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 11 * root.s
        }

        ListView {
            id: favoriteList
            width: parent.width
            height: root.listHeight
            visible: root.favorites.length > 0
            clip: true
            model: root.favorites
            spacing: 2 * root.s

            delegate: Item {
                required property var modelData
                width: favoriteList.width
                height: 36 * root.s

                Row {
                    anchors.fill: parent
                    spacing: 5 * root.s

                    Rectangle {
                        width: parent.width - 94 * root.s
                        height: parent.height
                        color: "transparent"
                        clip: true

                        Column {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1 * root.s

                            Text {
                                width: parent.width
                                text: String(modelData.name || "Unknown station")
                                    .replace(/[\r\n\t]+/g, " ").slice(0, 100)
                                color: Theme.bright
                                font.family: Theme.font
                                font.pixelSize: 11 * root.s
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: String(modelData.country || "Radio station")
                                    .replace(/[\r\n\t]+/g, " ").slice(0, 80)
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 10 * root.s
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.runPlayer("play", modelData.uuid)
                        }
                    }

                    Rectangle {
                        width: 42 * root.s
                        height: 26 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 5 * root.s
                        color: Theme.accent

                        Text {
                            anchors.centerIn: parent
                            text: "Play"
                            color: Theme.bright
                            font.family: Theme.font
                            font.pixelSize: 10 * root.s
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !actionProcess.running
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.runPlayer("play", modelData.uuid)
                        }
                    }

                    Rectangle {
                        width: 42 * root.s
                        height: 26 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        color: "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "\uE838"
                            color: Theme.accent
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 14 * root.s
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.service && root.service.toggleFavorite)
                                    root.service.toggleFavorite(modelData.uuid)
                            }
                        }
                    }
                }
            }
        }

        Text {
            visible: root.playerError !== ""
                || (root.service && root.service.stateError !== "")
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.playerError || (root.service ? root.service.stateError : "")
            color: Theme.verm
            font.family: Theme.font
            font.pixelSize: 10 * root.s
        }
    }
}
