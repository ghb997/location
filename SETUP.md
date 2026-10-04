# Locus 中文版安装与首次定位

## 1. 安装 IPA

从[本仓库 Releases](https://github.com/ghb997/location/releases/latest) 下载 `Locus-1.0.3-zh-Hans-unsigned.ipa`。此包未包含个人签名证书，需用你已有的 SideStore、AltStore、Sideloadly、Feather 或其他可用签名工具重新签名，也可在兼容的 LiveContainer 环境中导入。

最低系统 iOS 18.0。不同系统、签名和容器对后台运行及文件选择器的支持不同，构建成功不代表这些安装组合均经过验证。

如使用 LiveContainer 无法导入配对文件：

1. 长按 Locus → Settings，开启 **Fix File Picker**，再尝试导入。
2. 或在文件共享菜单中选择 LiveContainer → Locus。
3. 或复制 RPPairing 的 plist 全文，在 Locus 中选择“从剪贴板粘贴”。

## 2. 开启开发者模式并配对

在 iPhone 系统设置中开启开发者模式，按系统提示重启并确认。找不到此选项时，可能需要先通过电脑连接开发工具。

### iOS 18–26

1. 在电脑下载 [idevice_pair](https://github.com/jkcoxson/idevice_pair/releases) 中适合电脑系统的版本。
2. 使用 USB 连接 iPhone，解锁并选择“信任”。
3. 按该工具说明生成 **RPPairing** 文件。不要选普通 lockdown 或 SideStore `.mobiledevicepairing` 格式；文件扩展名本身不能判断格式。
4. 将文件传到 iPhone，打开 Locus → 导入配对文件。也可在“设置 → 开发者配对”中导入或粘贴。

配对文件含有设备配对凭据，请保存在自己的设备上，不要提交到 GitHub 或发给他人。

### iOS 27 的上游本机配对流程

本版保留原项目的入口，未在 iOS 27 真机上验证。若你的系统支持此流程：

1. 在 Locus 中选择“在此 iPhone 上配对”→“开始配对”。
2. 允许本地网络、定位和通知。
3. 保持 Locus 运行，前往系统设置 › 隐私与安全性 › 开发者模式，选择与 Locus／主机配对。
4. **先输入手机解锁密码**；第二次提示再输入 Locus 显示的 **6 位配对码**。
5. 返回 Locus 确认配对成功。

## 3. 连接 LocalDevVPN

从 [App Store](https://apps.apple.com/us/app/localdevvpn/id6755608044) 安装 LocalDevVPN，开启 VPN。本工具使用的是访问设备开发者服务的本机隧道。默认地址 `10.7.0.1`，除非你已修改隧道配置，否则保持默认即可。

## 4. 开始、移动与停止

1. 先连接 Wi-Fi，确认 LocalDevVPN 已开启。
2. 搜索地点，或在地图上点击放置标记。
3. 点击“修改定位”，等待状态变成“模拟定位中”。
4. 可选择步行／跑步／骑行／驾车速度，启用摇杆，或通过路线面板规划路线、导入 GPX。
5. 完成后点击“停止”，等待“未开启模拟定位”，并在系统地图中检查真实位置是否恢复。

如果停止提示失败，请重试；必要时重启 iPhone。退出应用或关闭 VPN 不应被当作已经成功清除模拟位置的证明。

## 常见问题

- **提示配对文件无效**：重新使用 idevice_pair 的 RPPairing 模式生成，粘贴时包含完整 XML。修改后缀不能转换格式。
- **无法打开开发者隧道**：检查开发者模式、Wi-Fi、LocalDevVPN 和设置中的隧道 IP。
- **地图在动，其他应用不接受**：对方应用可能识别了模拟位置，此版本不处理这类应用内部校验。
- **后台中断**：iOS 可能挂起应用；回到 Locus 检查连接后重试。
- **仍显示英文**：在系统的应用语言设置中选择简体中文，并重新打开应用。系统生成的错误信息跟随系统语言。
- **GPX 导入失败**：支持 XML GPX，最多 10 MB、50,000 个点；经纬度必须有效。多段轨迹按文件顺序连接播放。
