#!/usr/bin/env bash
#
# omarchy-mihomo 一键安装脚本
# 在全新的 Omarchy (Arch/Hyprland) 系统上安装并配置：
#   mihomo 内核 + TUN 全局透明代理 + 状态栏 UI + 菜单集成 + 订阅更新
#
# 用法:
#   ./install.sh                    # 交互式（询问订阅地址）
#   MIHOMO_SUB_URL="https://..." ./install.sh   # 非交互
#
# 可选环境变量:
#   MIHOMO_SUB_URL   机场订阅链接（Clash 格式）
#   MIHOMO_VERSION   mihomo 版本（默认 v1.19.34）
#   PLUGIN_ID        Omarchy shell 插件 id（默认 omarchy-mihomo）
#   DRY_RUN=1        只打印将要执行的步骤
#
set -euo pipefail

# ---------------------------------------------------------------- 配置
MIHOMO_VERSION="${MIHOMO_VERSION:-v1.19.34}"
PLUGIN_ID="${PLUGIN_ID:-omarchy-mihomo.vpn}"   # Omarchy 插件 id 约定: 作者.名称
DRY_RUN="${DRY_RUN:-0}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CFG_DIR="$HOME/.config/mihomo"
BIN_DIR="$HOME/.local/bin"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
MENU_FILE="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"

GH_MIRRORS=("https://ghfast.top" "https://ghproxy.net" "")

log()  { echo -e "\033[1;36m==> $*\033[0m"; }
ok()   { echo -e "\033[1;32m  ✓ $*\033[0m"; }
warn() { echo -e "\033[1;33m  ⚠ $*\033[0m"; }
fail() { echo -e "\033[1;31m  ✗ $*\033[0m"; exit 1; }

run() {
  if [ "$DRY_RUN" = "1" ]; then echo "  [dry-run] $*"; else "$@"; fi
}

# ---------------------------------------------------------------- 前置检查
log "1/9 环境检查"
[ "$(uname -m)" = "x86_64" ] || fail "仅支持 x86_64（其他架构请自行调整下载资产名）"
command -v systemctl >/dev/null || fail "需要 systemd"
if [ -z "${OMARCHY_PATH:-}" ] && [ ! -d "$HOME/.config/omarchy" ]; then
  fail "未检测到 Omarchy 环境（本项目的 UI 集成依赖 Omarchy shell）"
fi
command -v python3 >/dev/null || fail "需要 python3"
python3 -c "import yaml" 2>/dev/null || {
  warn "缺少 python-yaml，尝试安装…"
  run sudo pacman -S --noconfirm --needed python-yaml || \
    pkexec pacman -S --noconfirm --needed python-yaml || fail "python-yaml 安装失败"
}
command -v zenity >/dev/null 2>&1 || {
  warn "缺少 zenity（命令行更新订阅弹窗），尝试安装…"
  run sudo pacman -S --noconfirm --needed zenity || \
    pkexec pacman -S --noconfirm --needed zenity || warn "zenity 安装失败，CLI update-sub 弹窗不可用（不影响菜单）"
}
ok "环境检查通过"

# ---------------------------------------------------------------- 下载工具（带镜像回退）
gh_get() { # gh_get <github-url> <输出文件>
  local url="$1" out="$2" m
  for m in "${GH_MIRRORS[@]}"; do
    if [ -z "$m" ]; then
      log "    尝试 GitHub 直连"
      curl -sL -m 120 -o "$out" "$url" && [ -s "$out" ] && return 0
    else
      log "    尝试镜像 $m"
      curl -sL -m 120 -o "$out" "$m/$url" && [ -s "$out" ] && return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------- 订阅地址
log "2/9 配置订阅地址"
mkdir -p "$CFG_DIR"
SUB_URL="${MIHOMO_SUB_URL:-}"
if [ -z "$SUB_URL" ] && [ -f "$CFG_DIR/subscription-url" ]; then
  SUB_URL=$(head -1 "$CFG_DIR/subscription-url" | xargs)
fi
if [ -z "$SUB_URL" ] && [ "$DRY_RUN" != "1" ]; then
  echo
  echo "请粘贴机场订阅链接（Clash 格式订阅，通常在机场官网复制）:"
  read -r -e -i "${SUB_URL:-https://}" SUB_URL
fi
if [ -n "$SUB_URL" ]; then
  [[ "$SUB_URL" =~ ^https?:// ]] || fail "订阅地址需以 http(s):// 开头: $SUB_URL"
  printf '%s\n' "$SUB_URL" > "$CFG_DIR/subscription-url"
  ok "订阅地址已保存到 $CFG_DIR/subscription-url"
else
  warn "未配置订阅地址。安装后可通过状态栏 VPN 菜单 → 更新订阅 配置，"
  warn "或运行: $BIN_DIR/mihomo-ctl set-url <订阅链接>"
fi

# ---------------------------------------------------------------- mihomo 内核
log "3/9 安装 mihomo 内核 ($MIHOMO_VERSION)"
if [ "$DRY_RUN" = "1" ]; then
  echo "  [dry-run] 下载 mihomo-linux-amd64-compatible-$MIHOMO_VERSION.gz → /usr/local/bin/mihomo"
else
  WORK=$(mktemp -d /tmp/mihomo-install.XXXXXX)
  trap 'rm -rf "$WORK"' EXIT
  gh_get "https://github.com/MetaCubeX/mihomo/releases/download/$MIHOMO_VERSION/mihomo-linux-amd64-compatible-$MIHOMO_VERSION.gz" \
    "$WORK/mihomo.gz" || fail "mihomo 内核下载失败"
  gzip -df "$WORK/mihomo.gz"
  chmod +x "$WORK/mihomo"
  "$WORK/mihomo" -v >/dev/null || fail "下载的二进制无法运行"
  ROOT_STAGE="$WORK/root-stage.sh"   # 由第 7 步填充
  cp "$WORK/mihomo" "$WORK/mihomo.bin"
  ok "内核就绪"
fi

# ---------------------------------------------------------------- GeoIP 数据库
log "4/9 下载 GeoIP 数据库"
if [ "$DRY_RUN" = "1" ]; then
  echo "  [dry-run] Country.mmdb + geoip.dat → $CFG_DIR 与 /etc/mihomo"
else
  mkdir -p "$CFG_DIR"
  gh_get "https://github.com/Dreamacro/maxmind-geoip/releases/latest/download/Country.mmdb" \
    "$CFG_DIR/Country.mmdb" || fail "Country.mmdb 下载失败"
  gh_get "https://github.com/v2fly/geoip/releases/latest/download/geoip.dat" \
    "$CFG_DIR/geoip.dat" || true   # 可选文件
  [ "$(stat -c%s "$CFG_DIR/Country.mmdb")" -gt 1000000 ] || fail "Country.mmdb 不完整"
  ok "GeoIP 就绪 ($(stat -c%s "$CFG_DIR/Country.mmdb") bytes)"
fi

# ---------------------------------------------------------------- 生成配置
log "5/9 下载订阅并生成本地化配置"
if [ -n "$SUB_URL" ] || [ -f "$CFG_DIR/subscription-url" ]; then
  if [ "$DRY_RUN" = "1" ]; then
    echo "  [dry-run] bin/mihomo-sub-update（下载+补丁+校验）"
  else
    # 校验用内核通过环境变量传给 mihomo-sub-update（系统内核稍后由 root 阶段安装）
    export MIHOMO_BIN="$WORK/mihomo.bin"
    "$SCRIPT_DIR/bin/mihomo-sub-update" || fail "订阅更新失败（地址不可达或非 Clash 配置）"
    ok "配置已生成: $CFG_DIR/config.yaml"
  fi
else
  warn "跳过订阅下载（未配置地址）。mihomo 将以占位配置启动，配置地址后再更新。"
  if [ "$DRY_RUN" != "1" ]; then
    # 无订阅时给一份最小可启动配置（DNS/TUN 就绪，节点由后续订阅填充）
    cat > "$CFG_DIR/config.yaml" <<'MINIMAL'
mixed-port: 7890
allow-lan: false
bind-address: 127.0.0.1
mode: rule
log-level: info
external-controller: '127.0.0.1:9090'
dns:
    enable: true
    ipv6: false
    default-nameserver: [223.5.5.5, 119.29.29.29]
    enhanced-mode: fake-ip
    fake-ip-range: 198.18.0.1/16
    use-hosts: true
    nameserver: ['https://doh.pub/dns-query', 'https://dns.alidns.com/dns-query']
    proxy-server-nameserver: ['https://doh.pub/dns-query', 'https://dns.alidns.com/dns-query']
tun:
    enable: true
    stack: gvisor
    auto-route: true
    auto-detect-interface: true
    dns-hijack: ['any:53']
proxies: []
proxy-groups: []
rules:
  - MATCH,DIRECT
MINIMAL
  fi
fi

# ---------------------------------------------------------------- UI 插件
log "6/9 安装 Omarchy shell 插件 ($PLUGIN_ID)"
if [ "$DRY_RUN" = "1" ]; then
  echo "  [dry-run] 安装插件到 $PLUGIN_DIR 并启用"
else
  mkdir -p "$PLUGIN_DIR"
  for f in manifest.json Mihomo.qml SubDialog.qml; do
    sed "s/__PLUGIN_ID__/$PLUGIN_ID/g" "$SCRIPT_DIR/plugin/$f" > "$PLUGIN_DIR/$f"
  done
  omarchy plugin enable "$PLUGIN_ID" right >/dev/null 2>&1 || {
    qs ipc -p /usr/share/omarchy/shell call shell rescanPlugins >/dev/null 2>&1 || true
    sleep 2
    omarchy plugin enable "$PLUGIN_ID" right >/dev/null 2>&1 || \
      warn "插件启用失败，可手动: omarchy plugin enable $PLUGIN_ID right"
  }
  ok "插件已安装"
fi

# ---------------------------------------------------------------- 菜单集成
log "7/9 合并菜单条目"
if [ -f "$MENU_FILE" ]; then
  if grep -q '"vpn"' "$MENU_FILE"; then
    ok "菜单已包含 vpn 条目，跳过"
  else
    if [ "$DRY_RUN" = "1" ]; then
      echo "  [dry-run] python 合并 menu/omarchy-menu.example.jsonc 到 $MENU_FILE"
    else
      cp "$MENU_FILE" "$MENU_FILE.bak.$(date +%s)"
      python3 - "$MENU_FILE" "$SCRIPT_DIR/menu/omarchy-menu.example.jsonc" <<'PYEOF'
import sys, json, re
menu_file, example_file = sys.argv[1], sys.argv[2]
raw = open(menu_file, encoding='utf-8').read()
# 去掉 // 行注释与 /* */ 块注释（JSONC），保留字符串内的 //（如 https://）
def strip_jsonc(s):
    out, in_str, in_line, in_block = [], False, False, False
    i = 0
    while i < len(s):
        c = s[i]
        if in_str:
            out.append(c)
            if c == '\\' and i+1 < len(s): out.append(s[i+1]); i += 2; continue
            if c == '"': in_str = False
            i += 1; continue
        if in_line:
            if c == '\n': in_line = False; out.append(c)
            i += 1; continue
        if in_block:
            if s[i:i+2] == '*/': in_block = False; i += 2; continue
            i += 1; continue
        if c == '"': in_str = True; out.append(c); i += 1; continue
        if s[i:i+2] == '//': in_line = True; i += 2; continue
        if s[i:i+2] == '/*': in_block = True; i += 2; continue
        out.append(c); i += 1
    return ''.join(out)
existing = json.loads(strip_jsonc(raw))
example = json.loads(strip_jsonc(open(example_file, encoding='utf-8').read()))
home = __import__('os').path.expanduser('~')
plugin_id = __import__('os').environ.get('PLUGIN_ID', 'omarchy-mihomo')
for k, v in example.items():
    v = json.loads(json.dumps(v).replace('__HOME__', home).replace('__PLUGIN_ID__', plugin_id))
    existing[k] = v
open(menu_file, 'w', encoding='utf-8').write(json.dumps(existing, ensure_ascii=False, indent=2) + '\n')
print('    菜单已合并（原文件已备份）')
PYEOF
      ok "菜单已合并"
    fi
  fi
else
  if [ "$DRY_RUN" = "1" ]; then
    echo "  [dry-run] 写入 $MENU_FILE"
  else
    mkdir -p "$(dirname "$MENU_FILE")"
    sed "s|__HOME__|$HOME|g; s/__PLUGIN_ID__/$PLUGIN_ID/g" \
      "$SCRIPT_DIR/menu/omarchy-menu.example.jsonc" > "$MENU_FILE"
    ok "菜单已写入"
  fi
fi

# ---------------------------------------------------------------- root 阶段
log "8/9 安装系统组件（需要授权: polkit 密码框）"
if [ "$DRY_RUN" = "1" ]; then
  echo "  [dry-run] mihomo/sub-update 单元 + polkit 规则 + deploy helper + 启动服务"
else
  ROOT_STAGE=$(mktemp /tmp/omarchy-mihomo-root.XXXXXX.sh)
  {
    echo '#!/bin/bash'
    echo 'set -euo pipefail'
    echo "install -Dm755 '$WORK/mihomo.bin' /usr/local/bin/mihomo"
    echo "mkdir -p /etc/mihomo"
    echo "install -Dm644 '$CFG_DIR/Country.mmdb' /etc/mihomo/Country.mmdb"
    [ -f "$CFG_DIR/geoip.dat" ] && echo "install -Dm644 '$CFG_DIR/geoip.dat' /etc/mihomo/geoip.dat"
    echo "install -Dm644 '$SCRIPT_DIR/systemd/mihomo.service' /etc/systemd/system/mihomo.service"
    echo "sed \"s|__HOME__|$HOME|g\" '$SCRIPT_DIR/systemd/mihomo-sub-update.service' > /etc/systemd/system/mihomo-sub-update.service"
    echo "sed \"s|__HOME__|$HOME|g\" '$SCRIPT_DIR/polkit/omarchy-mihomo-deploy' > /usr/local/bin/mihomo-sub-deploy"
    echo "chmod 755 /usr/local/bin/mihomo-sub-deploy"
    # 用户配置已存在则直接部署
    echo "install -Dm644 '$CFG_DIR/config.yaml' /etc/mihomo/config.yaml"
    echo "install -Dm644 '$SCRIPT_DIR/polkit/49-omarchy-mihomo.rules' /etc/polkit-1/rules.d/49-omarchy-mihomo.rules"
    echo "chmod 644 /etc/polkit-1/rules.d/49-omarchy-mihomo.rules"
    echo "systemctl daemon-reload"
    echo "systemctl enable --now mihomo.service mihomo-sub-update.service"
    echo "sleep 3"
    echo "systemctl is-active --quiet mihomo.service || { echo 'mihomo 未运行'; exit 1; }"
  } > "$ROOT_STAGE"
  chmod +x "$ROOT_STAGE"
  if command -v pkexec >/dev/null 2>&1; then
    pkexec bash "$ROOT_STAGE" || fail "root 阶段执行失败"
  else
    warn "pkexec 不可用，请手动执行: sudo bash $ROOT_STAGE"
    fail "等待手动授权"
  fi
  ok "系统组件安装完成，mihomo 已运行"
fi

# ---------------------------------------------------------------- 收尾
log "9/9 重启 Omarchy shell 并验证"
if [ "$DRY_RUN" != "1" ]; then
  omarchy restart shell >/dev/null 2>&1 || warn "shell 重启失败，可手动: omarchy restart shell"
  sleep 5
  echo
  ok "安装完成！"
  echo
  echo "  状态栏右侧新增 VPN 盾牌图标（红=TUN全局 / 地球=仅代理 / 锁=已停止）"
  echo "  左键点击 → MiHomo VPN 菜单（启停/模式/TUN/更新订阅）"
  echo "  命令行: mihomo-ctl status | mihomo-ctl help"
  if [ -z "$SUB_URL" ]; then
    echo
    warn "订阅地址尚未配置：菜单 → 更新订阅 → 粘贴地址 → 确认"
  fi
  echo
else
  echo "  [dry-run] omarchy restart shell + 验证"
fi
