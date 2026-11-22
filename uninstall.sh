#!/usr/bin/env bash
# omarchy-mihomo 卸载脚本
# 移除: 服务 / 内核 / polkit / 插件 / 菜单条目提示
# 保留: ~/.config/mihomo（订阅地址与备份，可手动删除）
set -uo pipefail

PLUGIN_ID="${PLUGIN_ID:-omarchy-mihomo}"
log()  { echo -e "\033[1;36m==> $*\033[0m"; }
ok()   { echo -e "\033[1;32m  ✓ $*\033[0m"; }

log "1/6 停止并移除 systemd 单元"
ROOT_STAGE=$(mktemp /tmp/omarchy-mihomo-uninstall.XXXXXX.sh)
cat > "$ROOT_STAGE" <<'ROOT'
#!/bin/bash
systemctl disable --now mihomo-sub-update.service mihomo.service 2>/dev/null || true
rm -f /etc/systemd/system/mihomo.service /etc/systemd/system/mihomo-sub-update.service
rm -f /etc/polkit-1/rules.d/49-omarchy-mihomo.rules
rm -f /usr/local/bin/mihomo /usr/local/bin/mihomo-sub-deploy
rm -rf /etc/mihomo
systemctl daemon-reload
echo "ROOT_OK"
ROOT
chmod +x "$ROOT_STAGE"
if command -v pkexec >/dev/null 2>&1; then
  pkexec bash "$ROOT_STAGE" && ok "系统组件已移除"
else
  echo "pkexec 不可用，请手动: sudo bash $ROOT_STAGE"
fi

log "2/6 移除 shell 插件"
omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
rm -rf "$HOME/.config/omarchy/plugins/$PLUGIN_ID"
ok "插件已移除"

log "3/6 移除命令行工具"
rm -f "$HOME/.local/bin/mihomo-ctl" "$HOME/.local/bin/mihomo-sub-update"
ok "已移除 ~/.local/bin/{mihomo-ctl,mihomo-sub-update}"

log "4/6 菜单条目"
echo "  如需移除菜单，请编辑 ~/.config/omarchy/extensions/omarchy-menu.jsonc"
echo "  删除以 \"vpn\" 开头的条目（或整行含 vpn. 的条目）"

log "5/6 用户数据"
echo "  已保留 ~/.config/mihomo（订阅地址/备份）"
echo "  如需彻底清理: rm -rf ~/.config/mihomo"

log "6/6 重启 shell"
omarchy restart shell >/dev/null 2>&1 || true
ok "卸载完成"
