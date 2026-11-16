import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.PluginKit
import Ryoku.PluginKit.Singletons

// Radio Atlas — desktop widget.
//
// The complete desktop surface for the plugin: now-playing, transport, volume,
// mute, favourites, recent stations, live search and the audio-output picker.
// Everything is driven by the plugin service (service/Main.qml); this file
// never touches the network itself.

Item {
    id: root

    property var pluginApi
    property var screen
    property bool active: true
    property string density: "compact"
    property real s: 1
    property real widthBudget: 380

    readonly property var service: pluginApi ? pluginApi.mainInstance : null
    readonly property string playerPath: service ? service.bin("radio-player") : ""
    readonly property var processEnvironment: service ? service.stateEnv : []

    readonly property var favorites: service && Array.isArray(service.favorites) ? service.favorites : []
    readonly property var recent: service && Array.isArray(service.recent) ? service.recent : []
    readonly property var results: service && Array.isArray(service.results) ? service.results : []
    readonly property var audioOutputs: service && Array.isArray(service.audioOutputs) ? service.audioOutputs : []

    readonly property int volumeValue: {
        if (!service) return 0
        var value = Math.round(Number(service.volume))
        return isFinite(value) ? Math.max(0, Math.min(100, value)) : 0
    }
    readonly property string outputId: service ? String(service.output || "") : ""
    readonly property var outputChoices: {
        var rows = [{ id: "", label: "System default" }]
        for (var i = 0; i < root.audioOutputs.length; i++) rows.push(root.audioOutputs[i])
        return rows
    }

    readonly property var playingStation: playerStatus.station || ({})
    readonly property bool hasCurrentStation: playerStatus.running === true
        && String(playingStation.uuid || "") !== ""
    readonly property string currentStationName: String(playingStation.name
        || playerStatus.title || "Nothing playing").replace(/[\r\n\t]+/g, " ").slice(0, 100)
    readonly property string currentStationCountry: String(playingStation.country
        || "").replace(/[\r\n\t]+/g, " ").slice(0, 80)
    readonly property bool isPaused: playerStatus.paused === true
    readonly property string statusText: !root.hasCurrentStation
        ? "Pick a station to start"
        : (root.isPaused ? "Paused" : "Playing")

    property var playerStatus: ({})
    property string playerError: ""
    property string pendingPlayedUuid: ""
    property string tab: "favorites"
    property string query: ""

    readonly property var listModel: root.tab === "favorites" ? root.favorites
        : (root.tab === "recent" ? root.recent : root.results)
    readonly property string errorText: root.playerError !== "" ? root.playerError
        : (service ? String(service.stateError || service.fetchError || "") : "")

    implicitWidth: widthBudget > 0 ? widthBudget : 380 * s
    implicitHeight: card.implicitHeight

    function refreshPlayer() {
        if (!active || !playerPath || statusProcess.running) return
        statusProcess.command = [playerPath, "status"]
        statusProcess.running = true
    }

    function applyPlayerStatus(raw) {
        try {
            var next = JSON.parse(raw)
            if (!next || typeof next !== "object") throw new Error("bad status")
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

    function playStation(uuid) {
        root.runPlayer("play", uuid)
    }

    function toggleFavorite(uuid) {
        if (service && service.toggleFavorite) service.toggleFavorite(uuid)
    }

    function setVolumeFromX(x, trackWidth) {
        if (!service || !trackWidth) return
        var value = Math.round(x / trackWidth * 100)
        service.setVolume(Math.max(0, Math.min(100, value)))
    }

    function runSearch() {
        if (!service || root.query.trim() === "") return
        root.tab = "search"
        service.search(root.query)
    }

    function outputLabel(sink) {
        for (var i = 0; i < root.audioOutputs.length; i++) {
            if (root.audioOutputs[i].id === sink) return root.audioOutputs[i].label
        }
        return sink
    }

    function stationName(row) {
        return String((row && row.name) || "Unknown station").replace(/[\r\n\t]+/g, " ").slice(0, 100)
    }

    function stationDetail(row) {
        var country = String((row && row.country) || "").replace(/[\r\n\t]+/g, " ").slice(0, 80)
        var codec = String((row && row.codec) || "").replace(/[\r\n\t]+/g, " ").slice(0, 24)
        var bits = Math.round(Number(row && row.bitrate) || 0)
        var quality = codec && bits ? (codec + " · " + bits + " kbps") : codec
        return country + (country && quality ? "  ·  " : "") + quality
    }

    function isFavorite(row) {
        var wanted = String((row && row.uuid) || "")
        for (var i = 0; i < root.favorites.length; i++) {
            if (String(root.favorites[i].uuid || "") === wanted) return true
        }
        return false
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
            if (exitCode !== 0) root.playerError = "Radio player status is unavailable"
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
                root.playerError = actionProcess.errorText.trim() || "Radio playback action failed"
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

    Card {
        id: card
        s: root.s
        width: root.implicitWidth

        Column {
            id: layout
            width: parent.width
            spacing: 10 * root.s

            // --- header ---------------------------------------------------
            Row {
                width: parent.width
                spacing: 8 * root.s

                Rectangle {
                    width: 26 * root.s
                    height: 26 * root.s
                    radius: 7 * root.s
                    color: Theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: "RA"
                        color: Theme.bright
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
                        font.weight: Font.Bold
                    }
                }

                Column {
                    width: Math.max(0, parent.width - 92 * root.s)
                    spacing: 1 * root.s
                    Text {
                        width: parent.width
                        text: "Radio Atlas"
                        color: Theme.bright
                        font.family: Theme.font
                        font.pixelSize: 14 * root.s
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: root.statusText
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
                        elide: Text.ElideRight
                    }
                }

                Item { width: Math.max(0, parent.width - 246 * root.s); height: 1 }

                Text {
                    text: root.favorites.length + " saved"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                }
            }

            // --- now playing ---------------------------------------------
            Rectangle {
                width: parent.width
                height: 52 * root.s
                radius: 8 * root.s
                color: Theme.sheen
                border.width: 1
                border.color: Theme.hair

                Row {
                    anchors.fill: parent
                    anchors.margins: 9 * root.s
                    spacing: 10 * root.s

                    Rectangle {
                        width: 34 * root.s
                        height: 34 * root.s
                        radius: 17 * root.s
                        color: root.hasCurrentStation && !root.isPaused ? Theme.accent : Theme.hair
                        Text {
                            anchors.centerIn: parent
                            text: root.hasCurrentStation && !root.isPaused ? "▶" : "‖"
                            color: Theme.bright
                            font.family: Theme.font
                            font.pixelSize: 13 * root.s
                        }
                    }

                    Column {
                        width: Math.max(0, parent.width - 54 * root.s)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2 * root.s
                        Text {
                            width: parent.width
                            text: root.currentStationName
                            color: Theme.bright
                            font.family: Theme.font
                            font.pixelSize: 13 * root.s
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: root.currentStationCountry !== ""
                                ? root.currentStationCountry : root.outputLabel(root.outputId)
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 11 * root.s
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // --- transport -----------------------------------------------
            Row {
                width: parent.width
                spacing: 6 * root.s

                Repeater {
                    model: [
                        { label: "Prev", action: "previous" },
                        { label: root.isPaused ? "Play" : "Pause", action: "toggle" },
                        { label: "Next", action: "next" },
                        { label: "Stop", action: "stop" }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: (parent.width - 18 * root.s) / 4
                        height: 30 * root.s
                        radius: 6 * root.s
                        color: mouseArea.containsMouse ? Theme.tileBg : "transparent"
                        border.width: 1
                        border.color: Theme.hair
                        opacity: root.hasCurrentStation && !actionProcess.running ? 1 : 0.45
                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: Theme.bright
                            font.family: Theme.font
                            font.pixelSize: 11 * root.s
                        }
                        MouseArea {
                            id: mouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: root.hasCurrentStation && !actionProcess.running
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.runPlayer(modelData.action, "")
                        }
                    }
                }
            }

            // --- volume ---------------------------------------------------
            Row {
                width: parent.width
                spacing: 8 * root.s

                Rectangle {
                    width: 30 * root.s
                    height: 24 * root.s
                    radius: 6 * root.s
                    color: muteArea.containsMouse ? Theme.tileBg : "transparent"
                    border.width: 1
                    border.color: Theme.hair
                    Text {
                        anchors.centerIn: parent
                        text: root.volumeValue === 0 ? "Mute" : "Vol"
                        color: Theme.bright
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
                    }
                    MouseArea {
                        id: muteArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.service)
                                root.service.setVolume(root.volumeValue === 0 ? 70 : 0)
                        }
                    }
                }

                Item {
                    width: Math.max(0, parent.width - 80 * root.s)
                    height: 24 * root.s

                    Rectangle {
                        id: volumeTrack
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 5 * root.s
                        radius: 3 * root.s
                        color: Theme.hair
                        Rectangle {
                            width: parent.width * (root.volumeValue / 100)
                            height: parent.height
                            radius: parent.radius
                            color: Theme.accent
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: function(mouse) {
                            root.setVolumeFromX(mouse.x, volumeTrack.width)
                        }
                    }
                }

                Text {
                    width: 36 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: root.volumeValue + "%"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                }
            }

            // --- tabs -----------------------------------------------------
            Row {
                width: parent.width
                spacing: 6 * root.s

                Repeater {
                    model: [
                        { key: "favorites", label: "Favorites" },
                        { key: "recent", label: "Recent" },
                        { key: "search", label: "Search" }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: (parent.width - 12 * root.s) / 3
                        height: 24 * root.s
                        radius: 6 * root.s
                        color: root.tab === modelData.key ? Theme.accent : "transparent"
                        border.width: 1
                        border.color: root.tab === modelData.key ? Theme.accent : Theme.hair
                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: root.tab === modelData.key ? Theme.bright : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 11 * root.s
                            font.weight: root.tab === modelData.key ? Font.DemiBold : Font.Normal
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.tab = modelData.key
                        }
                    }
                }
            }

            TextField {
                width: parent.width
                height: 28 * root.s
                visible: root.tab === "search"
                placeholderText: "Search stations…"
                text: root.query
                foreground: Theme.bright
                accent: Theme.accent
                font.family: Theme.font
                font.pixelSize: 11 * root.s
                onTextChanged: root.query = text
                onAccepted: root.runSearch()
            }

            // --- list -----------------------------------------------------
            ListView {
                id: stationList
                width: parent.width
                height: Math.min(root.listModel.length * 32 * root.s, 164 * root.s)
                visible: root.listModel.length > 0
                clip: true
                spacing: 3 * root.s
                model: root.listModel
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    required property var modelData
                    width: stationList.width
                    height: 32 * root.s
                    radius: 6 * root.s
                    color: rowMouse.containsMouse ? Theme.tileBg : "transparent"

                    Row {
                        anchors.fill: parent
                        anchors.margins: 7 * root.s
                        spacing: 8 * root.s

                        Rectangle {
                            width: Math.max(0, parent.width - 94 * root.s)
                            height: parent.height
                            color: "transparent"
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                spacing: 1 * root.s
                                Text {
                                    width: parent.width
                                    text: root.stationName(modelData)
                                    color: Theme.bright
                                    font.family: Theme.font
                                    font.pixelSize: 11 * root.s
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    text: root.stationDetail(modelData)
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: 11 * root.s
                                    elide: Text.ElideRight
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.playStation(modelData.uuid)
                            }
                        }

                        Rectangle {
                            width: 40 * root.s
                            height: 22 * root.s
                            radius: 5 * root.s
                            color: Theme.accent
                            Text {
                                anchors.centerIn: parent
                                text: "Play"
                                color: Theme.bright
                                font.family: Theme.font
                                font.pixelSize: 11 * root.s
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: !actionProcess.running
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.playStation(modelData.uuid)
                            }
                        }

                        Rectangle {
                            width: 26 * root.s
                            height: 22 * root.s
                            radius: 5 * root.s
                            color: "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: root.isFavorite(modelData) ? "★" : "☆"
                                color: root.isFavorite(modelData) ? Theme.accent : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 13 * root.s
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleFavorite(modelData.uuid)
                            }
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }
                }
            }

            Text {
                visible: root.listModel.length === 0
                width: parent.width
                wrapMode: Text.WordWrap
                text: root.tab === "search"
                    ? "No stations found. Type a name and press Enter."
                    : (root.tab === "recent" ? "Nothing played yet."
                        : "No favorites yet. Star a station in the Radio Atlas panel.")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 11 * root.s
            }

            // --- audio output --------------------------------------------
            Row {
                width: parent.width
                spacing: 6 * root.s
                visible: root.outputChoices.length > 1

                Repeater {
                    model: root.outputChoices
                    delegate: Rectangle {
                        required property var modelData
                        width: (parent.width - 6 * root.s * (root.outputChoices.length - 1))
                            / root.outputChoices.length
                        height: 22 * root.s
                        radius: 5 * root.s
                        color: root.outputId === modelData.id ? Theme.accent : "transparent"
                        border.width: 1
                        border.color: root.outputId === modelData.id ? Theme.accent : Theme.hair
                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 8 * root.s
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData.label !== undefined ? modelData.label : String(modelData.id)
                            color: root.outputId === modelData.id ? Theme.bright : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 11 * root.s
                            elide: Text.ElideRight
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.service) root.service.chooseOutput(modelData.id)
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.errorText !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: root.errorText
                color: Theme.verm
                font.family: Theme.font
                font.pixelSize: 11 * root.s
            }
        }
    }
}
