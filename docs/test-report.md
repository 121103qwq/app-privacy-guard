# 测试结果与边界

## 结论

两个空白 Edge、文件 IPC 代理、WFP 内核阻断和专用 Android APK 的合成测试已执行。没有使用真实 Claude 账号，没有请求公网直连 IP 基线。节点凭据、账号资料和签名私钥未纳入公开产物。

**仍未达到官方 Claude 全流程、任意极端条件下绝对零泄漏的验收标准。** 本机无可用的独立 Windows 客体；浏览器真实打开应用的权限弹窗、官方认证兼容性、手机系统 VPN 撤销竞态及真机网络切换，存在缺口。当前发布为预发布版。

交付复核发现，初次发布的扫描器在拦截列表中写入了可还原的服务器标识。已将清单移到工作区私有目录，并清理本次仓库历史和受影响的 Release 归档。后续扫描同时检查原文、转义文本和 UTF-16 字符串。GitHub 文件替换无法撤回第三方已经下载或缓存的旧副本。

## 已执行测试

| 测试 | 结果 | 证据与含义 |
| --- | --- | --- |
| 官方 MSIX 与本机 Setup 静态审计 | 通过 | 签名、版本、manifest、服务与安装器符号；不代表已运行客户端 |
| 两个空白 Edge 首屏 | 通过 | en-US、America/Los_Angeles、Accept-Language；未读取现有账号资料 |
| Date、Intl、原型构造器、冬夏时 | 通过 | 冬季偏移 480 分钟，夏季偏移 420 分钟 |
| iframe 首屏 | 通过 | 语言与时区为预设值 |
| Dedicated、Shared、Service Worker 与反射构造 | 通过 | 严格配置拒绝执行 |
| WebRTC 与定位 | 通过 | 接口被拒绝，无真实坐标采集 |
| 浏览器 mock 授权与 HTTP 回调 | 通过 | 正确 state 接受，错误 state 拒绝；只有 mock code |
| Windows OS 协议分发 | 通过 | 单独 ShellExecute 分发至 fixture；回调 state 和原生美国语言、时区通过；浏览器弹窗尚未验收 |
| 宿主 broker WFP | 通过 | IPv4 TCP 与其他 loopback 端口拒绝；实际观察到 5 次内核丢弃，其中 UDP 2 次、IPv6 1 次 |
| 文件代理访问与 broker 故障 | 通过 | 两个宿主进程间转发成功；broker 停止后关闭连接 |
| Android 首屏、iframe、反射与 mock 回调 | 通过 | 独立 Android 14 模拟器；系统使用 Tokyo 时区 canary，应用启动使用 fr-FR canary |
| Android IPv4、IPv6、DNS、UDP | 通过 | 文档保留地址探测；VPN 内观察到 IPv4 3 次、IPv6 1 次、UDP 2 次丢弃 |
| Android 美国出口预检 | 通过 | 显式代理访问 Cloudflare trace；仅保留国家是否为 US 的布尔值 |
| Android 普通 HTTPS 页面 | 通过 | 在保护就绪后打开无账号公开示例页面 |
| Android Java 默认地区 | 通过 | 修复 WebView 初始化重置后，实际读取 locale 与 timezone 为预设值 |
| Android 断代理与应用重启 | 通过 | 无效端口预检失败，网页拒绝创建；强制停止后重启保持关闭 |
| Android 系统设置断开 VPN | 部分通过 | 在独立模拟器的 Settings 中实际断开，重启应用没有 WebView；未证明撤销瞬间竞态不存在 |

UDP 的 `send()` 返回成功不代表发到了网络。本次改用 WFP 分类丢弃事件和 VPN TUN 的计数提供实际阻断证据。宿主外部 IPv6 文档地址因缺路由先失败，随后用 IPv6 loopback 检验全 IPv6 拒绝规则；它不能证明真实 IPv6 网络切换。

机器可读结果位于 [evidence](evidence)。最终 APK 的故障和重启结果另见 `android-runtime.json`。测试不保存远端 echo 的 IP 字段，也不提供本机真实 IP 对照。

## 发现并修复的问题

- 旧桌面规则允许所有 loopback 端口。新版 broker 只允许一个指定 TCP 端口，拒绝其他本机代理绕行。
- Worker 和 WebRTC 存在原型构造器路径。严格配置对全局与原型构造器一起阻止；首次注入时的构造器别名冲突也已修复。
- Android socket 的文件描述符延迟创建，导致 `protect()` 失败。改为先绑定本地 socket，再保护，期间不发包。
- 切换手机代理时旧页面可能仍在运行。现在先关闭页面，并以配置代数拒绝过期预检结果。
- Android WebView 初始化可能重置 Java 默认语言。现在在页面创建后和应用恢复时重新应用本进程区域，并读取 Java 层结果复核。
- 文件代理遇到单方向 EOF 时过早关闭，可能丢失末尾响应。已修复双方向结束流程。

## 尚未验证的情况

官方 Claude Desktop、CoworkVMService、SSH helper 和 Claude Code 在无网卡 Windows 客体中的完整运行；浏览器权限弹窗确认后的 OS 协议交接；真实登录和账户行为；手机真机、系统重启、休眠恢复、移动网络切换、VPN 强制撤销的窗口，以及所有原生或指纹推断。

Windows 浏览器弹窗测试被工具安全检查中止，原因是工具无法可靠核实当前浏览器 URL。停止后没有继续进行 Windows 界面输入。该缺口不能由单独通过的 OS 协议分发测试消除。

独立 Windows 方案隔离整个客体网络，能够在结构上约束系统 DNS 和辅助进程。但仅有方案和源代码，不能算已经验收。文件共享平台、客体逃逸、宿主权限提升和恶意本地程序也超出本轮证明范围。

本项目的边界是目标应用与测试流量。代理入口会知道接入方 IP，运营商和宿主正常联网的软件没有被全机隔离。无法诚实声称“所有观察者都看不到真实 IP”。
