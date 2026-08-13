# FloatCue iOS 新功能实现与验证状态

评估日期：2026-08-12  
实现更新：2026-08-13
上游仓库：<https://github.com/thisisnsh/cuecard>  
评估基线：`a959a4026e858dc19aaab3662c61e3b2cef890bd`  
许可证：MIT

## 结论

横竖屏布局、普通话端侧识别、中文文稿对齐、语音平滑滚动和失败后定速降级均已实现。29 项单元测试已在 iPhone 17 / iOS 26.5 Simulator 全部通过，模拟器完整构建和 arm64 真机 Debug 编译也已通过。

仍未验证的系统边界只有真实 iPhone 上的跨 App 行为：FloatCue 进入 PiP 后在后台读取麦克风，同时 Apple 系统相机录像时是否能持续共存。iOS 是否中断麦克风取决于双方的音频会话类别、混音选项、激活时机和具体设备，并非系统相机必然抢占；已有上架产品证明该产品形态能够落地，但 Apple 没有公开保证所有机型都能稳定共存。

此前按照代码行数和传统人工团队给出的“人日/周”估算不适用于智能体直接开发，已经从本文删除。剩余工作不再按代码量估算：连接真实 iPhone 后执行测试矩阵，成功则确认语音跟读，失败则确认约一秒内自动退回定速滚动。

## 当前 FloatCue iOS 实现

- 原生 SwiftUI/UIKit 工程，目标为 iPhone 和 iPad。
- 悬浮窗使用 `AVPictureInPictureVideoCallViewController`。
- 定速模式按 `wordsPerMinute` 推进；普通话连续中文按标准化字符数计算合理的滚动单位。
- 已允许主 App 的竖屏和横屏方向。
- PiP 监听界面尺寸和有效设备方向，在 `16:9`/`9:16`、`4:3`/`3:4` 之间自动旋转；方向变化只更新尺寸，不重建播放状态。
- `scrollSpeed` 虽然保存在设置里，但当前滚动实际主要由 `wordsPerMinute` 驱动。
- 语音识别固定 `zh-CN`，启动前检查端侧能力并强制 `requiresOnDeviceRecognition = true`，不存在联网后备路径。
- 音频会话使用 `playAndRecord + measurement + mixWithOthers`，并记录 session、buffer、识别、PiP、后台、中断、路由、匹配和降级事件。
- 中文对齐采用简繁/全半角/标点标准化、字符级编辑距离、连续命中、局部性、向前偏好和弱拼音辅助。
- 已新增 `FloatCueTests` 单元测试 target，共 29 项测试。

## 基线运行风险

1. 上游工程依赖 Firebase、Google Sign-In、Analytics 和 Crashlytics，但仓库没有提交 `GoogleService-Info.plist`。本 fork 已选择本地优先、无账号路线，并移除这些依赖。
2. 上游工程目标配置同时出现 17.0 和 16.6；本 fork 已按 iOS README 统一为 iOS 17.0+。
3. 上游通过 `UIApplication.shared.perform(#selector(NSXPCConnection.suspend))` 主动把 App 送入后台。这不是应当依赖的公开产品接口；本 fork 已移除该调用，改为启动 PiP 后由用户正常切换 App。
4. 上游没有测试；本 fork 已新增单元测试 target，覆盖方向、端侧请求策略、音频事件、降级、中文对齐和平滑滚动。

## 为什么不需要 Firebase

Firebase 与悬浮提词、自动滚动、横竖屏和语音跟读没有技术依赖。上游只把它用于：

- Firebase Auth：Apple/Google 账号登录；
- Analytics：页面和按钮事件；
- Crashlytics：线上崩溃收集。

现有文稿和设置本来就保存在本机，并没有依赖 Firebase 同步。对当前个人、本地优先版本，保留 Firebase 只会增加账号配置、隐私披露、网络依赖和构建体积，因此本 fork 已移除登录页、账号管理、Google Sign-In、Analytics、Crashlytics 和对应 Swift Package。代价是暂时没有登录、跨设备同步和云端崩溃统计；这些都可以等产品确实需要时再单独引入，不必绑定 Firebase。

## 功能一：横竖屏悬浮布局

### 已实现

1. 悬浮方向建模为 `portrait` / `landscape`，无有效方向时保留上一方向，首次默认竖屏。
2. 同一个比例预设按方向自动转换，例如 `16:9` 与 `9:16`。
3. 同时监听 SwiftUI 几何尺寸和 `UIDevice.orientationDidChangeNotification`，忽略 `faceUp`、`faceDown` 和未知方向。
4. 方向变化只更新 `preferredContentSize` 和承载视图尺寸，不重新配置 PiP，因此保留阅读进度和播放状态。
5. 5 项方向、比例、边界尺寸和状态保持测试全部通过。

### 尚待验证

模拟器能验证方向模型、尺寸计算和状态保持，但活动中的系统 PiP 最终如何呈现宽高比仍需在真实 iPhone 上观察。

## 功能二：语音跟读滚动

### “AI 跟读”实际上包含什么

MVP 不需要接大语言模型。核心是 Apple Speech 的流式识别加一个本地文稿对齐器：

1. 从麦克风持续取得音频并获得部分识别结果。
2. 对识别文本和原稿做同样的标准化。中文应按字或适合中文的词元处理，同时兼容数字、英文名和标点差异。
3. 只在当前阅读位置附近寻找匹配，使用编辑距离、连续命中奖励和向前偏好，避免常见词造成远距离跳转。
4. 把“识别到的文稿位置”变成滚动目标，用缓动而不是直接跳动。
5. 停顿约一秒后停止滚动；恢复说话后继续匹配。
6. 处理重复一句、退回重说、跳过一段、临时发挥、识别任务结束、网络/本地模型不可用和音频中断。
7. 请求麦克风和语音识别权限，并显示明确的录音状态。

Apple 的 `requiresOnDeviceRecognition` 只有在当前语言和设备的 `supportsOnDeviceRecognition` 为真时才能保证本地识别。本项目固定为普通话中文 `zh-CN`，启动前检查端侧能力并将 `requiresOnDeviceRecognition` 设为 `true`；不支持时不允许联网识别，直接退回定速滚动。

### 两条产品路线

#### A. 悬浮在 Apple 系统相机上方（首发路线）

提词器在后台需要录音，前台系统相机也会激活录音会话。建议在 App 位于前台时用 `playAndRecord + mixWithOthers` 激活语音录音，再启动 PiP。Apple 的机制允许可混音音频会话共存，因此不是“系统相机必然抢麦”；但相机内部配置没有公开，仍需真机验证。

VoicePrompter 的 App Store 页面和更新记录明确描述了悬浮 PiP 启用时的后台语音识别，可作为产品可行性证据。它不是开源实现，也不能替代我们对目标设备的验证。

必须先用真实 iPhone 做兼容矩阵，至少验证：

- Apple 系统相机的前后摄像头；
- 手机内置麦克风；
- 横屏和竖屏；
- 进入录像、停止录像以及来电等中断后的降级行为。

一旦发生音频中断、连续收不到 buffer 或识别任务失败，语音跟读停止并在约一秒内退回定速滚动，不在后台循环重启音频会话。

#### B. 在本 App 内置相机录制（不进入首发）

这是更可控的语音跟读路线：相机录制和识别共享同一个音频采集流，不与另一个 App 争夺麦克风。代价是产品还要实现相机预览、录制、方向、保存、权限和失败恢复。用户已明确第一版不采用这条路线。

MIT 开源项目 Open Prompter 采用这类内置相机架构，可参考其语音状态机、文稿对齐和测试结构。它的文稿对齐主要面向英文，本项目已经按普通话中文重写标准化和局部匹配。

### 已实现能力

- 普通话端侧流式识别，端侧模型、权限和输入格式均在启动前检查；
- `playAndRecord + measurement + mixWithOthers` 音频会话；
- buffer 心跳、一秒无 buffer 超时、中断、路由和识别任务诊断；
- 中文字符级局部模糊匹配，支持停顿、重复、小口误和小范围跳句；
- 对齐结果先转为目标进度，再通过限速缓动追赶，识别修正不会直接跳屏；
- 端侧不可用、权限拒绝、中断、无 buffer、任务结束或其他识别错误时同步切回定速模式；
- 模式切换保留当前阅读进度和播放状态，不在后台自动重抢麦克风。

## 当前交付状态

1. **已完成**：本地无账号基线、横竖屏 PiP、普通话端侧识别、音频诊断、中文对齐、平滑滚动和定速降级。
2. **已自动验证**：29 项单元测试全部通过；iPhone 17 / iOS 26.5 Simulator 完整构建通过；arm64 iphoneos Debug 编译通过。
3. **待人机协作验证**：真实 iPhone 上依次测试 Apple 系统相机前后摄像头、横竖屏、五分钟录像、PiP 跟读和成片声音。
4. **结果规则**：共存成功则确认语音模式；被系统相机中断则确认自动定速降级。首版均不引入联网识别或内置相机。

## 已确认边界与剩余参数

已确认：第一版只兼容 Apple 系统相机；只做普通话中文；只使用端侧识别；端侧不可用或麦克风被中断时退回定速滚动；不联网、不内置相机；最低 iOS 17.0。

当前默认参数为停顿约一秒停止推进、单次回退最多全文进度的 5%、短识别窗口最多前跳 24 个标准化字符。这些参数只需根据真机朗读结果调优，不改变现有架构。

## 本轮验证记录

- 已创建 `giga-drill/cuecard` GitHub fork；本地 `origin` 指向个人 fork，`upstream` 指向作者仓库且禁用 push。
- 已移除 Firebase、Google Sign-In、Analytics 和 Crashlytics；工程不再需要下载这些外部二进制依赖。
- 已移除非公开的强制后台调用。
- 已将 iOS 最低系统版本统一为 17.0。
- 工程 plist、Xcode project、shared scheme 和 Git diff 格式校验通过。
- CoreSimulator 框架版本不一致已修复，并已安装 Xcode 26.6 所需的 iOS 26.5 Simulator。
- 29 项单元测试已在 iPhone 17 / iOS 26.5 Simulator 全部通过，0 失败、0 跳过。
- 模拟器完整构建和 arm64 iphoneos Debug 编译成功。
- 已生成真机日志采集、汇总脚本和测试矩阵；真实 iPhone 系统相机共存验证尚未执行。

## 参考

- CueCard 源码与 MIT 许可证：<https://github.com/thisisnsh/cuecard>
- Apple Speech：<https://developer.apple.com/documentation/speech>
- Apple `supportsOnDeviceRecognition`：<https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition>
- Apple 音频会话中断：<https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions>
- Apple App Review Guidelines 2.5.14（录音提示与同意）：<https://developer.apple.com/app-store/review/guidelines/>
- Open Prompter 参考实现：<https://github.com/lelanddutcher/open-prompter>
- 本轮开源与系统相机共存调研：[`voice-tracking-open-source-research.md`](voice-tracking-open-source-research.md)
- Apple 系统相机真机测试清单：[`real-device-test-checklist.md`](real-device-test-checklist.md)
