# App Privacy Guard

面向指定应用的出口保护、地区信息测试和无账号回调测试工具。当前版本为 **0.2.1 预发布版**。

**官方 Claude 桌面版建议使用验签后的 MSIX。日常默认采用本机非严格方案，无需虚拟机，Windows 原有显示与时区保持正常。** MSIX 本身不是权限沙箱。手机端提供专用浏览器 APK；Via 脚本仅用于地区接口补丁。

本项目没有实现“任意软件、任意故障下绝对零泄漏”的证明。官方 Claude 的隔离系统运行、真实认证兼容性和手机 VPN 被系统强制撤销时的竞态，仍有验证缺口。请先阅读 [测试结果与边界](docs/test-report.md)。所有已执行的测试均未使用真实 Claude 账号。

## 下载与使用

- [桌面版使用指南](docs/desktop-guide.md)
- [本机非严格方案](docs/desktop-local-guide.md)
- [Windows URL 诊断记录](docs/browser-url-diagnostics.md)
- [手机版使用指南](docs/mobile-guide.md)
- [MSIX 与 Setup 权限审计](docs/package-audit.md)
- [测试结果与边界](docs/test-report.md)
- [构建与复测](docs/development.md)

Release 提供签名 APK、本机启动器与地区修正模块、桌面文件代理工具、Edge 扩展、Via 脚本、源码归档和 SHA-256 校验文件。0.2.1 的 Android APK 保持 0.2.0 的已验收字节。官方 Claude 安装包、代理凭据和 APK 签名私钥均不分发。

## 保护的结构

本机非严格方案：目标程序 → 进程内代理与地区修正 → 固定美国 HTTP 代理。WFP 阻止已覆盖程序的直接 IPv4、IPv6 出站，保留本机代理与回调使用的 loopback。包内已发现的 EXE 分别安装规则；共享系统服务、其他本机代理、更新后的新路径和全部原生读取仍有缺口。

桌面严格方案：独立 Windows → 本机文件代理 → 专用共享目录 → 宿主 broker → 固定美国代理。独立 Windows 移除全部虚拟网卡。原生程序、服务、DNS、IPv6 和 UDP 因而无法自行从网卡出站。该方案的文件代理已在两个宿主进程间实测，独立 Windows 与官方客户端尚未实测。

手机版：专用 WebView → 本机桥接代理 → 指定上游。仅覆盖本 APK 的 VPN 丢弃其他 IP 数据包，只有桥接代理的指定 socket 被放行。VPN、文档首屏注入、显式代理和美国出口预检就绪后，才允许普通页面打开。

地区脚本在首个文档脚本前修改常用 Date、Intl 和语言接口，并拒绝 Worker、WebRTC、定位和媒体请求。它会损失部分网页功能，也无法覆盖任意原生系统读取或所有浏览器指纹。

保护目标是减少目标网站读取真实网络和地区信息的机会。代理入口仍能看到接入方 IP，操作系统和运营商也不受网页脚本控制。

本机地区修正模块使用 MinHook，相关 BSD 许可见 [licenses/minhook-bsd.txt](licenses/minhook-bsd.txt)。其第三方源码保留在 `desktop/local/vendor/minhook`。
