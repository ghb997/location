# 1.1.1 中文版构建与成品验证

- 构建源码提交：`2421e8286d2bd3da7a6f34defcbfff6ba894343c`。
- [完整成功的 GitHub Actions 构建](https://github.com/ghb997/location/actions/runs/38122536328)。
- 环境：GitHub macOS 15 runner，Xcode 26 系列，iPhoneOS Release 设备构建。
- **104 项 Swift 自动测试，0 失败**。其中新增 9 项实际 `SpoofSession` 集成测试、10 项新系统定位请求生命周期测试、9 项路线预览与目标更新测试，以及 1 项恢复记录修复测试。
- 会话集成测试直接运行应用控制器，注入传输、时钟、定位服务及隔离偏好设置，验证重试耗尽后恢复、心跳、路线冻结、停止取消、迟到回调和恢复配置修复。
- **311 对中英文资源、295 个引用键**、权限文案与 Info.plist 检查通过。
- iOS Release 编译、IPA 打包及结构校验通过。最终测试和构建日志没有 Swift 警告或错误；Xcode 仅提示未依赖 App Intents，跳过其元数据提取。
- 成品经独立 IPA 静态检查：无异常路径、重复成员或符号链接；主程序未加密，没有描述文件、`_CodeSignature` 或 Mach-O 代码签名。

## 成品信息

| 项目 | 验证结果 |
| --- | --- |
| 文件 | `Locus-1.1.1-zh-Hans-unsigned.ipa` |
| 大小 | 4,808,990 字节 |
| Bundle ID | `com.ghb997.location` |
| 版本 / 构建 | 1.1.1 / 6 |
| 最低系统 | iOS 18.0 |
| 设备 / 架构 | iPhone、iPad；arm64、iPhoneOS 设备平台 |
| 语言 | en、zh-Hans；应用及权限资源齐全 |
| 坐标数据 | 主包离线大陆几何，固定 SHA-256 检查通过 |
| 许可 | Locus、idevice、coordtransform MIT 与 Natural Earth 来源说明齐全 |
| 签名 | 未签名，需要安装工具重新签名或兼容容器 |

IPA SHA-256：

```text
2df059d836b14f7bbe1a90d47a6668afc7d378a09910a80d8344a68e2f23cd51
```

工程文件由此成功构建的 XcodeGen 输出同步回仓库。源码配置仍以 `project.yml` 为准；生成工程和验证记录的后续提交不改变本次构建的应用源码或测试。

## 尚未进行的真机验收

设备、系统及安装方式尚未确定。首次配对、实际定位及停止恢复、苹果地图／高德对照、网络／VPN 切换、锁屏、一小时后台运行与耗电、较大字号和 iPad 视觉操作均未实测。完整矩阵见 [兼容性记录](COMPATIBILITY.zh-CN.md)。

自动测试验证可替换服务下的生产控制流程，不能证明原生服务、真实网络和 iOS 后台行为。发布不标注“真机全部兼容”。
