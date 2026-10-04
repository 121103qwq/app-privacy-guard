# 桌面版使用指南

## 选择运行方式

严格目标应使用独立的美国英语 Windows 系统，并移除其虚拟网卡。官方 Claude 使用验签后的 MSIX。宿主保留正常的中文显示、时区和两个 Edge。登录用的 Edge、Claude Desktop、Claude Code 和回调处理器应全部位于独立系统。

当前测试主机没有 Windows Sandbox，也没有可运行的独立 Windows 客体。因此，下列客体部署步骤是待验收流程。文件代理、WFP 和两个空白 Edge 的测试已通过，不能替代官方 Claude 的客体运行验收。

## 准备固定出口

在宿主的代理核心配置一个只使用美国节点的 HTTP 代理，例如 `127.0.0.1:17992`。组内不要加入 DIRECT，节点不可用时停止连接。可参考 [proxy-only.example.yaml](../config/proxy-only.example.yaml)，自行填写节点信息。

宿主 broker 从该端口转发，网站域名由代理端处理。不要把客户端域名解析交给独立 Windows 的系统 DNS。

## 准备独立 Windows

使用全新、合法授权的 en-US Windows 客体。系统默认语言、系统区域、用户语言和时区均设为美国英语及 `Pacific Standard Time`。需要更改系统区域时，完成客体重启后再测试。

移除全部虚拟网卡，禁用共享剪贴板、拖放、USB、摄像头、麦克风和宿主目录映射。不要导入宿主的账号、浏览器资料、Cookie 或文件。全系统隔离还要求正确配置虚拟化平台；本项目未证明抵抗恶意客体逃逸。

文件 IPC 必须使用无需网卡的共享目录，例如 VirtualBox 的专用共享文件夹。不要通过 SMB 给无网卡客体提供代理目录，也不要让宿主与客体同时写同一个 VHDX。

只提供两个映射：只读的安装工具目录，以及专用的可读写 IPC 目录。IPC 目录不能放个人资料、配置凭据或其他文件。将工具复制到客体后即可撤销安装工具映射。

## 启动文件代理

从 Release 解压桌面工具。在宿主的管理员 PowerShell 中执行：

```powershell
$tools='C:\AppPrivacy\desktop'
$ipc='C:\AppPrivacy\ipc'
New-Item -ItemType Directory -Force $ipc | Out-Null
& "$tools\loopback-guard.exe" install "$tools\file-tunnel.exe" 17992
& "$tools\loopback-guard.exe" check "$tools\file-tunnel.exe" 17992
& "$tools\file-tunnel.exe" broker $ipc 17992
```

每次使用新的空 IPC 目录。WFP 规则只针对指定 broker 路径，允许 TCP 连接 `127.0.0.1:17992`，拒绝其他 IPv4、IPv6、端口和协议。不会改 Windows 防火墙全局配置。

在客体中将共享 IPC 目录映射为 `Z:\ipc`，工具放入 `C:\AppPrivacy\desktop`。运行：

```powershell
& 'C:\AppPrivacy\desktop\prepare-guest.ps1' `
  -IpcDirectory 'Z:\ipc' -Port 18080 `
  -MsixPath 'C:\AppPrivacy\Claude.msix'
```

该脚本发现已启用的网卡时会拒绝启动。它配置客体用户区域、时区和系统 HTTP 代理，并验证 MSIX 签名。工具只做文件转发，不直接连接网站，也不解析目标域名。

## 浏览器、客户端与回调

在客体创建两个空白 Edge 配置。按需载入 Release 的 `edge` 扩展目录。扩展仅作用于安装它的配置，宿主 Edge 不需要加载。旧资料中已运行的 Worker 可能保留环境信息，所以首次验收必须使用全新资料。

启动官方 Claude 时，确保浏览器打开操作留在客体。回调的 `claude:` 协议也应由客体中的客户端接收。Claude Code 同样在客体中运行；它忽略代理的连接只能失败，因为客体没有可用网卡。

先运行无账号 fixture，核对首屏、iframe、语言、Date、Intl 和回调状态。实际授权登录、WebView 兼容性和 Cowork 功能，本轮没有用真实账号验收。不要将浏览器模拟通过理解成官方客户端全流程通过。

## 退出与故障

先关闭客体应用和文件代理，再关闭 broker。停止 broker 或美国代理后，连接应失败，不能恢复客体网卡作为补救。

需要移除宿主规则时，只移除该 broker 路径：

```powershell
& 'C:\AppPrivacy\desktop\loopback-guard.exe' remove `
  'C:\AppPrivacy\desktop\file-tunnel.exe' 17992
```

新版本或新路径必须重新安装、核对规则。单独把 MSIX 安装到宿主，再加时区补丁和进程分流，仍可能通过系统服务、系统 DNS、未覆盖的 helper 或本机代理读取或转发信息。它不满足本指南的严格条件。
