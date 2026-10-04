# 1.0.3 中文版构建验证

- 构建来源提交：`5a69460f1ec1f69ee9dd3231898fe18bfb891c33`。
- [成功的 GitHub Actions 构建](https://github.com/ghb997/location/actions/runs/37215024713)。
- 环境：GitHub macOS 15 runner、Xcode 26.3、Release、iphoneos。
- 175 项中英文资源及权限文案检查通过；14 项 Swift 核心回归测试通过。
- `xcodebuild` 与 IPA 结构校验通过。Swift 编译无错误；Xcode 因应用未使用 App Intents 跳过相关元数据生成，此提示不影响构建。
- IPA：`Locus-1.0.3-zh-Hans-unsigned.ipa`，4,356,250 字节。
- 包标识：`com.ghb997.location`；版本 `1.0.3`；构建号 `4`；最低 iOS `18.0`。
- Mach-O：arm64、iPhoneOS 设备平台。压缩包未发现异常路径、重复成员或符号链接。
- 中文资源包含 `Localizable.strings`、`InfoPlist.strings`，中文应用名称为“Locus 定位”。
- 没有嵌入签名证书、描述文件或 Mach-O 代码签名，需自行签名／通过兼容容器安装。
- SHA-256：`987a4e68b399ef02f5b4d85999b00e14e62cd87ac66324d3ebcf0ee722368237`。

工程文件由同一次成功构建的 XcodeGen 输出同步回仓库。源码配置以 `project.yml` 为准。

尚未验证：用户 iPhone 的签名安装、真实定位恢复、iOS 27 本机配对、长时间后台行为，以及中文界面在各屏幕尺寸上的实际显示。这些项目需要真机操作。
