# Locus 定位 · 简体中文版

基于 [ChrisMack32/Locus](https://github.com/ChrisMack32/Locus) 的中文适配与稳定性改进版本，由 [ghb997/location](https://github.com/ghb997/location) 维护。保留原作者提交历史与 MIT 许可；此仓库是独立衍生版本。

Locus 使用 Apple 开发者定位模拟服务修改系统报告的位置，支持地图选点、地点搜索、摇杆移动、路线及 GPX 导入导出。

## 下载与使用

- [下载 IPA](https://github.com/ghb997/location/releases/latest)
- [中文安装指南](SETUP.md)
- [自动构建记录与临时下载](https://github.com/ghb997/location/actions/workflows/build-ipa.yml)
- [代码检查与优化说明](docs/REVIEW.zh-CN.md)

**最低 iOS 18.0，支持 arm64 iPhone / iPad。** 包标识为 `com.ghb997.location`。

发布的 `Locus-1.0.3-zh-Hans-unsigned.ipa` 是**未签名侧载包**，需通过自己的签名工具或兼容的 LiveContainer 环境安装，不能直接点击 IPA 安装。构建过程不需要上传 Apple 账号、证书或配对文件。

中文系统显示简体中文，并保留英文资源；可通过系统的应用语言设置选择语言。需要有效的 **RPPairing 文件、开发者模式及 LocalDevVPN**。iOS 18–26 需在电脑上用 idevice_pair 生成配对文件；上游的 iOS 27 本机配对入口予以保留，仍需对应系统的真机验证。

## 此版本的改进

- 完整覆盖界面、首次设置、权限提示、通知、错误和无障碍标签的简体中文资源。
- 定位服务通过串行后台队列异步调用，连接期间界面仍可响应；停止会排在已发出的定位请求之后执行，并忽略过期结果。
- 路线取消后不再继续发送下一点；按实际路段长度计算时间，并正确处理跨越日期变更线的经度插值。
- 使用 XML 解析 GPX，支持单／双引号、不同属性顺序、命名空间、轨迹点及路线点；拒绝无效坐标并限制文件体积和点数。
- 配对文件经过结构检查和 idevice 原生解析；原子替换保留写入失败时的旧文件，导入文件不参与备份。
- 隧道 IP 保存前校验；VPN 状态仅检查隧道接口，避免普通 Wi-Fi 地址造成误判。
- 选中搜索结果不会自动收藏；修复 iPad 导出分享的弹窗锚点，外部文件导入错误可见。
- 将状态栏、底部控制与地点管理拆为独立视图，并加入可重复执行的测试、汉化检查和 IPA 结构校验。

## 从源码构建

需要 macOS、**Xcode 26+** 和 XcodeGen。Windows 用户可直接使用本仓库的 GitHub Actions。

```bash
brew install xcodegen
xcodegen generate
open Locus.xcodeproj
```

`project.yml` 是项目配置的来源；添加文件或调整配置后请重新运行 `xcodegen generate`。

不签名编译：

```bash
xcodebuild -project Locus.xcodeproj -scheme Locus -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
```

若要通过 Xcode 直接安装到真机，请在 Signing & Capabilities 选择自己的开发者团队。GitHub Actions 自动运行测试、生成项目、编译真机应用并打包 IPA；构建产物保留 30 天，正式下载见 Releases。

## 验证

```bash
python3 scripts/check_localization.py
swift test
python3 scripts/verify_ipa.py /path/to/Locus-1.0.3-zh-Hans-unsigned.ipa
```

`swift test` 在 macOS 上运行 GPX、坐标和配对格式的回归测试，不依赖真机 FFI。完整 iOS 编译由 Actions 验证。编译和静态检查不能替代真机上的定位、恢复真实 GPS、后台运行和各签名工具兼容性测试。

## 已知边界

- 应用不含账号或统计服务。配对数据、收藏和最近记录保存在本机；地图、搜索和路线使用 Apple 地图网络服务。
- 后台存活受 iOS 限制，不能保证永久保持；开始定位模拟时建议使用 Wi-Fi。
- “骑行”是移动速度模式，当前 MapKit 规划使用驾车路线，不代表自行车专用路线。
- 某些应用会识别或拒绝开发者模拟位置；本项目不保证所有应用接受模拟位置。
- 本版未改写原始 idevice 二进制依赖，仍需随上游跟进系统兼容性。

## 许可与来源

[MIT 许可](LICENSE)。原始项目：[ChrisMack32/Locus](https://github.com/ChrisMack32/Locus)，基线提交 `83c8fb324983728e8f44759cfd834dc637ee38b5`。依赖 [jkcoxson/idevice](https://github.com/jkcoxson/idevice)，许可见 [Vendor/idevice/LICENSE](Vendor/idevice/LICENSE)。
