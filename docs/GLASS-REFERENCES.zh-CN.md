# 浅色液态玻璃设计参考

本轮按照用户提供的五个项目检查实际源码，提取适合 location 的视觉原则。没有复制这些项目的代码、图片或着色器，也没有添加它们作为依赖。

| 参考项目（固定版本） | 参考的视觉细节 | location 的实现边界 |
| --- | --- | --- |
| [Beans-Music · `f988131`](https://github.com/XIaodou0416/Beans-Music/blob/f9881318caf774129205c3160510ef0dfa318adc/Beans/Components.swift#L168-L279) | 统一玻璃表面、连续圆角、轻阴影、浅色底衬，以及不同系统版本的材质适配 | 使用原生 SwiftUI 玻璃 API 和公开 Material；统一搜索、状态、工具栏和操作控件的表面规则 |
| [Douyin-Liquid-Glass · `c150eab`](https://github.com/YuanhaoBei/Douyin-Liquid-Glass/blob/c150eab1ffe6725230fdf36c094eccdf53d1aca0/app/src/main/java/com/autumn/douyin/liquidglass/component/FloatingBottomBar.kt#L94-L153) | 悬浮胶囊、轻表面色、克制的投影与边缘高光 | 保留地图在控件之间和周围的可见空间；不采用 Android LSPosed、背景捕获或传感器管线 |
| [WeChat-LiquidGlass · `f2d40f4`](https://github.com/liuran001/WeChat-LiquidGlass/blob/f2d40f4e40172aa6728cbc70485ca8cf727b930c/src/io/github/liuran001/mmliquidglass/LiquidGlassPanel.java#L346-L363) | 背景仍可辨认，通过细边和轻表面色保证内容可读，减少厚重磨砂感 | 长文字使用较稳的常规玻璃，动作采用独立表面；不采用宿主应用注入或 AGSL 着色器 |
| [Gordonynh/LiquidGlass · `f3019d1`](https://github.com/Gordonynh/LiquidGlass/blob/f3019d113be94d95ec286571d2e8cb7647c21598/Rendering/GlassHlsl.cs#L217-L251) | 柔软投影与细小接触投影、相邻明暗边表现厚度 | 旧系统材质增加细渐变边与轻投影；iOS 26 的光学边缘交给系统，不采用 Windows DXGI 捕获和自定义绘制循环 |
| [sunimp/TabBar · `0eb711b`](https://github.com/sunimp/TabBar/blob/0eb711b13cf81e292b7afeff8aa8b2ed6c33aa8b/Sources/TabBar/TabBarStyle.swift#L61-L76) | 浅色浮动胶囊、清晰的选中状态、图标与文字层次 | 使用 location 自己的颜色和控件；不引入该组件的私有 `_UILiquidLensView`、`CABackdropLayer` 或 `CAFilter` 路径 |

location 固定使用浅色外观。iOS 26 使用 `glassEffect`、`GlassEffectContainer` 和系统玻璃按钮；iOS 18–25 使用公开材质与边缘、投影近似效果，不声称具有与原生 Liquid Glass 相同的折射。开启“降低透明度”时使用实色表面，并保留增强对比度和减少动态效果的适配。

上述仓库顶层许可证均为 MIT；此处仅记录设计参考，不引入其源码授权关系。具体代码复制仍需单独核对相应源码和第三方声明。本轮未引入任何参考项目的私有 API。

本文为源码和设计范围说明，不代表已完成真机视觉或性能验收。
