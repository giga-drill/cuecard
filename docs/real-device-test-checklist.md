# Apple 系统相机真机测试清单

状态：**尚未执行，所有结果均为待验证**
目标：判断 CueCard 在 PiP 后台运行时，端侧普通话识别能否与 Apple 系统相机录像稳定共存；若不能，确认约一秒内退回定速滚动。

## 一次性准备

1. 使用运行 iOS 17 或更高版本的真实 iPhone，解锁、连接 Mac、选择“信任”，并开启 Developer Mode。
2. 在 Xcode 登录 Apple ID，为 `CueCard` target 选择个人或团队的 Apple Development Team。当前 Mac 没有可用的代码签名证书，首次真机安装必须完成这一步。
3. 打开 `cuecard-mobile/ios/CueCard/CueCard.xcodeproj`，选择连接的 iPhone，按 Run 安装 Debug 版。
4. 首次启动时允许麦克风和语音识别权限。App 固定使用 `zh-CN` 端侧识别，不允许联网后备。
5. 可先验证 arm64 Debug 编译：

   ```sh
   ./scripts/build-device-debug.sh
   ```

## 启动日志采集

在仓库根目录执行：

```sh
./scripts/capture-device-speech-logs.sh '<设备名称或标识>'
```

当前曾发现的设备名称为 `王维扬的iPhone`，但生成本清单时状态为 `unavailable`。设备连接后也可先运行 `xcrun devicectl list devices` 获取最新标识。

日志脚本会重新启动 CueCard 并持续等待。测试全部结束后按 Control-C。日志默认保存到 `artifacts/device-tests/`，随后执行：

```sh
./scripts/summarize-device-speech-log.sh artifacts/device-tests/<日志文件>
```

## 每组测试的操作

使用一篇至少能朗读五分钟的普通话中文文稿，每组均执行以下步骤：

1. 在 CueCard 打开文稿并开始播放。
2. 点击 PiP 按钮；进入 PiP 前确认模式标识由 `Fixed speed` 变为 `Voice follow`。
3. 手动切换到 Apple 系统相机。
4. 选择指定摄像头和手机方向，开始录像。
5. 按文稿正常朗读五分钟，中间包含一次约两秒停顿、一次重复上一句、一次小口误和一次跳过一句。
6. 观察 PiP：朗读时平滑推进，停顿时停止，恢复后继续；若麦克风被中断，应在约一秒内显示 `Fixed speed` 并继续滚动。
7. 停止录像，播放成片，确认人声存在且连续。
8. 回到 CueCard，确认阅读位置、播放状态和方向没有重置。
9. 在结果表记录现象，不确定时保留原始日志和视频，不填写“通过”。

## 测试矩阵

| 编号 | 摄像头 | 方向 | 连续时长 | PiP 跟读 | 成片声音 | 降级行为 | 状态 |
|---|---|---|---:|---|---|---|---|
| A | 后置 | 竖屏 | 5 分钟 | 待验证 | 待验证 | 待验证 | 未执行 |
| B | 后置 | 横屏 | 5 分钟 | 待验证 | 待验证 | 待验证 | 未执行 |
| C | 前置 | 竖屏 | 5 分钟 | 待验证 | 待验证 | 待验证 | 未执行 |
| D | 前置 | 横屏 | 5 分钟 | 待验证 | 待验证 | 待验证 | 未执行 |

## 明确验证定速降级

1. 在 iPhone 设置中暂时关闭 CueCard 的麦克风权限。
2. 重新打开 CueCard，从文稿中部开始，点击 PiP。
3. 确认模式保持或切换为 `Fixed speed`，文字继续从当前位置推进，不能回到开头。
4. 测试后恢复麦克风权限，再执行上述 A–D 矩阵。

## 日志判定

- `sessionConfigured` 和 `sessionActivated`：语音会话已按 `playAndRecord + mixWithOthers` 在前台激活。
- `audioBuffer`、`partialTranscript`：持续收到麦克风数据和识别结果。
- `pipStarted` 后出现 `appBackgrounded`：已进入 PiP 并切换到系统相机。
- `appBackgrounded` 后仍持续出现 `audioBuffer`、`partialTranscript`、`voiceAlignment`：支持系统相机与后台跟读共存的正向证据。
- `interruptionBegan`、`noBufferTimeout` 或识别错误后出现 `fallbackToFixedSpeed`：麦克风不共存，但自动降级路径正常。
- 相机成片无人声：即使 CueCard 仍在识别也判定失败，不能以 PiP 滚动正常代替成片声音验收。

真机结果出来前，项目只能声明“已完成实现与模拟器自动测试”，不能声明“已兼容 Apple 系统相机语音跟读”。
