# omarchy-mihomo

在 [Omarchy](https://omarchy.org/)（Arch Linux + Hyprland）上一键安装配置 [mihomo](https://github.com/MetaCubeX/mihomo)（Clash Meta 内核），并深度集成到 Omarchy 桌面：

- **TUN 全局透明代理** + HTTP/SOCKS 代理端口（7890）双模式
- **状态栏 VPN 图标**：盾牌（TUN 全局）/ 地球（仅代理端口）/ 锁（已停止），悬停显示当前节点
- **控制菜单**：启动/停止、规则/全局/直连模式切换、TUN 开关、订阅更新、状态通知
- **订阅更新弹窗**：查看/修改订阅地址，确认后自动下载、保留本地自定义设置、校验、备份、部署
- **分流**：国内直连、国外代理（订阅规则 + 本地补充），GeoIP 本地判定
- **免密管理**：polkit 仅放行 mihomo 相关两个 systemd 单元，UI 操作无需输密码

## 安装

全新 Omarchy 系统上：

```bash
git clone https://github.com/<你的用户名>/omarchy-mihomo.git
cd omarchy-mihomo
./install.sh
```

或一行远程安装：

```bash
curl -fsSL https://raw.githubusercontent.com/<你的用户名>/omarchy-mihomo/main/install.sh | bash
```

安装脚本会：

1. 检查环境（Omarchy / python-yaml），缺依赖自动装
2. 询问订阅地址（支持环境变量 `MIHOMO_SUB_URL` 非交互传入）
3. 下载 mihomo 内核与 GeoIP 数据库（GitHub 直连失败自动切换镜像）
4. 下载订阅并生成本地化配置（见下文"本地化补丁"），`mihomo -t` 校验后备份部署
5. 安装 systemd 系统服务（TUN）、polkit 免密规则、订阅部署单元
6. 安装状态栏插件与菜单条目，重启 Omarchy shell

安装需要 polkit 授权（图形密码框，wheel 组）。

## 使用

### 状态栏

右侧 VPN 图标：

- **左键** 打开 `MiHomo VPN` 菜单
- **中键** 循环模式：规则 → 全局 → 直连
- **右键** 快速开/关 TUN 透明代理
- **悬停** 显示运行状态、当前模式与节点

### 菜单

| 条目 | 说明 |
|---|---|
| 更新订阅 | 弹窗查看/修改订阅地址，确认立即更新 |
| 查看状态 | 通知显示运行状态、流量、到期时间 |
| 启动 / 停止服务 | ✓ = 运行中 |
| 规则模式 / 全局模式 / 直连模式 | ✓ = 当前模式 |
| TUN 透明代理 | ✓ = 全局接管；关闭后仅 7890 端口代理 |

### 命令行

```bash
mihomo-ctl status              # 状态摘要
mihomo-ctl update-sub          # 更新订阅（zenity 弹窗版，与菜单等效）
mihomo-ctl mode global         # 切换模式 rule|global|direct
mihomo-ctl toggle-tun          # 开/关 TUN
mihomo-ctl toggle-service      # 启停服务
mihomo-ctl set-url <url>       # 设置订阅地址（空值恢复默认）
mihomo-ctl get-url             # 查看当前订阅地址
mihomo-ctl help                # 全部命令
```

## 本地化补丁（订阅更新时自动保留）

订阅是 Clash YAML，脚本下载后自动应用以下本地设置再部署，订阅更新不会丢失：

- `dns`：启用内置 DoH（doh.pub / alidns）+ fake-ip + `proxy-server-nameserver`——绕过运营商 DNS 污染；**不配 fallback**（境外 DoH 直连不可达，只会导致解析超时）
- `tun`：gvisor 栈 + auto-route + dns-hijack
- 仅监听 `127.0.0.1`（不对局域网开放）
- 追加 `x.com` / `t.co` / `xtwitter.com` 域名规则（订阅自带规则通常不含）
- `allow-lan: false`、`external-controller: 127.0.0.1:9090`

## 架构

```
状态栏插件 (Mihomo.qml)  ──左键──▶  Omarchy 菜单 (omarchy-menu.jsonc vpn 条目)
        │                                 │ action
        │ IPC (qs ipc call)               ▼
        └──────────────▶ SubDialog.qml (overlay 订阅弹窗)
                                 │ Process
                                 ▼
                          ~/.local/bin/mihomo-ctl ──▶ mihomo REST API (127.0.0.1:9090)
                                 │ do-update                          (模式/TUN/节点热切换)
                                 ▼
                     mihomo-sub-update (下载/合并补丁/校验/备份)
                                 │
                                 ▼
                  mihomo-sub-update.service (root, polkit 免密)
                                 ▼
                     /etc/mihomo/config.yaml + mihomo.service (TUN, 7890)
```

- 模式与 TUN 切换走 REST API，即时生效无需 root
- 服务启停/部署走 polkit（免密范围仅限 `mihomo.service` 与 `mihomo-sub-update.service` 两个单元）
- 状态栏每 4 秒轮询一次，外部改动自动反映

## 目录

```
bin/                mihomo-ctl 控制脚本、mihomo-sub-update 订阅更新
plugin/             Omarchy shell 插件（状态栏 widget + 订阅弹窗 overlay）
systemd/            mihomo.service（TUN 系统服务）、mihomo-sub-update.service（部署）
polkit/             免密规则 + 部署 helper 模板
menu/               菜单条目模板（含 __HOME__/__PLUGIN_ID__ 占位符）
install.sh          一键安装
uninstall.sh        卸载
```

## 常见问题

**下载 GitHub 失败？** 脚本内置镜像回退（ghfast.top / ghproxy.net → 直连）。国内网络建议先在别处配好代理再装，或手动下载内核放 `/usr/local/bin/mihomo`。

**开机后 TUN 不工作？** 服务已配置等待网络就绪（NetworkManager-wait-online）。若仍异常：`sudo systemctl restart mihomo`。

**内核栈选择？** 使用 `gvisor`（纯用户态）。在部分新内核上 `system` 栈会出现 TCP 进 TUN 后无响应的兼容问题。

**换机场了？** 菜单 → 更新订阅 → 粘贴新地址 → 确认。地址保存在 `~/.config/mihomo/subscription-url`。

**想改插件 id？** `PLUGIN_ID=myvpn ./install.sh`

## 卸载

```bash
./uninstall.sh
```

`~/.config/mihomo`（订阅地址与备份）默认保留，可手动删除。

## 隐私与安全

- 仓库不含任何订阅地址/token——安装时输入，保存在本地 `~/.config/mihomo/subscription-url`
- polkit 免密范围严格限定 `mihomo.service` 与 `mihomo-sub-update.service`
- 代理仅监听本机回环

## 免责声明

本项目仅为工具集成，不提供任何代理服务。请遵守当地法律法规，使用合法的机场服务。
