# wloc 可借鉴点与 location 对照

检查版本：[OpenHRTT/wloc `54bd737`](https://github.com/OpenHRTT/wloc/tree/54bd7378853d12c2e69aa7d7da33bc21c617d2c6)。源码和公开讨论已完成审阅，未独立验证 wloc 的真机效果。location 1.3.0（9）已按下面前三项实现自己的组件和状态处理，未引入 wloc 代码、资源或依赖。

## 1.3.0 实现与后续建议

| 状态 | 方向 | location 的具体做法 | 源码依据 |
| --- | --- | --- | --- |
| 1.3.0 已实现 | 待应用地点信息卡 | 展示名称、可用地址、WGS-84 坐标和收藏状态；与当前模拟位置分开，信息不随心跳覆盖。地点列表先预览，再明确点击定位 | [选点展示](https://github.com/OpenHRTT/wloc/blob/54bd7378853d12c2e69aa7d7da33bc21c617d2c6/WLocApp/WLocAppiOS/WLocMapViewController.swift#L350-L383) |
| 1.3.0 已实现 | 按可见区域调整地图视野 | 根据顶部、底部浮层和可用尺寸留边，安排目标和路线范围；异步结果尊重用户期间主动拖动的视野 | [地图留边](https://github.com/OpenHRTT/wloc/blob/54bd7378853d12c2e69aa7d7da33bc21c617d2c6/WLocApp/WLocAppiOS/WLocMapViewController.swift#L417-L424) |
| 1.3.0 已实现 | 按当前状态提供处理步骤 | 状态栏问号打开配对、服务、等待或恢复指引，并跳到相应设置区；按 location 的结构化状态和操作门禁处理，打开指引不自动写入或检测 | [分阶段教程](https://github.com/OpenHRTT/wloc/blob/54bd7378853d12c2e69aa7d7da33bc21c617d2c6/WLocApp/WLocAppiOS/WLocTutorialViewController.swift#L31-L61) |
| 后续建议 | 外部位置链接／快捷指令输入 | 接收名称、地址、经纬度和明确坐标系；先预览并设置待应用目标，再由用户点击定位。校验载荷大小、坐标系白名单和数字范围 | [URL 解析](https://github.com/OpenHRTT/wloc/blob/54bd7378853d12c2e69aa7d7da33bc21c617d2c6/WLocApp/WLocAppShared/WLocURLCommand.swift#L34-L74) |
| 后续建议 | 显式 BD-09 输入 | 增加百度坐标来源选项，经 GCJ-02 转为内部 WGS-84；不改写旧收藏，并加入独立样本和往返测试 | [输入与转换](https://github.com/OpenHRTT/wloc/blob/54bd7378853d12c2e69aa7d7da33bc21c617d2c6/WLocApp/WLocCore/AppWLocCoordinateTool.swift#L150-L155) |

本轮还借鉴了紧凑信息卡、分步骤说明和清晰操作层次：目标、路线和模式按内容分层，短内容贴近底部，受限高度时次要内容可滚动，停止入口保留在滚动区外。外部位置 URL 和 BD-09 输入仍未加入本版。

“已实现”表示代码功能范围。自动测试、Release 构建及组件截图结果见[构建记录](BUILD.zh-CN.md)，真机 MapKit 交互、VoiceOver、横屏及网络／后台效果见[兼容性记录](COMPATIBILITY.zh-CN.md)；受限高度预览不等同于真实横屏或键盘验收。

## 不宜直接替换的部分

- **定位架构不同。** wloc 的 iOS 方案通过 Packet Tunnel、本地 HTTPS 代理及自建根证书处理 Apple `gs-loc` 网络定位响应；location 使用 idevice 开发者定位服务。前者不能等同于直接控制所有 GPS 来源。引入它会新增证书信任、Network Extension、App Group、签名和恢复设计，超出当前版本范围。其代理有目标域名白名单，不应描述为“抓取全部 HTTPS”。见[架构](https://github.com/OpenHRTT/wloc/blob/54bd7378853d12c2e69aa7d7da33bc21c617d2c6/docs/ARCHITECTURE.md)及[代理白名单](https://github.com/OpenHRTT/wloc/blob/54bd7378853d12c2e69aa7d7da33bc21c617d2c6/WLocApp/WLocCore/AppWLocHTTPProxyServer.swift#L149-L154)。
- **兼容性需要独立验证。** README 记录网页方案在 iOS 27 beta 6 后受阻；[issue #11](https://github.com/OpenHRTT/wloc/issues/11)又有兼容性问题报告。公开讨论不能作为“所有设备失效”或“全面兼容”的证明。
- **保留现有玻璃实现。** wloc 的 [WLocGlassView](https://github.com/OpenHRTT/wloc/blob/54bd7378853d12c2e69aa7d7da33bc21c617d2c6/WLocApp/WLocAppiOS/WLocGlassView.swift#L4-L43) 是模糊材质、白边和阴影；location 已采用 iOS 26 原生 Liquid Glass 与旧系统材质回退。
- **保留现有坐标和路线核心。** 不改用 wloc 的宽经纬度矩形判断或 Apple 地图坐标存储策略。location 现有内部 WGS-84、离线大陆多边形、GPX 多轨多段、单调时钟和暂停续走更符合本应用的要求。
- **海拔与精度后置。** location 当前传输只接受经纬度，不能仅增加界面就宣称支持这些参数。第三方海拔查询还涉及发送精确坐标，需要独立设计。

## 许可

wloc 自有代码采用 [MIT](https://github.com/OpenHRTT/wloc/blob/54bd7378853d12c2e69aa7d7da33bc21c617d2c6/LICENSE)；[NOTICE](https://github.com/OpenHRTT/wloc/blob/54bd7378853d12c2e69aa7d7da33bc21c617d2c6/NOTICE) 将第三方依赖单独处理。未来若复制实现，需保留署名并逐项核对相应依赖许可。本轮仅参考设计和功能思路。
