// MyOS Settings.
// This runs as its own small Quickshell instance, so a bug here can never
// break the main desktop shell (shelf and launcher).

import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    id: app

    property int page: 0
    property string selectedSsid: ""
    property string wifiStatus: ""
    property string aboutText: "Loading..."
    property real vol: 0.5
    property real bri: 0.7
    property var networks: []

    readonly property var pages: ["Wi-Fi", "Sound & Display", "Keyboard", "Wallpaper", "About"]
    readonly property var wallpapers: ["wallpaper.png", "wallpaper-2.png", "wallpaper-3.png", "wallpaper-4.png"]
    readonly property bool isHypr: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ? true : false

    // ----- Wi-Fi -----
    function parseWifi(text) {
        var lines = text.split("\n")
        var seen = {}
        var out = []
        for (var i = 0; i < lines.length; i++) {
            var p = lines[i].split(":")
            if (p.length < 3) continue
            var sec = p[p.length - 1]
            var sig = parseInt(p[p.length - 2])
            var ssid = p.slice(0, p.length - 2).join(":").replace(/\\:/g, ":")
            if (ssid === "" || seen[ssid]) continue
            seen[ssid] = true
            out.push({ ssid: ssid, signal: sig, secure: sec !== "" && sec !== "--" })
        }
        out.sort(function (a, b) { return b.signal - a.signal })
        networks = out
    }
    function scanWifi() { scan.running = false; scan.running = true }
    function connectWifi(ssid, pw) {
        var cmd = ["nmcli", "dev", "wifi", "connect", ssid]
        if (pw.length > 0) cmd = cmd.concat(["password", pw])
        connect.command = cmd
        wifiStatus = "Connecting to " + ssid + "..."
        connect.running = false
        connect.running = true
    }

    Process {
        id: scan
        command: ["nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY", "dev", "wifi", "list", "--rescan", "yes"]
        stdout: StdioCollector { onStreamFinished: app.parseWifi(text) }
    }
    Process {
        id: connect
        stdout: StdioCollector { onStreamFinished: { if (text.trim().length) app.wifiStatus = text.trim() } }
        stderr: StdioCollector { onStreamFinished: { if (text.trim().length) app.wifiStatus = text.trim() } }
    }

    // ----- read current values -----
    Process {
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var m = text.match(/([0-9.]+)/)
                if (m) app.vol = Math.min(1, parseFloat(m[1]))
            }
        }
    }
    Process {
        command: ["brightnessctl", "-m"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var p = text.trim().split(",")
                if (p.length >= 4) app.bri = Math.max(0, Math.min(1, parseInt(p[3]) / 100))
            }
        }
    }
    Process {
        command: ["sh", "-c", "uname -r; hostname; awk '/MemTotal/ {printf \"%.1f GB\\n\", $2/1048576}' /proc/meminfo"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var l = text.trim().split("\n")
                app.aboutText = "System:  MyOS 0.1 (Debian 13 base)\nKernel:  " + l[0] + "\nHostname:  " + l[1] + "\nMemory:  " + l[2]
            }
        }
    }

    function setWallpaper(name) {
        var path = "/usr/share/backgrounds/myos/" + name
        Quickshell.execDetached(["sh", "-c",
            "mkdir -p \"$HOME/.config/myos\"; echo '" + path + "' > \"$HOME/.config/myos/wallpaper\"; pkill swaybg; swaybg -i '" + path + "' -m fill"])
    }

    Component.onCompleted: scanWifi()

    // Simple slider (0 to 1)
    component QSlider: Item {
        id: sl
        property real value: 0.5
        signal moved(real v)
        height: 28
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: 6; radius: 3
            color: "#DCE3F2"
            Rectangle { width: parent.width * sl.value; height: parent.height; radius: 3; color: "#4C7BDE" }
        }
        Rectangle {
            x: (sl.width - width) * sl.value
            anchors.verticalCenter: parent.verticalCenter
            width: 20; height: 20; radius: 10
            color: "#4C7BDE"
        }
        MouseArea {
            anchors.fill: parent
            function setFrom(mx) { sl.value = Math.max(0, Math.min(1, mx / sl.width)) }
            onPressed: (m) => setFrom(m.x)
            onPositionChanged: (m) => { if (pressed) setFrom(m.x) }
            onReleased: sl.moved(sl.value)
        }
    }

    // Pill button
    component PBtn: Rectangle {
        id: pb
        property string label
        property color tint: "#4C7BDE"
        property color fg: "#FFFFFF"
        signal clicked()
        width: lbl.width + 36; height: 38; radius: 19
        color: pm.containsMouse ? Qt.darker(tint, 1.08) : tint
        Text { id: lbl; anchors.centerIn: parent; text: pb.label; color: pb.fg; font.pixelSize: 13 }
        MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; onClicked: pb.clicked() }
    }

    FloatingWindow {
        id: win
        title: "Settings"
        implicitWidth: 780
        implicitHeight: 520
        color: "#F7F8FC"
        onVisibleChanged: if (!visible) Qt.quit()

        // ----- sidebar -----
        Rectangle {
            id: side
            width: 200
            height: parent.height
            color: "#EEF1F8"
            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 6
                Text { text: "Settings"; font.pixelSize: 20; font.bold: true; color: "#1F2433"; bottomPadding: 10 }
                Repeater {
                    model: app.pages
                    delegate: Rectangle {
                        id: item
                        required property string modelData
                        required property int index
                        width: parent.width; height: 40; radius: 20
                        color: app.page === index ? "#D6E3FB" : (im.containsMouse ? "#E3E9F6" : "transparent")
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            text: item.modelData
                            font.pixelSize: 14
                            color: "#1F2433"
                        }
                        MouseArea { id: im; anchors.fill: parent; hoverEnabled: true; onClicked: app.page = item.index }
                    }
                }
            }
        }

        // ----- content -----
        Item {
            x: side.width
            width: parent.width - side.width
            height: parent.height

            // Page 0: Wi-Fi
            Item {
                anchors.fill: parent
                anchors.margins: 24
                visible: app.page === 0
                Column {
                    anchors.fill: parent
                    spacing: 12
                    Row {
                        spacing: 16
                        Text { text: "Wi-Fi"; font.pixelSize: 22; font.bold: true; color: "#1F2433"; anchors.verticalCenter: parent.verticalCenter }
                        PBtn { label: "Rescan"; tint: "#E3E9F6"; fg: "#1F2433"; onClicked: app.scanWifi() }
                    }
                    Rectangle {
                        width: parent.width; height: 230; radius: 16; color: "#FFFFFF"
                        ListView {
                            anchors.fill: parent
                            anchors.margins: 6
                            clip: true
                            model: app.networks
                            delegate: Rectangle {
                                id: nrow
                                required property var modelData
                                width: ListView.view.width; height: 40; radius: 12
                                color: app.selectedSsid === modelData.ssid ? "#D6E3FB" : (nm.containsMouse ? "#F1F3F8" : "transparent")
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left; anchors.leftMargin: 14
                                    text: nrow.modelData.ssid
                                    font.pixelSize: 14; color: "#1F2433"
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.right: parent.right; anchors.rightMargin: 14
                                    text: (nrow.modelData.secure ? "locked   " : "open   ") + nrow.modelData.signal + "%"
                                    font.pixelSize: 12; color: "#667"
                                }
                                MouseArea { id: nm; anchors.fill: parent; hoverEnabled: true; onClicked: app.selectedSsid = nrow.modelData.ssid }
                            }
                        }
                    }
                    Row {
                        spacing: 10
                        Rectangle {
                            width: 280; height: 38; radius: 19; color: "#FFFFFF"
                            TextInput {
                                id: pw
                                anchors.fill: parent
                                anchors.leftMargin: 16; anchors.rightMargin: 16
                                verticalAlignment: TextInput.AlignVCenter
                                echoMode: TextInput.Password
                                font.pixelSize: 14
                                color: "#1F2433"
                                clip: true
                                Text {
                                    visible: pw.text.length === 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Password (leave empty if saved or open)"
                                    font.pixelSize: 12; color: "#8A91A8"
                                }
                            }
                        }
                        PBtn {
                            label: "Connect"
                            onClicked: { if (app.selectedSsid !== "") app.connectWifi(app.selectedSsid, pw.text) }
                        }
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: app.selectedSsid === "" ? "Select a network from the list." : ("Selected: " + app.selectedSsid)
                        font.pixelSize: 13; color: "#667"
                    }
                    Text { width: parent.width; wrapMode: Text.WordWrap; text: app.wifiStatus; font.pixelSize: 13; color: "#1F2433" }
                }
            }

            // Page 1: Sound and display
            Item {
                anchors.fill: parent
                anchors.margins: 24
                visible: app.page === 1
                Column {
                    anchors.fill: parent
                    spacing: 14
                    Text { text: "Sound & Display"; font.pixelSize: 22; font.bold: true; color: "#1F2433" }
                    Text { text: "Volume"; font.pixelSize: 14; color: "#667" }
                    QSlider {
                        width: parent.width
                        value: app.vol
                        onMoved: (v) => Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", v.toFixed(2)])
                    }
                    PBtn {
                        label: "Mute / unmute"
                        tint: "#E3E9F6"; fg: "#1F2433"
                        onClicked: Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
                    }
                    Text { text: "Brightness (laptops)"; font.pixelSize: 14; color: "#667"; topPadding: 12 }
                    QSlider {
                        width: parent.width
                        value: app.bri
                        onMoved: (v) => Quickshell.execDetached(["brightnessctl", "set", Math.max(5, Math.round(v * 100)) + "%"])
                    }
                }
            }

            // Page 2: Keyboard
            Item {
                anchors.fill: parent
                anchors.margins: 24
                visible: app.page === 2
                Column {
                    anchors.fill: parent
                    spacing: 14
                    Text { text: "Keyboard"; font.pixelSize: 22; font.bold: true; color: "#1F2433" }
                    Text { text: "Layouts: English (US) and Arabic"; font.pixelSize: 14; color: "#1F2433" }
                    Text { text: "Shortcut to switch: Alt + Shift"; font.pixelSize: 14; color: "#667" }
                    PBtn {
                        label: "Switch layout now"
                        onClicked: Quickshell.execDetached(app.isHypr
                            ? ["hyprctl", "switchxkblayout", "all", "next"]
                            : ["swaymsg", "input", "type:keyboard", "xkb_switch_layout", "next"])
                    }
                }
            }

            // Page 3: Wallpaper
            Item {
                anchors.fill: parent
                anchors.margins: 24
                visible: app.page === 3
                Column {
                    anchors.fill: parent
                    spacing: 14
                    Text { text: "Wallpaper"; font.pixelSize: 22; font.bold: true; color: "#1F2433" }
                    Flow {
                        width: parent.width
                        spacing: 14
                        Repeater {
                            model: app.wallpapers
                            delegate: Rectangle {
                                id: wp
                                required property string modelData
                                width: 160; height: 96; radius: 12
                                color: "#DCE3F2"
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    source: "file:///usr/share/backgrounds/myos/" + wp.modelData
                                    sourceSize: Qt.size(320, 192)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                                MouseArea { anchors.fill: parent; onClicked: app.setWallpaper(wp.modelData) }
                            }
                        }
                    }
                }
            }

            // Page 4: About
            Item {
                anchors.fill: parent
                anchors.margins: 24
                visible: app.page === 4
                Column {
                    anchors.fill: parent
                    spacing: 14
                    Text { text: "About"; font.pixelSize: 22; font.bold: true; color: "#1F2433" }
                    Text { text: app.aboutText; font.pixelSize: 14; color: "#1F2433"; lineHeight: 1.5 }
                }
            }
        }
    }
}
