# openwrt-dell-dw5821e

在 **OpenWrt 25 (apk)** 上安装 **Dell DW5821e**（富士康 T77W968 / 高通骁龙 X20 LTE）调制解调器的脚本：一次运行即可在全新系统上部署 MBIM 驱动、创建网络接口，并安装 [4IceG](https://github.com/4IceG) 面板 —— `3ginfo-lite`、`sms-tool-js`、`modemband`。

![OpenWrt](https://img.shields.io/badge/OpenWrt-25.x%20(apk)-blue)
![Shell](https://img.shields.io/badge/shell-POSIX%20sh-green)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

[Русский](README.md) · [English](README.en.md) · **中文**

---

该脚本会安装在 OpenWrt 25 上运行和监控 Dell DW5821e 所需的一切，并自动创建一个即用型接口。第二个脚本（卸载器）可彻底还原所有更改（便于测试，无需重刷固件）。

### 为什么需要它

DW5821e 是基于高通骁龙 X20 LTE（Cat16）的 M.2 调制解调器。它通过 **MBIM** 协议工作（`/dev/cdc-wdm0`），而其 AT 端口是 `option`/`ttyUSB*` 设备。该调制解调器有**两个** AT 端口（`ttyUSB0` 和 `ttyUSB1`，都会回应 `OK`），但完整遥测数据来自 `ttyUSB1`；`ttyUSB2` 是 GPS/NMEA，`ttyUSB3` 是诊断端口。要在 OpenWrt 上启用它并读取数据，需要特定的软件包组合和正确的端口/接口绑定。脚本会自动完成这一切，将 4IceG 面板指向正确的端口，并修复该调制解调器特有的 JSON 无效错误（见"已知问题"）。

### 脚本做了什么

1. 询问 **APN**（默认 `internet`）以及是否安装面板的**俄语**翻译（`[Y/n]`）。
2. 安装 MBIM 栈：`kmod-usb-net-cdc-mbim`、`umbim`、`luci-proto-mbim`，以及 AT 端口驱动（`kmod-usb-serial`、`kmod-usb-serial-option`）和 `sms-tool`。
3. 添加 [4IceG/Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) apk 软件源及其签名密钥（幂等）。
4. 安装 `luci-app-3ginfo-lite`、`luci-app-sms-tool-js`、`luci-app-modemband`（如选择则含俄语语言包）。
5. **检测 MBIM 设备**（`/dev/cdc-wdm*`）用于接口；面板使用的 AT 端口固定为 `/dev/ttyUSB1`（该调制解调器的工作端口）。
6. 创建 **`LTE_DELL_5821`** 接口（协议 `mbim`、检测到的 cdc-wdm 设备、输入的 APN、`pdptype`），并将其加入 `wan` 防火墙区域。
7. 将面板绑定到正确的端口：3ginfo（`device` = ttyUSB1 + `network` = LTE_DELL_5821）、modemband（`set_port` + `iface`）、sms-tool（5 个端口），并将短信前缀设为 `7`。
8. 安装 **短信接收** 初始化脚本：开机时等待 AT 端口就绪，然后将来信路由到 SIM 存储（`CPMS`）并启用新消息提示（`CNMI`）—— 否则在 MBIM 模式下短信接收无法在重启后保持。
9. 在 `3ginfo.sh` 中应用 **`\r` 修复** —— 否则 LuCI 会显示红色横幅 `Bad control character in string literal in JSON`。
10. 重启路由器（10 秒倒计时，可用 `Ctrl+C` 取消）。

### 要求

- 使用 **apk** 包管理器的 OpenWrt **25.x**（不适用于 opkg 版本）。
- **Dell DW5821e / Foxconn T77W968** 调制解调器，已插入并被识别（存在 `/dev/cdc-wdm0` 和 `/dev/ttyUSB*`）。
- 安装时路由器需**联网**（通过其他上行链路或已工作的调制解调器）—— 需要下载软件包和密钥。
- 具有 root 权限的 **SSH** 访问。

### 安装

在**路由器上**运行（通过 SSH）：

```sh
wget https://raw.githubusercontent.com/lastik9/openwrt-dell-dw5821e/main/install-dw5821e.sh
sh install-dw5821e.sh
```

重启后，打开 **LuCI → Network → Interfaces**（`LTE_DELL_5821` 应显示 Carrier/RX/TX）以及 **LuCI → Modem(s)**（用 Ctrl+F5 强制刷新 —— 信号、运营商、频段）。

设置项在脚本顶部以变量形式给出：接口名称、防火墙区域、默认 APN、PDP 类型、PIN、短信前缀 —— 可在一处修改。

### 卸载

```sh
wget https://raw.githubusercontent.com/lastik9/openwrt-dell-dw5821e/main/uninstall-dw5821e.sh
sh uninstall-dw5821e.sh
```

卸载器会移除接口及其防火墙条目、删除软件包（面板和语言包）、清理面板配置、`\r` 修复的残留文件以及添加的软件源/密钥，然后重启。默认**保留**调制解调器驱动（以免中断连接）；在顶部设置 `REMOVE_DRIVERS=yes` 可一并删除。可安全重复运行。

### 已知问题

- **红色横幅 `Bad control character in string literal in JSON`** —— 该调制解调器的主要问题。高通 AT 响应使用 CRLF，杂散的 `\r` 会漏入 JSON 并破坏 LuCI 的解析。脚本会自动修复（步骤 8），在 `3ginfo.sh` 的 `sanitize_number()` 函数后追加 `| tr -d '\r\n'`。插件升级后需重新应用修复 —— 脚本会在 `/root/3ginfo.sh.fixed` 保存工作副本。详情：[issue #121](https://github.com/4IceG/luci-app-3ginfo-lite/issues/121)。
- **安装后 `Carrier: Absent`** —— 几乎都是 **APN** 错误。它取决于运营商：脚本默认使用 `internet`，但部分套餐不同。在接口上修正 APN 并 `Save & Apply`。
- **3ginfo 不显示数据** —— 检查 AT 端口。DW5821e 的工作端口是 `/dev/ttyUSB1`（不是 ttyUSB2 —— 那是 GPS）。检查命令：`sms_tool -d /dev/ttyUSB1 at ATI`。
- **收不到来信短信** —— 在 MBIM 模式下，高通调制解调器不会在重启后保留短信路由设置：重启后 `CPMS`/`CNMI` 被重置，来信无法到达 sms-tool（发送仍然正常）。脚本会安装 `/etc/init.d/dw5821e-sms`，开机时等待端口就绪并重新设置 `AT+CPMS="SM","SM","SM"` + `AT+CNMI=2,1,0,0,0`。若接收仍然失败，检查 `AT+CNMI?`（应为 `2,1,0,0,0`）和 `AT+CEREG?`（第二个字段为 `1` 表示已注册）。
- **断电后注册较慢** —— 完全断电（power-cycle）后，调制解调器会进行冷启动网络搜索，因此 LTE 注册和联网可能需要一两分钟（比普通 `reboot` 更久）。这是调制解调器的正常行为；短信也会在注册完成后才开始到达，而非立即。
- **锁频**（通过 modemband 或 `AT^SLBAND`）—— 请谨慎：锁定到你所在位置不存在的频段会导致调制解调器无法注册。查看当前锁定：`AT^SLBAND?`；重置：`AT^SLBAND`。在 Foxconn 固件上，频段更改**仅在调制解调器重启后**生效。部分固件的私有 AT 命令可能返回错误，此时无法控制频段。
- **在 Windows 上编辑脚本？** 请以 **LF (Unix)** 换行符保存。`#!/bin/sh` 中的 CRLF 会导致脚本在路由器上无法执行。仓库通过 `.gitattributes` 予以保护。

### 诊断

```sh
ls -l /dev/cdc-wdm* /dev/ttyUSB*                     # 调制解调器设备
sms_tool -d /dev/ttyUSB1 at 'ATI'                    # 调制解调器响应
sms_tool -d /dev/ttyUSB1 at 'AT+CESQ'                # 信号 (RSRP/RSRQ)
sms_tool -d /dev/ttyUSB1 at 'AT+COPS?'               # 运营商
sms_tool -d /dev/ttyUSB1 at 'AT^SLBAND?'             # 当前频段锁定
uci show network.LTE_DELL_5821                       # 接口配置
uci show 3ginfo; uci show modemband; uci show sms_tool_js
ifstatus LTE_DELL_5821 | grep -i up                  # 接口是否已启动
logread | grep -i mbim                               # MBIM 协议日志
```

### 测试环境

OpenWrt 25.12.x（mediatek/filogic，`aarch64_cortex-a53`），Dell DW5821e（骁龙 X20 LTE）。

### 致谢

本项目只是一个安装器。真正的工作在 **[4IceG](https://github.com/4IceG)** 的项目中：

- [luci-app-3ginfo-lite](https://github.com/4IceG/luci-app-3ginfo-lite) —— 调制解调器监控面板
- [luci-app-sms-tool-js](https://github.com/4IceG/luci-app-sms-tool-js) —— 短信 / USSD / AT 命令
- [luci-app-modemband](https://github.com/4IceG/luci-app-modemband) —— LTE 频段控制
- [Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) —— apk 软件包仓库

所安装的组件归其各自作者所有，并按其各自许可证分发。MIT 许可证仅涵盖本安装器的代码。

### 许可证

[MIT](LICENSE) © 2026 lastik9
