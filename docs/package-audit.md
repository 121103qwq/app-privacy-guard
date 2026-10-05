# Claude Windows 安装包审计

## 安装建议

选择 **官方签名的 MSIX**。日常可以直接在本机安装并采用[非严格方案](desktop-local-guide.md)。推荐 MSIX 的原因是版本、完整内容和权限清单可在安装前核对。它不具有低权限浏览器沙箱的安全属性。

如果要求客户端的所有原生读取都只能获得美国地区信息，应隔离整个客户端系统。本机方案修正常用接口，无法覆盖原生程序、系统服务和辅助进程的全部读取；Windows 显示和原时区可以保持正常。

## 本次 MSIX

审计日期为 2026-10-05。来源为[官方下载页](https://claude.com/download)和[官方 MSIX 重定向](https://claude.ai/api/desktop/win32/x64/msix/latest/redirect)。

| 项目 | 实测结果 |
| --- | --- |
| 版本 | 2.19675.0.0，x64 |
| 大小 | 291,543,056 字节 |
| Authenticode | Valid，Anthropic, PBC |
| SHA-256 | `8355c3d28aa08d2e8d841596b41abce0a4fc3805cc9d74f6836d42176ab6b0f9` |
| 应用入口 | `Windows.FullTrustApplication` |
| 能力 | `runFullTrust`、`localSystemServices`、`packagedServices`、`unvirtualizedResources`、`internetClient` |
| 系统服务 | `CoworkVMService`，`cowork-svc.exe`，自动启动，账户为 `localSystem` |
| 防火墙声明 | Claude.exe 和 cowork-svc.exe；TCP 入站与出站；所有配置文件 |
| 其他入口 | `claude:` 协议、启动任务、执行别名、SSH askpass 与 proxy |
| 外部框架依赖 | 未声明外部框架包；Windows.Desktop 最低版本 10.0.18362.0 |

包内还包含 SSH broker、浏览器 native host 和 GitHub MCP helper。因此，针对单个 Claude.exe 的进程规则，不能自然覆盖完整客户端的联网范围。防火墙声明也不等于程序每次实际获得管理员权限；它表明安装和运行涉及更宽的系统集成。

## 本次 Setup.exe

使用本机 2026-09-26 下载的官方安装器做静态审计。本轮最新 Setup 链接返回 HTTP 403，未取得新的安装器，不能把旧安装器当作最新版本的现场证据。

| 项目 | 实测结果 |
| --- | --- |
| 大小 | 7,176,352 字节 |
| Authenticode | Valid，Anthropic, PBC |
| 安装器文件版本 | 1.0.0.0；不是客户端版本 |
| PE manifest | `requestedExecutionLevel=asInvoker`，`uiAccess=false` |
| SHA-256 | `477f60741634f5968647195c357d888a1233e10e8c4e94281167114097616ae7` |
| 静态符号 | `installMSIXPackage`、`installViaMSIX`、`addAppxPackage`、`uninstallMSIXPackageElevated`、`ShellExecuteEx`、`--msix-path`、`runas` |

`asInvoker` 仅表示安装器最初沿用启动者权限。后续 MSIX 部署、全用户安装和修复流程可以另行请求提权。静态符号支持“此安装器包含 MSIX 部署与提权修复路径”，并未证明每个安装分支都执行这些路径。

因此，不能据此得出“Setup 只申请普通权限，所以安装后的 Claude 更安全”。本轮也没有在宿主执行该安装器或安装 Cowork 系统服务。

## 复核方法

对所下载文件运行 `Get-AuthenticodeSignature` 和 `Get-FileHash -Algorithm SHA256`。用 ZIP 工具读取 MSIX 的 `AppxManifest.xml`。Setup 用 PE 资源工具读取 manifest，并查看安装器符号。

权限含义可参阅 Microsoft 的[应用能力声明](https://learn.microsoft.com/windows/uwp/packaging/app-capability-declarations)、[桌面服务扩展](https://learn.microsoft.com/uwp/schemas/appxpackage/uapmanifestschema/element-desktop6-service)和[执行权限清单](https://learn.microsoft.com/windows/win32/sbscs/application-manifests)。这些是静态权限解释，不能替代实际运行观察。
