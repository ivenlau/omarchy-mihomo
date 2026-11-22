import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  // 由 shell 注入
  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool updating: false
  property string statusMsg: ""
  property bool statusOk: false

  readonly property string ctlPath: Quickshell.env("HOME") + "/.local/bin/mihomo-ctl"

  // 直角主题
  readonly property color bgColor: Commons.Color.menu.background
  readonly property color fgColor: Commons.Color.menu.text
  readonly property color borderColor: Commons.Color.menu.border
  readonly property color scrim: Commons.Color.menu.scrim
  readonly property color accent: Commons.Color.accent

  function open(payloadJson) {
    root.opened = true
    root.updating = false
    root.statusMsg = ""
    urlInput.text = ""
    getUrlProc.running = true
  }

  function close() { root.opened = false }

  function dismiss() {
    if (root.updating) return
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "__PLUGIN_ID__")
  }

  function confirmUpdate() {
    var u = urlInput.text.trim()
    if (!/^https?:\/\//.test(u)) {
      root.statusOk = false
      root.statusMsg = "地址需以 http:// 或 https:// 开头"
      return
    }
    root.updating = true
    root.statusOk = true
    root.statusMsg = "正在更新订阅，请稍候…"
    confirmProc.command = [root.ctlPath, "do-update", u]
    confirmProc.running = true
  }

  // 外部触发: qs ipc -p /usr/share/omarchy/shell call __PLUGIN_ID__.sub open
  IpcHandler {
    target: "__PLUGIN_ID__.sub"
    function open(): string { root.open("{}"); return "ok" }
    function ping(): string { return "ok" }
  }

  Process {
    id: getUrlProc
    command: [root.ctlPath, "get-url"]
    stdout: StdioCollector {
      onStreamFinished: { urlInput.text = text.trim() }
    }
  }

  Process {
    id: confirmProc
    stdout: StdioCollector { onStreamFinished: {} }
    onExited: function(exitCode) {
      root.updating = false
      root.statusOk = exitCode === 0
      root.statusMsg = exitCode === 0 ? "✓ 订阅已更新并部署" : "✗ 更新失败（地址不可达或返回内容无效）"
    }
  }

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "__PLUGIN_ID__-sub"
    color: "transparent"

    // 全屏遮罩
    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    // 直角卡片
    Rectangle {
      id: card
      width: 560
      height: 320
      radius: 0
      anchors.centerIn: parent
      color: root.bgColor
      border.color: root.borderColor
      border.width: 1

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        anchors.fill: parent
        anchors.margins: 32
        spacing: 18

        Text {
          text: "VPN 订阅更新"
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          color: root.fgColor
        }

        Text {
          text: "订阅地址："
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: root.fgColor
        }

        // 拉长的直角输入框
        Rectangle {
          id: urlBox
          width: parent.width
          height: 44
          radius: 0
          color: Qt.darker(root.bgColor, 1.15)
          border.color: urlInput.activeFocus ? root.accent : root.borderColor
          border.width: 1

          TextInput {
            id: urlInput
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            color: root.fgColor
            selectionColor: root.accent
            selectedTextColor: root.bgColor
            selectByMouse: true
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            activeFocusOnTab: true
            // 回车 = 确认, Esc = 返回
            Keys.onReturnPressed: if (!root.updating) root.confirmUpdate()
            Keys.onEnterPressed: if (!root.updating) root.confirmUpdate()
            Keys.onEscapePressed: root.dismiss()
          }
        }

        Text {
          text: root.statusMsg
          visible: root.statusMsg !== ""
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: root.statusOk ? "#98c379" : "#e06c75"
          wrapMode: Text.WrapAnywhere
          width: parent.width
        }

        Item { width: 1; height: 1 } // 弹性占位

        // 返回 / 确认 一行显示
        Row {
          width: parent.width
          height: 44
          spacing: 14

          Rectangle {
            width: (parent.width - parent.spacing) / 2
            height: parent.height
            radius: 0
            color: retMouse.containsMouse ? Qt.darker(root.bgColor, 1.2) : Qt.darker(root.bgColor, 1.08)
            border.color: root.borderColor
            border.width: 1

            Text {
              anchors.centerIn: parent
              text: "返回"
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              color: root.fgColor
            }
            MouseArea {
              id: retMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.dismiss()
            }
          }

          Rectangle {
            width: (parent.width - parent.spacing) / 2
            height: parent.height
            radius: 0
            color: root.updating ? Qt.darker(root.accent, 1.5) : (confMouse.containsMouse ? Qt.lighter(root.accent, 1.15) : root.accent)
            border.color: root.accent
            border.width: 1
            enabled: !root.updating

            Text {
              anchors.centerIn: parent
              text: root.updating ? "更新中…" : "确认"
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
              color: root.bgColor
            }
            MouseArea {
              id: confMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: root.updating ? Qt.WaitCursor : Qt.PointingHandCursor
              enabled: !root.updating
              onClicked: root.confirmUpdate()
            }
          }
        }
      }

      // 键盘: Esc = 返回
      Item {
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) root.dismiss()
        }
      }
    }

    onShownChanged: {
      if (shown) Qt.callLater(function() { urlInput.forceActiveFocus() })
    }
  }
}
