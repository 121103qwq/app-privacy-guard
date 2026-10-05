# 手机版使用指南

## 使用哪个应用

严格测试使用 Release 中的 **App Privacy Browser APK**。这是本项目的专用浏览器，不是官方 Claude Android 客户端，也不会接管官方客户端的数据。

Via 脚本只能修改部分网页接口。Via 是否及时执行首屏脚本、WebView 子进程、系统 DNS 和直连回退，都不由脚本控制。因此，单独安装 Via 脚本不能满足严格出口保护要求。

APK 最低要求 Android 10。系统 WebView 必须支持显式代理和文档首屏注入。不支持时，应用拒绝创建浏览页面。

## 安装和核验

下载 APK 与 SHA256SUMS，核对文件 SHA-256。发布 APK 的签名证书 SHA-256 为：

```text
76040fb6af6360f6b4f8d2a679c197147eca5255a2f1cd4c3f3a67d312f1958d
```

安装包只申请网络、前台服务和 VPN 服务能力，没有定位、相机、麦克风、联系人或外部存储权限。它关闭备份，普通网页没有本地 JavaScript 接口。

## 准备手机代理

APK 接受 HTTP 或 HTTPS TCP 代理，不直接实现 Reality 或 Hysteria 2。可以在手机的独立代理进程中使用 Mihomo，以**关闭 VPN/TUN 的代理模式**运行。该进程提供 `127.0.0.1:17992`，再通过 Reality 或 Hy2 连接美国节点。

例如，在能够运行 Mihomo 的终端环境中，将示例配置填写到私有目录后运行：

```sh
mihomo -f proxy-only.yaml
```

配置参考 [proxy-only.example.yaml](../config/proxy-only.example.yaml)。示例地址属于文档保留网段，必须替换。保持 `tun.enable=false`、`allow-lan=false` 和最终规则 `MATCH,US-fixed`。组内没有 DIRECT。

Android 同时只提供一个 VPN 位置。本 APK 的应用专用 VPN 与另一个代理应用的 VPN 模式会冲突。要使用本方案，上游必须提供无需自身 VPN 的本机代理。这条真机部署路径尚未实测；模拟器使用宿主的固定美国代理。

远程代理需填写数字 IP、端口，勾选 TLS，并填写证书对应的域名。证书校验失败时连接停止。域名只用于 SNI 和证书核验，不触发本机对代理地址的 DNS 查询。当前 APK 不支持上游代理账号认证，远程服务的访问控制需要另行正确配置；推荐先使用本机代理路径。

## 操作步骤

1. 本机代理填写 `127.0.0.1` 和 `17992`。仅 Android 模拟器使用 `10.0.2.2` 访问宿主。
2. 点 `Start guard`，按 Android 的提示授权本应用建立 VPN。
3. 等待 `US egress verified`。失败时普通网页不能打开，只有离线测试可用。
4. 点 `Run synthetic app-browser-callback flow`。检查 `en-US`、`America/Los_Angeles`，再点 `Simulate authorization`。状态应显示模拟回调已验证。
5. 点 `Probe blocked IPv4 / IPv6 / DNS / UDP`。直连应失败，并出现相应丢包计数。
6. 普通页面仅输入 HTTPS 地址，再点 `Open HTTPS URL`。退出用 `Stop guard`，应用先关闭浏览页面，再关闭保护。

修改代理后再次点 `Start guard`，旧页面会关闭，并重新检查出口。上游不可用时不回退直连。应用重启后不会自动恢复网页，必须重新启动保护。

模拟测试不使用真实账号，只验证 mock 状态与回调。本应用拒绝把链接交给外部应用；因此它不能替官方 Claude App 完成登录回调。Google 等服务可能拒绝嵌入式 WebView 登录，本轮未用真实账号测试这些兼容性。

## Google 登录页面

Via 脚本的 `https://*/*` 范围包含 `accounts.google.com`。需要在 Via 中保持脚本对 Google 登录页启用，并使 Claude 与 Google 使用同一可靠代理。真实首屏执行时机仍取决于 Via；跳到其他浏览器或官方 App 后，脚本不能继续保护新应用。

专用 APK 会对在内部打开的 Google 页面应用原有地区补丁和网络保护。但 Google 对嵌入式浏览器有 OAuth 限制，参见[官方 OAuth 政策](https://developers.google.com/identity/protocols/oauth2/policies)。不能把页面范围覆盖当作 Google 登录兼容性通过。本项目没有修改浏览器标识来规避这些限制。

## 保护范围与限制

VPN 仅选择本 APK 的 UID，其余软件不经过这个丢弃通道。上游代理进程也不在该 UID 中。网站的出口取决于上游规则，所以只检查一次国家代码，不能证明代理以后永远保持美国出口。

定位、Worker、Service Worker、WebRTC、WebTransport、相机和麦克风接口会被拒绝。这可能影响登录、音视频、缓存和其他网页功能。Date、Intl 与常用语言接口有首屏补丁；字体、原生系统服务和所有指纹推断不在其证明范围。

系统撤销 VPN 时，应用会关闭桥接并结束进程。但撤销与进程结束之间的竞态、厂商后台管理、系统重启、网络切换和真机兼容性尚未全部验收。不要把应用专用 VPN 的普通断代理结果当作系统强制撤销下的绝对证明。

## Via 补充脚本

将 `via-us-privacy.user.js` 导入 Via 的脚本功能，开启对应站点。脚本元数据请求 `document-start`，实际执行时机依赖 Via 版本。必须重新打开网页，并另行配置可靠代理和断线保护。它没有控制网络出口的能力，不应单独作为严格方案使用。
