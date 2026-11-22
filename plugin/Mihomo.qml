import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "__PLUGIN_ID__"

  // 状态（由 mihomo-ctl dump 提供）
  property bool running: false
  property bool tun: false
  property string mode: ""
  property string node: ""

  readonly property string ctlPath: Quickshell.env("HOME") + "/.local/bin/mihomo-ctl"

  // Nerd Font 图标（已验证存在于 JetBrainsMono NF）
  readonly property string iconRunningTun: "\uf132"   // fa-shield: TUN 全局接管
  readonly property string iconRunningPort: "\uf0ac"  // fa-globe: 仅代理端口
  readonly property string iconStopped: "\uf023"      // fa-lock: 已停止

  readonly property string iconText: {
    if (!root.running) return root.iconStopped
    return root.tun ? root.iconRunningTun : root.iconRunningPort
  }

  readonly property string tipText: {
    if (!root.running) return "VPN 已停止（点击启动）"
    var parts = ["VPN 运行中"]
    parts.push(root.mode === "global" ? "全局模式" : (root.mode === "direct" ? "直连模式" : "规则模式"))
    parts.push(root.tun ? "TUN开" : "TUN关")
    if (root.node !== "") parts.push(root.node)
    return parts.join(" | ")
  }

  function refresh() {
    if (!statProc.running) statProc.running = true
  }

  // 操作后立即刷新一次（稍等服务/API 生效）
  function refreshSoon() {
    refreshTimer.restart()
  }

  Process {
    id: statProc
    command: [root.ctlPath, "dump"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var d = JSON.parse(text)
          root.running = d.running === true
          root.tun = d.tun === true
          root.mode = d.mode || ""
          root.node = d.node || ""
        } catch (e) {
          root.running = false
        }
      }
    }
  }

  // 定时轮询（模式/TUN 可能被外部 API 改动）
  Timer {
    interval: 4000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // 操作后的快速刷新
  Timer {
    id: refreshTimer
    interval: 1200
    onTriggered: root.refresh()
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.iconText
    slotSize: Style.bar.statusSlot
    active: root.running
    tooltipText: root.tipText
    onPressed: function(b) {
      if (b === Qt.MiddleButton) {
        root.bar.run(root.ctlPath + " cycle-mode")
        root.refreshSoon()
      } else if (b === Qt.RightButton) {
        root.bar.run(root.ctlPath + " toggle-tun")
        root.refreshSoon()
      } else {
        root.bar.run("omarchy menu summon vpn")
      }
    }
  }
}
