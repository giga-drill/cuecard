# iOS 悬浮提词器语音跟读与开源方案调研

调研日期：2026-08-12

## 结论先行

系统相机不一定会“必然抢占”悬浮提词器的麦克风。iOS 的实际行为取决于双方的 `AVAudioSession` 类别、是否允许混音、会话激活时机以及设备/系统版本。提词器可尝试在前台以 `playAndRecord + mixWithOthers` 启动录音，再进入画中画；如果系统相机激活后仍发生音频中断，则按已确认的产品规则立即退回定速滚动。

市面上已有 App 明确宣称能在其他相机 App 上方悬浮并进行语音跟读。VoicePrompter 的 App Store 更新记录还明确提到：只有启用悬浮画中画时，语音识别才在后台运行。这说明该产品形态在至少一部分设备和系统版本上已经落地，但不能据此推断 Apple 对所有机型都提供了稳定保证。

开源项目中已经有成熟的“端侧语音识别 + 文稿位置对齐”实现，但本轮没有找到同时公开以下完整链路的原生 iOS 项目：自定义 PiP 悬浮窗、后台麦克风、Apple 系统相机同时录制、端侧普通话识别、识别失败自动退回定速滚动。因此可以复用算法和工程结构，系统相机共存仍需自己做真机验证。

## Apple 平台边界

### 麦克风是否一定被系统相机抢占

- `playAndRecord` 默认是不可混音类别；另一个不可混音会话激活时，当前会话可能被中断。
- `mixWithOthers` 允许当前音频会话与其他 App 的音频会话混合，但它不是“所有 App 可同时读取麦克风”的跨设备承诺。
- 后台 App 不能在被中断后随意激活一个会打断前台 App 的不可混音会话，系统可能返回 `cannotInterruptOthers`。
- 所以实现策略应是：在本 App 仍位于前台时配置并激活允许混音的录音会话，确认收到音频，再启动 PiP 并由用户切换到系统相机。
- 系统相机的内部音频会话参数未公开；最终兼容性必须在真实 iPhone 上验证。

### 端侧识别边界

- 固定使用 `SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))`。
- 启动前检查 `supportsOnDeviceRecognition`。
- 支持时将 `requiresOnDeviceRecognition` 设为 `true`，明确禁止联网识别。
- 不支持、模型未就绪、权限被拒绝或识别任务失败时，不创建网络后备路径，直接切换定速滚动。

## 已上架产品证据

### VoicePrompter

- 官方网站称可在 Instagram、TikTok 或任意相机 App 上方悬浮，并根据说话位置逐字跟随。
- App Store 描述称语音识别在设备端运行。
- App Store 版本记录明确提到，为悬浮 PiP 启用时的后台语音识别改善了后台运行表现。
- 原生 iOS 实现未开源，无法确认它使用的具体音频会话参数或兼容矩阵。

### FloatText 与 VoiceScroll

- 两者均在 App Store 描述中提供悬浮提词和语音跟读能力。
- 这些产品进一步证明需求不是理论功能，但公开页面不足以证明它们在所有设备上都能与 Apple 系统相机同步使用麦克风。

## 开源方案审计

### Open Prompter：最值得复用

仓库：<https://github.com/lelanddutcher/open-prompter>  
许可证：MIT  
审计提交：`f77c4a2729327ebbd4e20657e68c9cedf74231dc`

可复用部分：

- `SFSpeechRecognizer` 流式部分结果与端侧识别请求；
- 独立的 `VoiceTracker` 状态机；
- 局部文稿对齐、编辑距离、连续命中奖励和向前偏好；
- 识别结果到滚动目标之间的平滑层；
- 音频会话与录制生命周期协调；
- 较完整的匹配测试，可用作测试结构参考。

不能直接照搬的部分：

- 它把语音语言写成 `en-US`；
- 分词和 Double Metaphone 主要面向英文，连续中文文本会被错误地视为大词块；
- 它使用 App 内置相机，不回答 Apple 系统相机与后台麦克风共存问题；
- 因此适合借鉴架构和状态机，中文标准化与对齐器必须重写。

### SmartCue：适合借鉴停顿与平滑

仓库：<https://github.com/tulsie-narine/SmartCue>  
许可证：MIT  
审计提交：`d5dc3fc1a6a288a2134399b0a24d7f0e08d5c4df`

它用音频 RMS 能量快速判断用户是否正在说话，同时用 Speech 结果估算语速。RMS 很适合作为“开始/停顿”的低延迟辅助信号，但不能单独判断用户已经说到原稿哪个位置。其实现也没有 PiP 或系统相机共存方案，且没有强制端侧识别。

### 其他仓库

- `kosuvorov/VoicePrompter` 公共仓库是 Web/PWA 版本，不包含其原生 iOS App 的关键实现。
- `Hennadiyk/Telepromter` 和 `noskybee1012/Teleprompter` 有内置相机或 Speech 示例，但没有给出系统相机 + PiP + 后台端侧识别的完整方案；其中部分仓库许可证也不明确，不应直接复制代码。
- `iverson-home/telepoter` 有简单 `zh-CN` 识别示例，但缺少端侧能力检查、PiP、相机共存和生产级匹配逻辑，也没有可确认的代码许可证。

## 本项目的建议实现

### 音频与降级

1. 用户在主 App 内开启语音跟读。
2. 检查麦克风、语音权限和 `zh-CN` 端侧识别能力。
3. 以前台身份配置 `AVAudioSession`：`playAndRecord`、适合语音识别的 mode，并开启 `mixWithOthers`。
4. 确认持续收到音频 buffer 和部分识别结果后启动 PiP。
5. 用户切换到 Apple 系统相机并开始录制。
6. 监听音频中断、route change、识别任务结束和“连续无 buffer”超时。
7. 任一异常触发后在约一秒内切换定速滚动；停止语音任务，不在后台循环重启去争抢相机麦克风。

### 普通话中文文稿对齐

1. 原稿与识别结果统一简繁、数字、英文大小写和标点规则。
2. 以汉字为主要 token；英文和数字作为连续 token，不能沿用英文空格分词。
3. 维护最近约 6–12 个有效字符的识别窗口，只在当前位置附近搜索。
4. 评分组合字符级编辑距离、连续命中、当前位置距离和向前偏好。
5. 拼音无声调匹配只作为同音字的次要加分，不能单独触发远距离跳转。
6. 连续多次局部匹配失败后，才把范围扩大到当前段和后两段。
7. 匹配结果只更新“目标进度”，滚动层用缓动追赶，避免每次部分结果都跳屏。
8. RMS 音量只负责快速暂停/恢复提示，不作为文稿进度来源。

## 必做的真机技术验证

这一步必须由智能体和用户配合使用真实 iPhone 完成，不能由 Simulator 或纯自动化代替：

- 普通话端侧识别在前台正常工作；
- 启动 PiP 后切换到 Apple 系统相机，分别验证前后摄像头；
- 横屏、竖屏各持续录制至少 5 分钟；
- 同时检查提词器是否持续更新、语音 buffer/部分识别是否持续、相机视频是否有声音；
- 人为触发音频中断或识别失败，确认约一秒内自动切到定速滚动；
- 记录具体 iPhone 型号、iOS 版本、音频 route 和失败日志，形成首发支持矩阵。

这一步的验收结果只需要二选一：成功时提供语音跟读；失败时保留系统相机上方的悬浮定速提词。第一版不因此扩展到内置相机或联网识别。

## 资料来源

- Apple `playAndRecord`：<https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord>
- Apple `mixWithOthers`：<https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/mixwithothers>
- Apple Audio Session Programming Guide：<https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/>
- Apple `cannotInterruptOthers`：<https://developer.apple.com/documentation/coreaudiotypes/avaudiosessionerrorcode/avaudiosessionerrorcodecannotinterruptothers>
- Apple `supportsOnDeviceRecognition`：<https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition>
- Apple `requiresOnDeviceRecognition`：<https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition>
- VoicePrompter App Store：<https://apps.apple.com/us/app/voiceprompter-teleprompter/id6758573080>
- VoicePrompter 官方网站：<https://voiceprompter.app/ios/>
- FloatText App Store：<https://apps.apple.com/us/app/floattext/id1548261498>
- VoiceScroll App Store：<https://apps.apple.com/us/app/voicescroll-teleprompter/id6760583162>
- Open Prompter：<https://github.com/lelanddutcher/open-prompter>
- SmartCue：<https://github.com/tulsie-narine/SmartCue>
