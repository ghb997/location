# location 1.2.1 构建与成品验证

- 构建源码提交：`627f6426a59f7bf620a766819b0891ff1a0dcd0d`。
- [成功的 GitHub Actions 构建](https://github.com/ghb997/location/actions/runs/42338529009)。
- 环境：GitHub macOS 15 runner，Xcode 26.3，iPhoneOS Release 设备构建。
- **144 项 Swift 自动测试，0 失败**。覆盖路线与 GPX、坐标、配对校验、定位会话控制、恢复顺序、数据存档、地点损坏保护及 50,000 点路线显示准备。
- **340 对中英文资源、315 个引用键**、本地化权限和 Info.plist 检查通过。基础及中英文显示名称均为精确的小写 `location`，浅色配置为 `UIUserInterfaceStyle = Light`。
- iOS Release 编译、IPA 打包和结构校验通过；日志没有 Swift 警告或错误。Xcode 仅提示没有 App Intents 依赖，因此跳过对应元数据提取。
- 下载产物后核对 GitHub artifact SHA-256，再执行仓库校验脚本和独立 IPA 静态检查：没有异常路径、重复成员或符号链接，检查器无警告。

## 成品信息

| 项目 | 验证结果 |
| --- | --- |
| 文件 | `location-1.2.1-zh-Hans-unsigned.ipa` |
| 大小 | 5,039,684 字节 |
| 应用显示名称 / 可执行文件 | `location` / `location` |
| Bundle ID | `com.ghb997.location` |
| 版本 / 构建 | 1.2.1 / 8 |
| 最低系统 | iOS 18.0 |
| 设备 / 架构 | iPhone、iPad；arm64、iPhoneOS 设备平台 |
| 外观 | 固定浅色；iOS 26 原生玻璃，iOS 18–25 材质兼容 |
| 语言 | en、zh-Hans；应用及权限资源齐全 |
| 坐标数据 | 离线大陆几何，固定 SHA-256 检查通过 |
| 许可 | Locus、idevice、coordtransform MIT 与 Natural Earth 来源说明齐全 |
| 签名 | 未签名，无描述文件、CodeResources 或 Mach-O 代码签名 |

IPA SHA-256：

```text
a9666de631172301ad28405caf14a2306d9108ab38b6c0d827f710a620532881
```

内部工程与 scheme 保留 `Locus` 名称，产品与应用显示名称为 `location`。原有 URL scheme 和存储键保留兼容性。Xcode 工程由此成功构建的 XcodeGen 输出同步；`project.yml` 仍为配置来源。工程生成文件和验证记录的后续提交不改变已验证的应用源码、测试或构建配置。

## 生产组件模拟器渲染

[组件渲染工作流](https://github.com/ghb997/location/actions/runs/42338529003)通过，8 张截图的摘要与实际渲染结果已检查。

| 检查项 | 结果 |
| --- | --- |
| 运行时 | iOS 26.2（23C54） |
| 模拟设备 | iPhone 16 Pro、iPad Pro 11-inch（M4） |
| 场景 | 未开始、路线运行、辅助字号 accessibility2、降低透明度；每台设备各 4 张 |
| 外观与语言 | 系统设为深色，应用实际观察值为浅色；zh-Hans |
| 辅助功能 | 实际观察到减少动态效果开启；降低透明度场景确认开启，其余关闭 |
| 像素检查 | 普通字号主要动作完整；大字号切换为纵向排列，iPhone 底部为可滚动区域；降低透明度时面板为实色 |

本次是静态截图审阅，不包括触摸、滚动、动画帧率或 VoiceOver 的自动交互测试。较大字号下需滚动查看完整底部操作区。发布附件 `location-1.2.1-UI-preview.zip` 包含原始截图和运行环境记录。

独立预览工程直接编译实际生产的主题、状态条、搜索框、工具栏、地图标记、底部操作及路线控制。背景是明确标注的合成地图，会话是无定位传输的假状态；不代表完整应用的导航、MapKit 瓦片、配对或定位已经在模拟器运行。截图流程记录源码提交、运行时、设备型号、实际环境设置和每张图片的 SHA-256。

## 真机验证边界

用户尚未确定设备和安装工具。实际地图背景上的玻璃交互、iOS 18–25 材质、系统辅助功能即时切换、VoiceOver、键盘下搜索结果、iPad 横屏与分屏、首次配对、真实定位与停止恢复、苹果地图／高德对照、VPN 切换、锁屏和一小时后台耗电均未实测。自动测试、Release 编译和独立组件截图不能替代这些结论，完整矩阵见[兼容性记录](COMPATIBILITY.zh-CN.md)。

50,000 点用例验证显示准备次数、分段与原值保留；没有宣称设备 FPS、启动时间或内存改善幅度。
