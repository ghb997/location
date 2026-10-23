# location 1.2.0 构建与成品验证

- 构建源码提交：`5c9b908f591c940ad2c48dc5d2c5917d346db743`。
- [完整成功的 GitHub Actions 构建](https://github.com/ghb997/location/actions/runs/39893673687)。
- 环境：GitHub macOS 15 runner，Xcode 26 系列，iPhoneOS Release 设备构建。
- **144 项 Swift 自动测试，0 失败**。比 1.1.1 增加 40 项，覆盖地点损坏与恢复、跨页面目标竞争、路线存档与启动恢复、全量 50,000 点显示准备、新端口清除恢复、脱敏诊断历史及音频生命周期策略。
- 其中 14 项测试直接运行实际 `SpoofSession`，注入传输、单调时钟、系统定位服务和隔离偏好设置，包括启动后立刻停止、新路线失败后保留旧进度等场景。
- **340 对中英文资源、315 个引用键**、本地化权限和 Info.plist 检查通过。基础及中英文显示名称均为精确的小写 `location`。
- iOS Release 编译、IPA 打包和结构校验通过；日志没有 Swift 警告或错误。Xcode 仅提示没有 App Intents 依赖，因此跳过对应元数据提取。
- 下载产物后核对 GitHub artifact SHA-256，再执行仓库校验脚本和独立 IPA 静态检查：没有异常路径、重复成员或符号链接，检查器无警告。

## 成品信息

| 项目 | 验证结果 |
| --- | --- |
| 文件 | `location-1.2.0-zh-Hans-unsigned.ipa` |
| 大小 | 4,982,931 字节 |
| 应用显示名称 / 可执行文件 | `location` / `location` |
| Bundle ID | `com.ghb997.location` |
| 版本 / 构建 | 1.2.0 / 7 |
| 最低系统 | iOS 18.0 |
| 设备 / 架构 | iPhone、iPad；arm64、iPhoneOS 设备平台 |
| 语言 | en、zh-Hans；应用及权限资源齐全 |
| 坐标数据 | 离线大陆几何，固定 SHA-256 检查通过 |
| 许可 | Locus、idevice、coordtransform MIT 与 Natural Earth 来源说明齐全 |
| 签名 | 未签名，无描述文件、CodeResources 或 Mach-O 代码签名 |

IPA SHA-256：

```text
660a54e7efc0f4b7cf1a89824bab16158ab855483915f87d504883672667ad09
```

内部工程与 scheme 保留 `Locus` 名称，产品与应用显示名称为 `location`。原有 URL scheme 和存储键保留兼容性。Xcode 工程由此成功构建的 XcodeGen 输出同步；`project.yml` 仍为配置来源。工程生成文件和验证记录的后续提交不改变已验证的应用源码、测试或构建配置。

## 真机验证边界

用户尚未确定设备和安装工具。Liquid Glass 的实际透视效果、系统辅助功能、iPad 与大字号视觉、首次配对、真实定位与停止恢复、苹果地图／高德对照、VPN 切换、锁屏和一小时后台耗电均未实测。自动测试与 Release 编译不能替代这些结论，完整矩阵见[兼容性记录](COMPATIBILITY.zh-CN.md)。

50,000 点用例验证显示准备次数、分段与原值保留；没有宣称设备 FPS、启动时间或内存改善幅度。
