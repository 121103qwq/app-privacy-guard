# 桌面版使用指南

日常默认选择[本机非严格方案](desktop-local-guide.md)。它直接使用当前 Windows，保留原有显示与时区，提供两个专用 Edge 资料、Claude Desktop 和独立 Claude Code 启动入口。

从 Release 解压桌面工具后，按本机指南配置固定美国代理，执行一次准备脚本，再使用受控入口启动。新版工具支持只撤销本次新增的保护。

本机方案已用自有探针验证常用地区接口和启动过滤器。它仍有系统服务、辅助进程、更新路径和其他本机代理的覆盖缺口。两个新 Edge 入口、官方客户端和真实授权登录尚未验收，不能承诺极端条件下绝对零泄漏。

如果以后需要独立系统隔离，再参考[严格方案](desktop-strict-guide.md)。严格部署说明统一保留在该文档；它不是日常使用的前提。

- [MSIX 与 Setup 权限审计](package-audit.md)
- [测试结果与边界](test-report.md)
- [Windows URL 诊断记录](browser-url-diagnostics.md)
- [手机版使用指南](mobile-guide.md)
