# 构建与复测

## 构建

桌面工具使用 Windows 自带的 .NET Framework 4.8 C# 编译器，以及 Visual Studio 的 x64 C++ 构建工具。Android 使用 JDK 17、Gradle 8.7、Android SDK 34 和 AGP 8.5.1。

```powershell
node tools/build-assets.mjs
& desktop/build.ps1
& desktop/local/build.ps1
gradle -p android assembleRelease
```

将 Android SDK 路径填写到私有的 `android/local.properties`。签名用自己的密钥和 `apksigner`，不把密钥或密码提交到 Git。项目不分发构建 JDK，当前主机曾因 Java 的 Unix domain pipe 出错使用私有 TCP pipe 修复；这不是 APK 运行依赖。

## 桌面复测

安装 Playwright 到自己的构建环境。设置 `PLAYWRIGHT_PACKAGE` 指向其 package.json，或在项目目录安装依赖，再运行：

```powershell
node tests/desktop-flow.mjs
python tests/file-tunnel-test.py
```

Edge 测试使用两个新建的空资料目录。测试服务器只绑定 loopback。文件代理测试要求 `127.0.0.1:17992` 是固定美国出口，并已为 broker 安装 loopback guard。它运行两个宿主进程，不会假装创建了 Windows 客体。

`tests/network-canary.cs` 只探测 loopback 和文档保留地址。编译该探针，为它安装规则，再运行 `loopback-guard observe`，可记录实际 WFP 丢弃事件。不要用公网直连 echo 来获取真实 IP 基线。

`tests/callback-fixture.cpp` 和 `tests/os-callback-flow.mjs` 用独立的 `appprivacy-fixture:` 协议测试 Windows 交接。需要构建 fixture，测试时由操作者在空白浏览器中处理打开应用的弹窗。它不注册或修改 `claude:`。本轮弹窗后的交接未验收，不能纳入已通过的浏览器测试结果。

## Android 复测

使用独立、空白 Android 模拟器，安装成功后才进行配置。可将模拟器时区设为 Tokyo、启动 locale 设为 fr-FR，作为测试 canary，不能用真实个人环境的地址作基线。

按手机版指南依次检查：保护未就绪时没有 WebView、US 出口预检、普通 HTTPS、mock 授权回调、IPv4/IPv6/DNS/UDP 丢包、断代理、停止和重新启动。应用日志只使用 `PrivacyFixture` 标签，记录地区测试与布尔结果，禁止记录 Cookie、IP、令牌、真实账号或代理密码。

发布前审查所有跟踪文件与归档，只取源码白名单。排除 runtime、私有数据、构建缓存、厂商安装器和签名私钥。Release 上传后重新下载资产，核对字节数与 SHA-256。

本机工具的复测只使用新编译的自有探针。为探针安装按完整路径匹配的启动过滤器，读取地区结果，比较宿主区域设置是否保持不变，再撤销测试规则。公开证据只保存布尔结果。不能为验证启动器而直接启动带真实账号的 Claude。

环境专用的拦截清单必须放在仓库外的私有 JSON 文件中，不能写入公开扫描器。运行 `python tools/scan-public.py --private-pattern-file <private-json>` 时，报告仅显示文件名和问题类型。扫描还会检查转义文本、UTF-16 字符串，以及解压后的 Release 内容。基本扫描不能识别所有私有数据，仍需核对发布白名单。
