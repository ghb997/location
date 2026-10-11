# 1.1.0 中文版构建与成品验证

- 构建源码提交：`1ff534e97f4d86e7e2561df8e9e2f23c262b599b`。
- [完整成功的 GitHub Actions 构建](https://github.com/ghb997/location/actions/runs/38110530356)。
- 环境：GitHub macOS 15 runner、Xcode 26.3、iPhoneOS 26.2 SDK、Release。
- **75 项 Swift 核心测试，0 失败**；覆盖 GPX/路线、时钟与取消、恢复标记及重试、端点发现策略、串行停止、原生迟到回调、配对取消、坐标与迁移。
- **298 对中英文资源、283 个引用键**、权限文案与 Info.plist 检查通过。
- iOS Release 编译、IPA 打包及全部结构校验通过。搜索取消及 Bonjour 回调的并发警告已修正；最终日志只有未使用 App Intents 时跳过元数据提取的提示，没有 Swift 编译警告或错误。
- 成品经独立 IPA 静态检查：无异常路径、重复成员或符号链接；主程序未加密，没有描述文件、`_CodeSignature` 或 Mach-O 代码签名。

## 成品信息

| 项目 | 验证结果 |
| --- | --- |
| 文件 | `Locus-1.1.0-zh-Hans-unsigned.ipa` |
| 大小 | 4,771,821 字节 |
| Bundle ID | `com.ghb997.location` |
| 版本 / 构建 | 1.1.0 / 5 |
| 最低系统 | iOS 18.0 |
| 设备 / 架构 | iPhone、iPad；arm64、iPhoneOS 设备平台 |
| 语言 | en、zh-Hans；应用及权限资源齐全 |
| 坐标数据 | 主包离线大陆几何，固定 SHA-256 检查通过 |
| 许可 | Locus、idevice、coordtransform MIT 与 Natural Earth 来源说明齐全 |
| 签名 | 未签名，需要安装工具重新签名或兼容容器 |

IPA SHA-256：

```text
b9fd8efdeab61d5fa9d28a3cec1816e830b4e15d2ee5202508e3630b7309dba3
```

离线坐标 JSON 的换行固定为 LF，其 SHA-256 为 `ec3fa27963f5e4481b6d68bdb9a132f48188dc5619df0a237dbdeac70009d2ec`。这消除了 Windows 工作区 CRLF 与 macOS/Git 文件之间的字节差异，几何数值没有改变。

工程文件由此成功构建的 XcodeGen 输出同步回仓库。源码配置仍以 `project.yml` 为准；生成工程和验证记录的后续提交不改变本次构建的应用源码。

## 尚未进行的真机验收

设备、系统及安装方式尚未确定。首次配对、实际定位及停止恢复、苹果地图/高德对照、网络/VPN 切换、锁屏、一小时后台运行与耗电、较大字号和 iPad 视觉操作均未实测。完整矩阵见 [兼容性记录](COMPATIBILITY.zh-CN.md)。

自动测试验证可替换传输与时钟下的核心策略，不能证明原生服务、真实网络和 iOS 后台行为。发布不标注“真机全部兼容”。
