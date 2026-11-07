# wloc 可借鉴点与 location 对照

检查版本：[OpenHRTT/wloc `54bd737`](https://github.com/OpenHRTT/wloc/tree/54bd7378853d12c2e69aa7d7da33bc21c617d2c6)。本次为源码和公开讨论审阅，未独立真机验证，也未将其代码或依赖加入 location 1.2.1。

## 建议优先借鉴

| 优先级 | 方向 | location 的具体做法 | 源码依据 |
| --- | --- | --- | --- |
| P1 | 待应用地点信息卡 | 展示名称、地址、坐标和收藏状态；标明“待应用”，与当前模拟位置区分，减少选错地点 | [选点展示](https://github.com/OpenHRTT/wloc/blob/54bd7378853d12c2e69aa7d7da33bc21c617d2c6/WLocApp/WLocAppiOS/WLocMapViewController.swift#L350-L383) |
| P1 | 按可见区域调整地图视野 | 根据顶部搜索、键盘、底部面板与安全区的实际占用留边，让目标和路线在可见地图区域内显示 | [地图留边](https://github.com/OpenHRTT/wloc/blob/54bd7378853d12c2e69aa7d7da33bc21c617d2c6/WLocApp/WLocAppiOS/WLocMapViewController.swift#L417-L424) |
| P1 | 按当前状态提供处理步骤 | 在未配对、服务未就绪、恢复未确认等状态旁直接打开对应说明；采用 location 自己的开发者服务和清除恢复流程 | [分阶段教程](https://github.com/OpenHRTT/wloc/blob/54bd7378853d12c2e69aa7d7da33bc21c617d2c6/WLocApp/WLocAppiOS/WLocTutorialViewController.swift#L31-L61) |
| P2 | 外部位置链接／快捷指令输入 | 接收名称、地址、经纬度和明确坐标系；先预览并设置待应用目标，再由用户点击定位。校验载荷大小、坐标系白名单和数字范围 | [URL 解析](https://github.com/OpenHRTT/wloc/blob/54bd7378853d12c2e69aa7d7da33bc21c617d2c6/WLocApp/WLocAppShared/WLocURLCommand.swift#L34-L74) |
| P2 | 显式 BD-09 输入 | 增加百度坐标来源选项，经 GCJ-02 转为内部 WGS-84；不改写旧收藏，并加入独立样本和往返测试 | [输入与转换](https://github.com/OpenHRTT/wloc/blob/54bd7378853d12c2e69aa7d7da33bc21c617d2c6/WLocApp/WLocCore/AppWLocCoordinateTool.swift#L150-L155) |

以上是后续建议，不代表 1.2.1 已实现。优先改善目标确认、可见地图范围和错误引导，再增加输入入口。

## 不宜直接替换的部分

- **定位架构不同。** wloc 的 iOS 方案通过 Packet Tunnel、本地 HTTPS 代理及自建根证书处理 Apple `gs-loc` 网络定位响应；location 使用 idevice 开发者定位服务。前者不能等同于直接控制所有 GPS 来源。引入它会新增证书信任、Network Extension、App Group、签名和恢复设计，超出当前版本范围。其代理有目标域名白名单，不应描述为“抓取全部 HTTPS”。见[架构](https://github.com/OpenHRTT/wloc/blob/54bd7378853d12c2e69aa7d7da33bc21c617d2c6/docs/ARCHITECTURE.md)及[代理白名单](https://github.com/OpenHRTT/wloc/blob/54bd7378853d12c2e69aa7d7da33bc21c617d2c6/WLocApp/WLocCore/AppWLocHTTPProxyServer.swift#L149-L154)。
- **兼容性需要独立验证。** README 记录网页方案在 iOS 27 beta 6 后受阻；[issue #11](https://github.com/OpenHRTT/wloc/issues/11)又有兼容性问题报告。公开讨论不能作为“所有设备失效”或“全面兼容”的证明。
- **保留现有玻璃实现。** wloc 的 [WLocGlassView](https://github.com/OpenHRTT/wloc/blob/54bd7378853d12c2e69aa7d7da33bc21c617d2c6/WLocApp/WLocAppiOS/WLocGlassView.swift#L4-L43) 是模糊材质、白边和阴影；location 已采用 iOS 26 原生 Liquid Glass 与旧系统材质回退。
- **保留现有坐标和路线核心。** 不改用 wloc 的宽经纬度矩形判断或 Apple 地图坐标存储策略。location 现有内部 WGS-84、离线大陆多边形、GPX 多轨多段、单调时钟和暂停续走更符合本应用的要求。
- **海拔与精度后置。** location 当前传输只接受经纬度，不能仅增加界面就宣称支持这些参数。第三方海拔查询还涉及发送精确坐标，需要独立设计。

## 许可

wloc 自有代码采用 [MIT](https://github.com/OpenHRTT/wloc/blob/54bd7378853d12c2e69aa7d7da33bc21c617d2c6/LICENSE)；[NOTICE](https://github.com/OpenHRTT/wloc/blob/54bd7378853d12c2e69aa7d7da33bc21c617d2c6/NOTICE) 将第三方依赖单独处理。未来若复制实现，需保留署名并逐项核对相应依赖许可。本轮仅参考设计和功能思路。
