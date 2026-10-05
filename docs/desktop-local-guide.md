# 桌面本机非严格方案

本方案直接使用当前 Windows，不需要虚拟机。Windows 显示语言和时区保持原设置。两个专用 Edge 资料、Claude Desktop 和独立 Claude Code 使用固定美国代理。启动器只在指定进程内修正常用地区接口。

这是便于日常使用的方案。已经覆盖的程序路径会被阻止直接出网，但它不能保证所有原生读取、系统服务、辅助进程和任意故障下都不泄漏信息。官方 Claude 账号和完整认证兼容性未实测。

## 下载与安装

官方 Claude Desktop 选择验签后的 MSIX，正常安装到本机。原因是包内容和权限清单可在安装前核对；它仍包含全信任程序和 LocalSystem 服务。Setup 起始为 `asInvoker`，不能代表安装后的权限更低。

从 Release 下载桌面 ZIP，解压到 `C:\AppPrivacy`。本机工具位于 `C:\AppPrivacy\desktop\local`。源码、MinHook 许可和 SHA256SUMS 一并提供。不要把工具放进临时目录，保护规则依赖固定程序路径。

如果已经使用旧版工具的受控快捷方式，可以继续使用。新版安装脚本保留已有的 WFP 规则和全局启动钩子；遇到已有启动钩子时，不会覆盖它。

## 固定美国出口

先让现有代理核心提供 `127.0.0.1:17992` HTTP 代理。它可以通过 Reality 或 Hy2 连接美国节点。本机工具不直接实现这两种协议。

该端口必须固定使用美国节点。组内不加入 DIRECT；连接失败时停止。可以填写 [proxy-only.example.yaml](../config/proxy-only.example.yaml)，或复用已经配置好的专用监听端口。其他软件仍按现有代理规则使用网络。

只有网页代理扩展、系统代理开关或进程分流，不能独立提供断线阻断。下面的 WFP 规则才负责阻止已覆盖程序的直接 IPv4 和 IPv6 连接。

## 一次性准备

安装好目标程序后，在管理员 PowerShell 中运行：

```powershell
$tools='C:\AppPrivacy\desktop\local'
& "$tools\setup.ps1" -IncludeEdge -RegisterStartup
```

脚本枚举已安装 Claude MSIX 包内的 EXE、已发现的独立 Claude Code EXE，以及 Edge。WFP 仅针对这些程序路径。它保留 loopback，供本机代理和授权回调使用，不修改整机防火墙配置。

`-RegisterStartup` 为发现的 `claude.exe` 创建按完整路径匹配的启动过滤器。它让协议回调或其他入口启动时也经过启动器。已有的其他启动调试器会被保留，此时应使用旧受控入口或下面的手动入口。保存的所有权记录用于只撤销本次新增项。

Edge 的多个资料共用一个程序路径，所以 Edge 网络规则会覆盖同一路径的所有资料。现有 Edge 窗口应继续使用本机代理；未设置代理的直连会失败。其他应用不受这些 Edge 规则影响。

## 日常启动

先启动美国代理，再启动目标软件。两个 Edge 资料相互独立，不导入现有账号资料：

```powershell
$tools='C:\AppPrivacy\desktop\local'
& "$tools\start-edge.ps1" -Profile one
& "$tools\start-edge.ps1" -Profile two
```

两个窗口使用 en-US 和固定 HTTP 代理。0.2.2 的地区扩展覆盖 Claude、Claude.com、Anthropic 和 `accounts.google.com`。Google、reCAPTCHA 和 gstatic 的 `/recaptcha/` 页面也在范围内。普通 Google 搜索页和其他站点保留原有网页接口；受保护页面会拒绝 Worker、WebRTC 和定位。

扩展目录为 `desktop/local/edge`。如果当前 Edge 不接受启动参数加载扩展，需在这两个专用资料中按 Edge 的扩展管理流程加载该目录。首次使用须核对扩展确实已加载，不能把生成目录当作已启用。已有 0.2.1 扩展需更新到 0.2.2，再关闭旧登录页并重新打开。

启动客户端：

```powershell
& 'C:\AppPrivacy\desktop\local\start-desktop.ps1'
& 'C:\AppPrivacy\desktop\local\start-code.ps1'
```

启动器检查目标程序的 IPv4、IPv6 保护规则，缺失时拒绝启动。它设置本进程的代理和语言环境，再载入地区修正模块。常用 Win32 语言、地理区域、时区、日期换算和特定注册表读取返回美国预设值；系统设置和其他进程保持原样。

这部分只在自有探针中验证。它没有覆盖所有底层系统调用、ICU 缓存、字体、系统服务或新子进程。仅由共享 `node.exe` 运行的 npm 版 Code 不在自动覆盖范围内，不能为了它把整机 Node 都封锁。

## 应用与浏览器交接

先从受控入口启动 Desktop，再由该应用发起浏览器授权。登录浏览器应是上述专用 Edge 资料，回调仍由官方 `claude:` 协议接收。不要把授权链接交给未配置的其他浏览器。启动器不会自动把系统默认浏览器切换到专用资料；若应用打开了其他资料，首屏已经可能读取该资料的环境。这仍是非严格方案的缺口。

选择 Google 登录时，浏览器会跨站跳转。Google 官方 OAuth 授权端点为 `https://accounts.google.com/o/oauth2/v2/auth`，参见 [Google OAuth 文档](https://developers.google.com/identity/protocols/oauth2/web-server)。使用顺序如下：

1. 确认专用 Edge 已加载 0.2.2 扩展，再在这个资料内打开 Claude 授权页。
2. 选择 Google 登录。Google 登录、账号选择和同意页面仍需留在这个资料内；同资料的新标签页或弹窗也使用该扩展。
3. Google 页面从文档首屏应用美国语言和 Pacific 时区补丁，请求头使用 `en-US,en;q=0.9`。网页出口继续通过固定美国代理，不因域名变成 Google 而改用其他分组。
4. Google 返回 Claude 后，Claude 页面继续使用补丁，再由官方协议完成应用回调。

扩展对验证码页面使用单独的路径规则，不对普通 Google 搜索页应用地区补丁。`www.recaptcha.net` 是 Google 文档列出的替代来源，参见 [reCAPTCHA FAQ](https://developers.google.com/recaptcha/docs/faq)。

目前只完成离线的跨站范围和脚本检查。两个模拟资料的 Claude → Google → 同意页 → Claude 回调，在各自的 JavaScript 环境中返回美国预设值。常见验证码 URL 和 `about:blank` 子页面也通过范围检查。这不是实际 Edge 加载或真实 Google 登录验收。

验证码路径规则没有宽泛的来源回退，其 `data:` 或 `blob:` 子页面仍有覆盖缺口。Google 若依赖被禁用的 Worker 或其他能力，登录也可能失败。其他认证域名、已有 Worker、浏览器权限弹窗和客户端辅助进程，仍未获得完整证明。

本项目的测试只使用 mock state 和 code。不会登录、读取或操作真实 Claude 账号。工具的 Windows URL 确认故障也尚未修复，详见 [URL 诊断记录](browser-url-diagnostics.md)。

## 更新、故障与撤销

客户端更新后，程序路径可能改变。首次启动新版本前，重新运行 `setup.ps1` 并核对结果。自动更新后的新服务和辅助路径可能先于刷新规则运行，不能声称版本更新期间也有完整保护。

代理停止时，已覆盖程序的直接出网会被阻断。loopback 仍可访问，因此其他本机代理可能形成绕行；系统 DNS 服务、未覆盖的系统程序、SYSTEM helper 和外部应用也不在完整证明范围内。无需使用的 Cowork、SSH 或 MCP 功能应保持关闭，避免增加辅助进程范围。

需要撤销新版工具新增的保护时，在管理员 PowerShell 中运行：

```powershell
& 'C:\AppPrivacy\desktop\local\undo.ps1'
```

撤销读取本次所有权记录，只移除它新增的规则和启动过滤器。原有保护、Edge 资料和文件会保留。它不会撤销工作区旧版工具拥有的规则。

如果以后需要隔离系统服务和全部原生读取，再参考[严格方案](desktop-strict-guide.md)。本指南的默认选择是直接在本机使用。
