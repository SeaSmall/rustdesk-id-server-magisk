# RustDesk ID Server — Magisk 模块

> ⚠️ **免责声明（DISCLAIMER）**
>
> 本模块及其附属脚本（install.sh / install.ps1 / README / 二进制等）按 **“按现状”（AS IS）** 提供，
> **不附带任何明示或暗示的担保**，包括但不限于适销性、特定用途适用性与非侵权性。
> 使用本工具需要在已 root 的安卓手机上运行第三方网络服务，**可能导致隐私泄露、数据丢失、
> 设备不稳定、被恶意利用、或违反服务商/运营商条款**。作者与贡献者**不对**因使用、误用或无法使用
> 本模块所造成的**任何直接、间接、附带、特殊、惩罚性或后果性损害**负责（包括但不限于业务中断、
> 数据损坏、设备损坏、利润损失或法律纠纷）。
> 在**生产/公网环境**部署前，请务必理解 RustDesk 服务器的安全模型、配置端口转发与访问控制，
> 自行评估风险。**RustDesk、hbbs、hbbr 及其商标均归其各自权利人所有**，本模块与其官方项目无关联。
> 本模块仅供学习与研究用途，**请勿用于任何非法活动**。使用即表示您已知晓并同意上述条款。

---

# RustDesk ID Server — Magisk 模块

在你的 **root 安卓手机**上运行 [RustDesk](https://rustdesk.com/) 的 **hbbs ID/rendezvous 服务器**，
把你的手机当自建 **ID 服务器** 使用。可选启动 hbbr 中继服务器。

- **服务器 key 随机生成**：每次安装自动生成，见“随机 key”一节
- **已内置 arm64 (aarch64) 静态二进制**：`bin/arm64/hbbs` 与 `bin/arm64/hbbr`，开箱即用
- **一键安装**：电脑端脚本自动完成“生成随机 key → 打包模块 → 推送手机 → 部署到 Magisk → 启动并校验”

> ✅ **已实测部署验证**：模块已成功部署到 Redmi K40 Gaming（arm64-v8a, Android 13, Root/Magisk 29），
> hbbs 通过官方 arm64 静态二进制稳定运行，端口 21115/21116/21118 正常监听。

---

## 目录结构

```
rustdesk-id-server/
├── module.prop          # 模块元数据
├── customize.sh         # Magisk 安装时运行（检测架构）
├── service.sh           # Magisk 开机自启（启动 hbbs / hbbr）
├── uninstall.sh         # Magisk 卸载清理
├── install.ps1          # ★ 电脑端一键安装脚本（Windows）
├── install.sh           # ★ 电脑端一键安装脚本（Linux / macOS）
├── config/
│   └── env.sh           # 配置（SERVER_KEY、端口、中继开关）
├── bin/
│   ├── arm64/           # 内置 hbbs / hbbr（aarch64 静态）
│   ├── arm/
│   ├── x86_64/
│   └── x86/
└── tools/
    └── build_binaries.sh # （可选）从源码交叉编译二进制的脚本
```

---

## 随机 key 说明

安装脚本会**为每次安装自动生成一个随机 key**（32 位安全随机字符，取自
`A-HJ-NP-Za-km-z2-9`，避免易混淆字符），并写入 `config/env.sh` 的 `SERVER_KEY`。
**客户端配置时必须填入这个 key**，且服务端/客户端 key 必须一致才能通信。

- 每次运行安装脚本，若不指定 `--key`，都会生成**新的随机 key**
- 想用固定 key：`--key 你的固定值`
- **请务必记录安装时打印的 key**，否则客户端无法连接

---

## 安装方式

### 方式一：一键脚本安装（推荐）

**前置条件：**
- 手机已 **root** 且装有 **Magisk**
- 电脑装有 **adb**（`winget install Google.PlatformTools` 或官网下载 platform-tools）
- 手机开启 **USB 调试**并授权电脑（开发者选项 → USB 调试；连接时点“允许”）

**Windows（PowerShell）：**
```powershell
.\install.ps1                 # 自动生成随机 key 并安装
.\install.ps1 -Key mykey123   # 指定固定 key
.\install.ps1 -Relay          # 同时启用 hbbr 中继服务器
.\install.ps1 -Serial xxxx    # 指定设备序列号
.\install.ps1 -OutOnly out.zip # 只打包不安装
```

**Linux / macOS：**
```bash
chmod +x install.sh
./install.sh                 # 自动生成随机 key 并安装
./install.sh --key mykey123  # 指定固定 key
./install.sh --relay         # 启用中继
./install.sh --serial xxxx   # 指定设备序列号
./install.sh --out-only out.zip  # 只打包
```

脚本会依次：定位 adb → 检测设备 → 检查 root/Magisk → 生成随机 key → 写入配置 →
打包 Magisk 模块 zip → 推送手机 → 解压到 `/data/adb/modules/rustdesk_id_server/` →
启动 hbbs → 校验运行并打印 key / 手机 IP。

### 方式二：手动安装（把 zip 装进 Magisk）

1. 用 `--out-only` 生成模块 zip（如 `.\install.ps1 -OutOnly rustdesk-id-server.zip`）
2. 把 zip 拷贝到手机
3. 打开 **Magisk Manager** → **模块** → **从本地安装** → 选择该 zip
4. 重启后 hbbs 自启；或手动执行 `service.sh`

---

## 客户端配置

在 RustDesk 客户端（电脑/手机）中：

| 设置项 | 值 |
|--------|-----|
| ID/中继服务器 | 填手机 **IP 地址**（如 `192.168.1.100`） |
| Key（公钥） | 安装时打印的随机 key（或 `--key` 指定的值） |

> 公网访问需在路由器把端口转发到手机（见下节），ID 服务器地址填公网 IP 或域名。

---

## 端口说明

| 端口 | 协议 | 用途 |
|------|------|------|
| 21115 | TCP | NAT 类型测试 |
| **21116** | **TCP + UDP** | **★ ID/rendezvous（hbbs 主端口，最关键）** |
| 21117 | TCP | 中继（hbbr，仅启用中继时用） |
| 21118 | TCP | WebSocket（网页客户端） |

**仅做 ID 服务器时，最关键的是转发 21116 的 TCP 和 UDP。**

- **手机本地访问**：同一局域网内，客户端直接填手机 IP + key，无需转发。
- **公网访问**：在路由器把 `21115`、`21116`（TCP+UDP）、`21117`、`21118` 转发到手机的局域网 IP；
  手机需固定 IP（DHCP 静态分配）。

---

## 配置修改

编辑 `config/env.sh`：

- `SERVER_KEY` — 服务器 key（安装脚本自动生成；可手动改）
- `ENABLE_RELAY` — `0` 仅 ID 服务器；`1` 同时启动中继
- `RELAY_HOST` — 中继地址（可选）
- `HBBS_PORT` / `HBBR_PORT` — 端口（一般不用改）
- `DATA_DIR` — 数据目录（默认 `/data/local/tmp/rustdesk`）

修改后重启模块服务或重启手机生效。

---

## 常见问题

- **hbbs 启动失败**：查看 `/data/local/tmp/rustdesk/rustdesk.log`
- **架构不匹配**：`getprop ro.product.cpu.abi` 查看，确认 `bin/<架构>` 有对应二进制
- **客户端连不上**：确认 21116 TCP/UDP 已放行、路由已转发、IP 正确、key 与服务端一致
- **key 不匹配**：客户端 key 必须与服务端 `SERVER_KEY` 完全一致
- **想要其他架构**：arm 为 32 位、x86/x86_64 为模拟器/少用；用 `tools/build_binaries.sh` 交叉编译

---

## 卸载

直接卸载 Magisk 模块即可（uninstall.sh 会停止服务并清理数据目录）。

---

## 参考

- RustDesk 官网：https://rustdesk.com
- RustDesk Server 源码：https://github.com/rustdesk/rustdesk-server
- RustDesk 客户端配置文档：https://rustdesk.com/docs/zh-cn/self-host/client-configuration/