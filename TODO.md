# Malody Catch Mobile TODO

更新日期：2026-04-29

## 近期目标

Android 首版先完成移动端低延迟编辑闭环：

- Flutter 负责 UI、触摸、画布、音频和文件入口。
- `Malody_catch_core` 通过 `dart:ffi` 提供数据和编辑规则。
- 首版不支持桌面插件系统。

## P0 - Native Core 接入

- [x] 创建 Android-only Flutter 工程。
- [x] 增加 `ffi` 依赖。
- [x] 建立初始 Dart FFI 绑定：session、普通音符、snapshot、undo/redo。
- [ ] 从 sibling core 仓库构建 Android `arm64-v8a` `.so`。
- [ ] 将 `libmalody_catch_core_ffi.so` 放入 Android `jniLibs/arm64-v8a`。
- [ ] 增加 debug 启动自检：加载 native library、create/destroy session。
- [ ] 增加 FFI smoke test 页面或 debug action。
- [ ] 为 FFI 绑定增加异常边界：library missing、ABI mismatch、null session。
- [ ] 封装 `CoreSession` Dart class，隐藏裸指针生命周期。

## P1 - 移动端数据状态层

- [ ] 建立 `ChartDocumentController`：持有 core session、当前文件路径、dirty 状态。
- [ ] 建立 note snapshot 缓存，按 core revision 刷新。
- [ ] 建立 selection state：单选、多选、清空、按 id 查询。
- [ ] 建立 editor mode：place normal、place rain、delete、select、move。
- [ ] 建立 undo/redo state，同步按钮可用状态。
- [ ] 建立错误展示通道：SnackBar/dialog/log panel。
- [ ] 增加 autosave 草稿策略，避免移动端切后台丢数据。

## P2 - Canvas 与触摸交互

- [ ] 建立 `ChartCanvas` Flutter widget。
- [ ] 建立坐标转换：screen x/y <-> lane x / beat。
- [ ] 绘制基础网格、参考线、普通音符、rain 音符。
- [ ] 实现单指点击放置普通音符。
- [ ] 实现点击命中选择。
- [ ] 实现拖动移动选中音符。
- [ ] 实现双指缩放时间轴。
- [ ] 实现单指纵向滚动谱面。
- [ ] 实现长按上下文菜单：删除、复制、粘贴。
- [ ] 增加帧率与耗时 debug overlay。

## P3 - 文件与音频

- [ ] 集成 Android 文件选择器，支持 `.mc` / `.mcz`。
- [ ] 接 core load/save/export API。
- [ ] 建立最近打开列表。
- [ ] 集成音频播放库，支持播放、暂停、seek、速度。
- [ ] 将音频进度映射到 canvas reference line。
- [ ] 支持后台/前台切换时暂停和恢复策略。
- [ ] 支持导出 `.mcz` 后系统分享。

## P4 - 移动端 UI

- [ ] 替换 Flutter 默认 counter 页面。
- [ ] 建立横屏优先主界面：画布为第一视觉中心。
- [ ] 建立顶部/底部工具栏：打开、保存、播放、撤销、重做、模式切换。
- [ ] 建立可收起编辑面板：音符、BPM、Meta。
- [ ] 建立移动端功能入口，不复刻桌面菜单树。
- [ ] 建立暗色主题和触摸友好尺寸。
- [ ] 隐藏插件入口，首版不展示不可用功能。

## P5 - Android 打包与质量

- [ ] 确认包名、应用名、图标、横屏策略。
- [ ] 增加 Android 权限和文件访问策略。
- [ ] 建立 debug/release 构建说明。
- [ ] 真机测试目标：中端 Android 设备，优先 arm64。
- [ ] 验证 30/60 FPS 交互稳定性。
- [ ] 验证打开、编辑、保存、重开一致性。
- [ ] 验证异常路径：native library 缺失、文件损坏、保存失败。

## 验收清单

- [ ] Android 真机可启动且加载 native core。
- [ ] 能打开示例谱面并绘制音符。
- [ ] 能放置、删除、移动、撤销、重做。
- [ ] 能保存并由桌面端重新打开。
- [ ] 操作中无明显 GUI 出界、卡顿、布局抽搐。
