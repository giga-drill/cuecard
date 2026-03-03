import AVKit
import UIKit
import SwiftUI

/// Manager for Picture-in-Picture teleprompter functionality
@MainActor
class TeleprompterPiPManager: NSObject, ObservableObject {
    static let shared = TeleprompterPiPManager()

    // MARK: - Published Properties

    @Published var isPiPActive = false
    @Published var isPiPPossible = false
    @Published var isPlaying = false

    // MARK: - Content Properties

    private(set) var text: String = ""
    private(set) var settings: TeleprompterSettings = .default
    private(set) var timerDuration: Int = 0
    private(set) var elapsedTime: Double = 0
    private(set) var currentWordIndex: Int = 0
    private(set) var isDarkMode: Bool = true
    private(set) var totalWords: Int = 0
    private(set) var countdownValue: Int = 0
    private(set) var isCountingDown: Bool = false

    // MARK: - PiP Components

    private var pipController: AVPictureInPictureController?
    private var pipViewController: AVPictureInPictureVideoCallViewController?
    private var teleprompterContentView: TeleprompterPiPContentView?
    private var pipContentView: TeleprompterPiPContentView?
    private var pipWindow: UIWindow?

    // MARK: - Timers

    private var displayLink: CADisplayLink?
    private var playbackTimer: Timer?
    private var playbackTimerStartDate: Date?
    private var elapsedTimeAtPlaybackStart: Double = 0
    private var needsContentViewUpdate = false

    // MARK: - Callbacks

    var onPiPClosed: (() -> Void)?
    var onPiPRestoreUI: (() -> Void)?
    var onPlayPauseFromPiP: ((Bool) -> Void)?
    var onRestartFromPiP: (() -> Void)?
    var onExpandFromPiP: (() -> Void)?

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Configure the PiP manager with content
    func configure(text: String, settings: TeleprompterSettings, timerDuration: Int, colorScheme: ColorScheme) {
        cleanup()
        self.text = text
        self.settings = settings
        self.timerDuration = timerDuration
        self.elapsedTime = 0
        self.currentWordIndex = 0
        self.isDarkMode = colorScheme == .dark

        let parsedContent = TeleprompterParser.parseNotes(text)
        totalWords = parsedContent.words.count

        setupPiP()
    }

    /// Update current state from TeleprompterView
    func updateState(elapsedTime: Double, isPlaying: Bool, currentWordIndex: Int = 0, countdownValue: Int = 0, isCountingDown: Bool = false) {
        self.elapsedTime = elapsedTime
        self.isPlaying = isPlaying
        self.currentWordIndex = currentWordIndex
        self.countdownValue = countdownValue
        self.isCountingDown = isCountingDown
        needsContentViewUpdate = true
    }

    /// Start PiP mode
    func startPiP(minimizeApp: Bool = false) {
        guard let pipController = pipController else {
            print("PiP controller not available")
            return
        }

        guard pipController.isPictureInPicturePossible else {
            print("PiP is not possible")
            return
        }

        pipController.startPictureInPicture()

        if minimizeApp {
            // Minimize the app after a short delay to let PiP start
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.minimizeApp()
            }
        }
    }

    /// Minimize the app to background
    func minimizeApp() {
        UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
    }

    /// Expand from PiP - bring app back to foreground
    func expandFromPiP() {
        stopPiP()
        onExpandFromPiP?()
    }

    /// Restart teleprompter from PiP
    func restartFromPiP() {
        stopPlaybackTimer()
        elapsedTime = 0
        currentWordIndex = 0
        isPlaying = false
        onRestartFromPiP?()
        updateContentView()
    }

    /// Toggle play/pause from PiP button
    func togglePlayPauseFromPiP() {
        isPlaying.toggle()
        if isPlaying {
            startPlaybackTimer()
        } else {
            stopPlaybackTimer()
        }
        onPlayPauseFromPiP?(isPlaying)
        updateContentView()
    }

    // MARK: - Playback Timer (for background PiP)

    private func startPlaybackTimer() {
        stopPlaybackTimer()
        playbackTimerStartDate = Date()
        elapsedTimeAtPlaybackStart = elapsedTime
        let interval = 1.0 / 30.0
        let timer = Timer(timeInterval: interval, target: self, selector: #selector(handlePlaybackTimerTick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        playbackTimer = timer
        needsContentViewUpdate = true
    }

    @objc private func handlePlaybackTimerTick() {
        guard isPlaying, let startDate = playbackTimerStartDate else { return }
        elapsedTime = elapsedTimeAtPlaybackStart + Date().timeIntervalSince(startDate)
        updateCurrentWordIndex()
        // Keep PiP motion smooth by rendering every playback tick.
        needsContentViewUpdate = true
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        playbackTimerStartDate = nil  // Prevents stale Task blocks from writing elapsedTime
    }

    /// Stop PiP mode
    func stopPiP() {
        pipController?.stopPictureInPicture()
    }

    /// Toggle play/pause
    func togglePlayPause() {
        isPlaying.toggle()
        updateContentView()
    }

    /// Seek forward 10 seconds
    func seekForward() {
        elapsedTime = min(elapsedTime + 10, timerDuration > 0 ? Double(timerDuration + 60) : 3600)
        // Reset wall-clock anchor so the playback timer continues from the new position
        if playbackTimerStartDate != nil {
            playbackTimerStartDate = Date()
            elapsedTimeAtPlaybackStart = elapsedTime
        }
        updateCurrentWordIndex()
        updateContentView()
    }

    /// Seek backward 10 seconds
    func seekBackward() {
        elapsedTime = max(elapsedTime - 10, 0)
        // Reset wall-clock anchor so the playback timer continues from the new position
        if playbackTimerStartDate != nil {
            playbackTimerStartDate = Date()
            elapsedTimeAtPlaybackStart = elapsedTime
        }
        updateCurrentWordIndex()
        updateContentView()
    }

    /// Cleanup resources
    func cleanup() {
        stopDisplayLink()
        stopPlaybackTimer()
        pipController?.stopPictureInPicture()
        pipController = nil
        pipViewController = nil
        teleprompterContentView?.removeFromSuperview()
        teleprompterContentView = nil
        pipContentView?.removeFromSuperview()
        pipContentView = nil
        pipWindow?.isHidden = true
        pipWindow = nil
        isPiPActive = false
    }

    // MARK: - PiP Setup

    private func setupPiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("PiP not supported on this device")
            isPiPPossible = false
            return
        }

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            print("No window scene available")
            return
        }

        let screenBounds = windowScene.screen.bounds
        let maxWidth = screenBounds.width
        let maxHeight = screenBounds.height
        let ratio = settings.overlayAspectRatio.ratio
        var preferredWidth = maxWidth
        var preferredHeight = preferredWidth / ratio
        if preferredHeight > maxHeight {
            preferredHeight = maxHeight
            preferredWidth = preferredHeight * ratio
        }
        let preferredSize = CGSize(width: preferredWidth, height: preferredHeight)
        let pipWidth = preferredSize.width
        let pipHeight = preferredSize.height

        // Create the teleprompter content view
        let contentView = TeleprompterPiPContentView(frame: CGRect(x: 0, y: 0, width: pipWidth, height: pipHeight))
        contentView.isDarkMode = isDarkMode
        self.teleprompterContentView = contentView

        // Create a host view controller
        let hostVC = UIViewController()
        hostVC.view.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: hostVC.view.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: hostVC.view.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: hostVC.view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: hostVC.view.trailingAnchor)
        ])

        // Create a hidden window to host the source view
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(x: -1000, y: -1000, width: pipWidth, height: pipHeight)
        window.rootViewController = hostVC
        window.isHidden = false
        window.windowLevel = .normal - 1
        self.pipWindow = window

        // Create the PiP video call view controller
        let pipVC = AVPictureInPictureVideoCallViewController()
        pipVC.preferredContentSize = preferredSize

        // Add content to PiP VC's view
        let pipContent = TeleprompterPiPContentView(frame: .zero)
        pipContent.isDarkMode = isDarkMode
        pipVC.view.addSubview(pipContent)
        pipContent.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pipContent.topAnchor.constraint(equalTo: pipVC.view.topAnchor),
            pipContent.bottomAnchor.constraint(equalTo: pipVC.view.bottomAnchor),
            pipContent.leadingAnchor.constraint(equalTo: pipVC.view.leadingAnchor),
            pipContent.trailingAnchor.constraint(equalTo: pipVC.view.trailingAnchor)
        ])
        self.pipContentView = pipContent
        self.pipViewController = pipVC

        // Create the PiP controller with video call content source
        let contentSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: contentView,
            contentViewController: pipVC
        )

        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        self.pipController = controller

        // Check if PiP is possible after setup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isPiPPossible = controller.isPictureInPicturePossible
        }

        // Start rendering
        startDisplayLink()
        updateContentView()
    }

    // MARK: - Content Rendering

    private func startDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(updateDisplay))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30)
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func updateDisplay() {
        guard needsContentViewUpdate else { return }
        needsContentViewUpdate = false
        updateContentView()
    }

    private func updateContentView() {
        let fontSize = CGFloat(settings.pipFontSize)
        let remainingTime = timerDuration > 0 ? timerDuration - Int(elapsedTime) : Int(elapsedTime)

        // Show countdown value if counting down (in mm:ss format), otherwise show timer
        let timerText = isCountingDown ? TeleprompterParser.formatTime(countdownValue) : TeleprompterParser.formatTime(remainingTime)

        let wordsPerSecond = Double(settings.wordsPerMinute) / 60.0
        let highlightProgress = (elapsedTime == 0 && !isPlaying)
            ? -Double.greatestFiniteMagnitude
            : (elapsedTime * wordsPerSecond)

        teleprompterContentView?.update(
            text: text,
            fontSize: fontSize,
            isPlaying: isPlaying,
            timerText: timerText,
            timerDuration: timerDuration,
            remainingTime: remainingTime,
            currentWordIndex: currentWordIndex,
            highlightProgress: highlightProgress,
            isCountingDown: isCountingDown
        )

        pipContentView?.update(
            text: text,
            fontSize: fontSize,
            isPlaying: isPlaying,
            timerText: timerText,
            timerDuration: timerDuration,
            remainingTime: remainingTime,
            currentWordIndex: currentWordIndex,
            highlightProgress: highlightProgress,
            isCountingDown: isCountingDown
        )
    }

    private func updateCurrentWordIndex() {
        guard totalWords > 0 else {
            currentWordIndex = 0
            return
        }
        let wordsPerSecond = Double(settings.wordsPerMinute) / 60.0
        let newWordIndex = min(Int(Double(elapsedTime) * wordsPerSecond), totalWords - 1)
        currentWordIndex = max(newWordIndex, 0)
    }

    // MARK: - Scroll Timer
    // Intentionally no internal timer; PiP mirrors the teleprompter state.
}

// MARK: - AVPictureInPictureControllerDelegate

extension TeleprompterPiPManager: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            isPiPActive = true
            // Start playback timer if already playing when PiP starts
            if isPlaying {
                startPlaybackTimer()
            }
        }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            isPiPActive = true
        }
    }

    nonisolated func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            stopPlaybackTimer()
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            isPiPActive = false
            onPiPClosed?()
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor in
            onPiPRestoreUI?()
            completionHandler(true)
        }
    }
}

// MARK: - Teleprompter PiP Content View

private class TeleprompterPiPContentView: UIView {
    private let textView = UITextView()
    private let timerLabel = UILabel()
    private let topGradientView = UIView()
    private let bottomGradientView = UIView()
    private var topGradientLayer: CAGradientLayer?
    private var bottomGradientLayer: CAGradientLayer?
    private var lastContentId: String = ""
    private var lastWordIndex: Int = -1
    private var lastProgressBucket: Double = -1
    private var cachedWordRanges: [NSRange] = []
    private var cachedLineWordRanges: [(start: Int, end: Int)] = []
    private var cachedNoteWordIndices: Set<Int> = []

    var isDarkMode: Bool = true {
        didSet {
            updateColors()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = true
        textView.showsVerticalScrollIndicator = false
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 40, left: 12, bottom: 40, right: 12)
        textView.textContainer.lineFragmentPadding = 0
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)

        timerLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .bold)
        timerLabel.textAlignment = .center
        timerLabel.layer.cornerRadius = 6
        timerLabel.layer.masksToBounds = true
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timerLabel)

        // Setup gradient views for fade effect
        topGradientView.translatesAutoresizingMaskIntoConstraints = false
        topGradientView.isUserInteractionEnabled = false
        addSubview(topGradientView)

        bottomGradientView.translatesAutoresizingMaskIntoConstraints = false
        bottomGradientView.isUserInteractionEnabled = false
        addSubview(bottomGradientView)

        NSLayoutConstraint.activate([
            timerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            timerLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            timerLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 50),
            timerLabel.heightAnchor.constraint(equalToConstant: 24),

            textView.topAnchor.constraint(equalTo: timerLabel.bottomAnchor, constant: 4),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            // Top gradient - starts at top of textView
            topGradientView.topAnchor.constraint(equalTo: textView.topAnchor),
            topGradientView.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            topGradientView.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
            topGradientView.heightAnchor.constraint(equalToConstant: 40),

            // Bottom gradient
            bottomGradientView.bottomAnchor.constraint(equalTo: textView.bottomAnchor),
            bottomGradientView.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            bottomGradientView.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
            bottomGradientView.heightAnchor.constraint(equalToConstant: 40)
        ])

        updateColors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        topGradientLayer?.frame = topGradientView.bounds
        bottomGradientLayer?.frame = bottomGradientView.bounds
    }

    private func updateColors() {
        let bgColor = isDarkMode ? AppColors.UIColors.Dark.background : AppColors.UIColors.Light.background
        backgroundColor = bgColor
        textView.textColor = isDarkMode ? AppColors.UIColors.Dark.textPrimary : AppColors.UIColors.Light.textPrimary

        // Update top gradient (fades from background to transparent)
        topGradientLayer?.removeFromSuperlayer()
        let topGradient = CAGradientLayer()
        topGradient.colors = [bgColor.cgColor, bgColor.withAlphaComponent(0).cgColor]
        topGradient.locations = [0.0, 1.0]
        topGradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        topGradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        topGradient.frame = topGradientView.bounds
        topGradientView.layer.addSublayer(topGradient)
        topGradientLayer = topGradient

        // Update bottom gradient (fades from transparent to background)
        bottomGradientLayer?.removeFromSuperlayer()
        let bottomGradient = CAGradientLayer()
        bottomGradient.colors = [bgColor.withAlphaComponent(0).cgColor, bgColor.cgColor]
        bottomGradient.locations = [0.0, 1.0]
        bottomGradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        bottomGradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        bottomGradient.frame = bottomGradientView.bounds
        bottomGradientView.layer.addSublayer(bottomGradient)
        bottomGradientLayer = bottomGradient
    }

    func update(
        text: String,
        fontSize: CGFloat,
        isPlaying: Bool,
        timerText: String,
        timerDuration: Int,
        remainingTime: Int,
        currentWordIndex: Int,
        highlightProgress: Double,
        isCountingDown: Bool = false
    ) {
        let contentId = text
        let hasActiveHighlight = highlightProgress > -1_000_000_000
        let progressBucket = hasActiveHighlight
            ? ((highlightProgress * 10).rounded(.down) / 10)
            : -Double.greatestFiniteMagnitude
        let previousWordIndex = lastWordIndex
        let needsFullRebuild = lastContentId != contentId
        let needsHighlightUpdate = !needsFullRebuild && lastProgressBucket != progressBucket
        let needsWordChange = previousWordIndex != currentWordIndex

        if needsFullRebuild {
            // Full rebuild: set attributedText and cache word ranges
            textView.attributedText = buildAttributedString(
                text: text,
                fontSize: fontSize,
                currentWordIndex: currentWordIndex,
                highlightProgress: highlightProgress
            )
            textView.layoutIfNeeded()
            textView.contentOffset = .zero
            cachedWordRanges = getWordRanges(from: text)
            cachedLineWordRanges = getLineWordRanges(from: text)
            cachedNoteWordIndices = getNoteWordIndices(from: text)
            lastContentId = contentId
            lastProgressBucket = progressBucket
        } else if needsHighlightUpdate || needsWordChange {
            updateHighlightColors(
                previousWordIndex: previousWordIndex,
                currentWordIndex: currentWordIndex,
                highlightProgress: highlightProgress
            )
            lastProgressBucket = progressBucket
        }

        if hasActiveHighlight {
            let didSeekOrJump = previousWordIndex >= 0 && abs(currentWordIndex - previousWordIndex) > 12
            let shouldSnap = needsFullRebuild || !isPlaying || didSeekOrJump
            updateHybridScroll(highlightProgress: highlightProgress, snapToTarget: shouldSnap)
        }

        lastWordIndex = currentWordIndex

        timerLabel.text = " \(timerText) "
        if isCountingDown {
            timerLabel.textColor = isDarkMode ? AppColors.UIColors.Dark.pink : AppColors.UIColors.Light.pink
        } else {
            timerLabel.textColor = AppColors.timerUIColor(
                remainingSeconds: remainingTime,
                totalSeconds: timerDuration,
                isDarkMode: isDarkMode
            )
        }
        timerLabel.backgroundColor = (isDarkMode ? AppColors.UIColors.Dark.background : AppColors.UIColors.Light.background).withAlphaComponent(0.8)
    }

    private func updateHighlightColors(previousWordIndex: Int, currentWordIndex: Int, highlightProgress: Double) {
        guard !cachedWordRanges.isEmpty else { return }
        let textColor = isDarkMode ? AppColors.UIColors.Dark.textPrimary : AppColors.UIColors.Light.textPrimary
        let fadeRange = 2.0

        let shouldRecolorAllWords = previousWordIndex < 0 || abs(currentWordIndex - previousWordIndex) > 16
        let lowerBound: Int
        let upperBound: Int
        if shouldRecolorAllWords {
            lowerBound = 0
            upperBound = cachedWordRanges.count - 1
        } else {
            let minIndex = min(previousWordIndex, currentWordIndex)
            let maxIndex = max(previousWordIndex, currentWordIndex)
            lowerBound = max(0, minIndex - 4)
            upperBound = min(cachedWordRanges.count - 1, maxIndex + 4)
        }
        guard upperBound >= lowerBound else { return }

        textView.textStorage.beginEditing()
        for wordIndex in lowerBound...upperBound {
            if cachedNoteWordIndices.contains(wordIndex) { continue }
            let range = cachedWordRanges[wordIndex]
            let distance = highlightProgress - Double(wordIndex)
            let t = min(max((distance + fadeRange) / fadeRange, 0.0), 1.0)
            let blend = t * t * (3.0 - 2.0 * t)
            let alpha = 0.3 + CGFloat(blend) * 0.7
            textView.textStorage.addAttribute(
                .foregroundColor,
                value: textColor.withAlphaComponent(alpha),
                range: range
            )
        }
        textView.textStorage.endEditing()
    }

    private func updateHybridScroll(highlightProgress: Double, snapToTarget: Bool) {
        guard !cachedWordRanges.isEmpty else { return }
        guard !cachedLineWordRanges.isEmpty else { return }

        let maxIndex = Double(cachedWordRanges.count - 1)
        let clampedProgress = min(max(highlightProgress, 0), maxIndex)
        let clampedWordIndex = Int(floor(clampedProgress))
        guard let currentLineIndex = lineIndex(for: clampedWordIndex) else { return }
        let currentLine = cachedLineWordRanges[currentLineIndex]
        let nextLineIndex = min(currentLineIndex + 1, cachedLineWordRanges.count - 1)

        guard let currentLineCenterY = lineCenterY(for: currentLineIndex),
              let nextLineCenterY = lineCenterY(for: nextLineIndex) else { return }

        // Hybrid behavior:
        // 1) Hold mostly steady on the current line for readability.
        // 2) Pre-scroll smoothly to the next line near the end of the current line.
        // 3) Keep a tiny correction while holding to prevent drift.
        let lineSpan = max(1, currentLine.end - currentLine.start + 1)
        let lineProgressRaw = (clampedProgress - Double(currentLine.start)) / Double(lineSpan)
        let lineProgress = min(max(lineProgressRaw, 0), 1)

        let preScrollStart = 0.80
        let transitionT: CGFloat
        if lineProgress <= preScrollStart {
            transitionT = 0
        } else {
            let rawT = (lineProgress - preScrollStart) / (1.0 - preScrollStart)
            let t = min(max(rawT, 0), 1)
            // Smoothstep easing for a natural glide.
            transitionT = CGFloat(t * t * (3.0 - 2.0 * t))
        }

        let focusCenterY = currentLineCenterY + (nextLineCenterY - currentLineCenterY) * transitionT
        let focusFraction: CGFloat = 0.36
        let targetY = focusCenterY - textView.bounds.height * focusFraction
        let maxY = max(0, textView.contentSize.height - textView.bounds.height)
        let clampedTargetY = max(0, min(targetY, maxY))
        let targetOffset = CGPoint(x: 0, y: clampedTargetY)

        if snapToTarget {
            textView.layer.removeAllAnimations()
            textView.setContentOffset(targetOffset, animated: false)
            return
        }

        let currentY = textView.contentOffset.y
        let delta = clampedTargetY - currentY
        if abs(delta) < 0.1 { return }

        let inTransition = lineProgress > preScrollStart
        let adaptiveGain: CGFloat = inTransition
            ? min(0.34, max(0.22, abs(delta) / 72.0))
            : min(0.16, max(0.10, abs(delta) / 140.0))
        var step = delta * adaptiveGain
        let maxStepPerFrame: CGFloat = inTransition ? 8.0 : 2.6
        if step > maxStepPerFrame { step = maxStepPerFrame }
        if step < -maxStepPerFrame { step = -maxStepPerFrame }
        let nextY = currentY + step
        textView.setContentOffset(CGPoint(x: 0, y: nextY), animated: false)
    }

    private func lineIndex(for wordIndex: Int) -> Int? {
        guard !cachedLineWordRanges.isEmpty else { return nil }
        let maxWordIndex = cachedLineWordRanges[cachedLineWordRanges.count - 1].end
        let clampedWordIndex = max(0, min(wordIndex, maxWordIndex))
        for (index, lineRange) in cachedLineWordRanges.enumerated() {
            if clampedWordIndex >= lineRange.start && clampedWordIndex <= lineRange.end {
                return index
            }
        }
        return nil
    }

    private func lineCenterY(for lineIndex: Int) -> CGFloat? {
        guard lineIndex >= 0, lineIndex < cachedLineWordRanges.count else { return nil }
        let anchorWordIndex = cachedLineWordRanges[lineIndex].start
        return wordCenterY(for: anchorWordIndex)
    }

    private func wordCenterY(for index: Int) -> CGFloat? {
        guard index >= 0, index < cachedWordRanges.count else { return nil }
        let range = cachedWordRanges[index]
        let glyphRange = textView.layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = textView.layoutManager.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer)
        return rect.midY + textView.textContainerInset.top
    }

    private func buildAttributedString(
        text: String,
        fontSize: CGFloat,
        currentWordIndex: Int,
        highlightProgress: Double
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        let noteFont = UIFont.systemFont(ofSize: fontSize * 0.72, weight: .semibold)
        let noteKern = fontSize * 0.05
        let fadeRange = 2.0

        func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
            let t = min(max((x - edge0) / (edge1 - edge0), 0.0), 1.0)
            return t * t * (3.0 - 2.0 * t)
        }

        func highlightAlpha(for index: Int) -> CGFloat {
            let distance = highlightProgress - Double(index)
            let blend = smoothstep(-fadeRange, 0.0, distance)
            return 0.3 + CGFloat(blend) * 0.7
        }

        let textColor = isDarkMode ? AppColors.UIColors.Dark.textPrimary : AppColors.UIColors.Light.textPrimary
        let pinkColor = isDarkMode ? AppColors.UIColors.Dark.pink : AppColors.UIColors.Light.pink

        var globalWordIndex = 0
        let paragraphs = text.components(separatedBy: "\n\n")

        for (paragraphIndex, paragraph) in paragraphs.enumerated() {
            if paragraphIndex > 0 {
                result.append(NSAttributedString(string: "\n"))
            }

            let lines = paragraph.components(separatedBy: "\n")

            for (lineIndex, line) in lines.enumerated() {
                if lineIndex > 0 {
                    result.append(NSAttributedString(string: "\n"))
                }

                if line.isEmpty { continue }

                if line.contains("[note") {
                    let noteContent = extractNoteContent(from: line)
                    let noteAttrs: [NSAttributedString.Key: Any] = [
                        .font: noteFont,
                        .foregroundColor: pinkColor,
                        .kern: noteKern
                    ]
                    let noteWords = noteContent.split(separator: " ", omittingEmptySubsequences: true)
                    for (wordIndex, word) in noteWords.enumerated() {
                        if wordIndex > 0 {
                            result.append(NSAttributedString(string: " ", attributes: noteAttrs))
                        }
                        result.append(NSAttributedString(string: String(word), attributes: noteAttrs))
                        globalWordIndex += 1
                    }
                } else {
                    let words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

                    for (wordIndex, word) in words.enumerated() {
                        if wordIndex > 0 {
                            result.append(NSAttributedString(string: " ", attributes: [
                                .font: font,
                                .foregroundColor: textColor
                            ]))
                        }

                        let alpha = highlightAlpha(for: globalWordIndex)
                        let color = textColor.withAlphaComponent(alpha)

                        let attrs: [NSAttributedString.Key: Any] = [
                            .font: font,
                            .foregroundColor: color
                        ]
                        result.append(NSAttributedString(string: word, attributes: attrs))

                        globalWordIndex += 1
                    }
                }
            }
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = fontSize * 0.18
        paragraphStyle.paragraphSpacing = fontSize * 0.45
        if result.length > 0 {
            result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))
        }

        return result
    }

    private func getWordRanges(from text: String) -> [NSRange] {
        var ranges: [NSRange] = []
        let fullText = NSMutableString()
        let paragraphs = text.components(separatedBy: "\n\n")

        for (paragraphIndex, paragraph) in paragraphs.enumerated() {
            if paragraphIndex > 0 {
                fullText.append("\n")
            }

            let lines = paragraph.components(separatedBy: "\n")

            for (lineIndex, line) in lines.enumerated() {
                if lineIndex > 0 {
                    fullText.append("\n")
                }

                if line.isEmpty { continue }

                if line.contains("[note") {
                    let noteContent = extractNoteContent(from: line)
                    let noteWords = noteContent.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                    for (wordIndex, word) in noteWords.enumerated() {
                        if wordIndex > 0 {
                            fullText.append(" ")
                        }
                        let location = fullText.length
                        fullText.append(word)
                        ranges.append(NSRange(location: location, length: word.count))
                    }
                } else {
                    let words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

                    for (wordIndex, word) in words.enumerated() {
                        if wordIndex > 0 {
                            fullText.append(" ")
                        }
                        let location = fullText.length
                        fullText.append(word)
                        ranges.append(NSRange(location: location, length: word.count))
                    }
                }
            }
        }

        return ranges
    }

    private func getLineWordRanges(from text: String) -> [(start: Int, end: Int)] {
        var lineRanges: [(start: Int, end: Int)] = []
        var globalWordIndex = 0
        let paragraphs = text.components(separatedBy: "\n\n")

        for paragraph in paragraphs {
            let lines = paragraph.components(separatedBy: "\n")
            for line in lines {
                if line.isEmpty { continue }
                let wordCount = wordsInDisplayLine(line)
                if wordCount == 0 { continue }
                let start = globalWordIndex
                globalWordIndex += wordCount
                lineRanges.append((start: start, end: globalWordIndex - 1))
            }
        }

        return lineRanges
    }

    private func wordsInDisplayLine(_ line: String) -> Int {
        if line.contains("[note") {
            let noteContent = extractNoteContent(from: line)
            return noteContent.split(separator: " ", omittingEmptySubsequences: true).count
        }
        return line.split(separator: " ", omittingEmptySubsequences: true).count
    }

    private func getNoteWordIndices(from text: String) -> Set<Int> {
        var indices = Set<Int>()
        var globalWordIndex = 0
        let paragraphs = text.components(separatedBy: "\n\n")
        for paragraph in paragraphs {
            let lines = paragraph.components(separatedBy: "\n")
            for line in lines {
                if line.isEmpty { continue }
                if line.contains("[note") {
                    let noteContent = extractNoteContent(from: line)
                    let noteWords = noteContent.split(separator: " ", omittingEmptySubsequences: true)
                    for _ in noteWords {
                        indices.insert(globalWordIndex)
                        globalWordIndex += 1
                    }
                } else {
                    let words = line.split(separator: " ", omittingEmptySubsequences: true)
                    globalWordIndex += words.count
                }
            }
        }
        return indices
    }

    private func extractNoteContent(from line: String) -> String {
        let pattern = #"\[note\s+([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let contentRange = Range(match.range(at: 1), in: line) else {
            return line
        }
        return String(line[contentRange])
    }
}
