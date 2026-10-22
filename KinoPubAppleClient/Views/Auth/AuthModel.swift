//
//  AuthModel.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 27.07.2023.
//

import Foundation
import SwiftUI
import KinoPubUI
import KinoPubBackend
import KinoPubLogging
import OSLog
#if canImport(UIKit)
import UIKit
#endif
#if os(iOS)
import UserNotifications
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Manages the iOS background execution window while the user switches to Safari or
/// another app to enter the activation code.
@MainActor
protocol AuthBackgroundTaskManaging: AnyObject {
  func beginBackgroundTask(expirationHandler: @escaping @MainActor () -> Void)
  func endBackgroundTask()
}

@MainActor
final class SystemAuthBackgroundTaskManager: AuthBackgroundTaskManaging {
#if os(iOS)
  private var taskIdentifier: UIBackgroundTaskIdentifier = .invalid
#endif

  func beginBackgroundTask(expirationHandler: @escaping @MainActor () -> Void) {
#if os(iOS)
    endBackgroundTask()
    taskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "KinoPubDeviceCodeAuth") { [weak self] in
      Task { @MainActor in
        self?.endBackgroundTask()
        expirationHandler()
      }
    }
#endif
  }

  func endBackgroundTask() {
#if os(iOS)
    guard taskIdentifier != .invalid else { return }
    let id = taskIdentifier
    taskIdentifier = .invalid
    UIApplication.shared.endBackgroundTask(id)
#endif
  }
}

/// Delivers haptics and background local notifications when device-code activation completes.
@MainActor
protocol AuthFeedbackHandling: AnyObject {
  func prepareForActivation()
  func didAuthorize(inBackground: Bool)
}

@MainActor
final class SystemAuthFeedbackHandler: AuthFeedbackHandling {
  func prepareForActivation() {
#if os(iOS)
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      guard settings.authorizationStatus == .notDetermined else { return }
      center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
#endif
  }

  func didAuthorize(inBackground: Bool) {
#if os(iOS)
    let generator = UINotificationFeedbackGenerator()
    generator.notificationOccurred(.success)

    let shouldNotify = inBackground || UIApplication.shared.applicationState != .active
    guard shouldNotify else { return }

    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      guard settings.authorizationStatus == .authorized
              || settings.authorizationStatus == .provisional else { return }
      let content = UNMutableNotificationContent()
      content.title = NSLocalizedString("Auth_NotificationTitle", comment: "")
      content.body = NSLocalizedString("Auth_NotificationBody", comment: "")
      content.sound = .default
      let request = UNNotificationRequest(
        identifier: "kinopub.auth.deviceActivated",
        content: content,
        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
      )
      center.add(request) { error in
        if let error {
          Logger.app.error("Failed to post auth notification: \(String(describing: error))")
        }
      }
    }
#endif
  }
}

/// Drives the device-activation screen: fetches a 5-minute device code, preserves the
/// active code across background/foreground transitions until its real `expiresAt`,
/// continues polling during the iOS background task window, immediately polls on
/// returning to foreground, and explicitly surfaces expiration and error states.
@MainActor
class AuthModel: ObservableObject {

  enum PollOutcome: Equatable {
    case authorized
    case pending
    case expired
    case failed(String)
  }

  private var authService: AuthorizationService
  private var authState: AuthState
  private let backgroundTaskManager: AuthBackgroundTaskManaging
  private let feedbackHandler: AuthFeedbackHandling
  private let now: @Sendable () -> Date
  private let sleep: @Sendable (TimeInterval) async -> Void

  /// The code the user types on the website. Empty until the first one arrives.
  @Published var deviceCode: String = ""
  /// Where to type it, as returned by the backend — shown as plain text on tvOS.
  @Published var verificationURL: String = ""
  /// A new code request is in flight.
  @Published var isRefreshing: Bool = true
  /// Validity window (`issuedAt...expiresAt`) for the active device code.
  @Published var codeValidRange: ClosedRange<Date>?
  /// True once the 5-minute TTL has elapsed or the server rejected the device code.
  /// Rather than silently swapping the code out from under the user, we show an
  /// explicit expired state with a button to request a fresh code.
  @Published var isExpired: Bool = false
  /// User-facing error message when fetching a code or polling fails.
  @Published var errorMessage: String?
  /// Copy confirmation toast.
  @Published var hudToast: HudToast?

  /// The currently active verification payload. Preserved across background/foreground
  /// transitions until `codeValidRange.upperBound` elapses or `requestNewCode()` is called.
  private(set) var activeVerification: VerificationResponse?
  /// Whether the app is currently in the background.
  private(set) var isInBackground: Bool = false
  /// Timestamp of the latest user interaction (code issued, copied, opened, or foregrounded),
  /// used to keep polling fast (5s) during active interaction and scale back later.
  private(set) var lastInteractionAt: Date?
  /// Backoff interval set when the server responds with OAuth `slow_down`.
  private(set) var slowDownInterval: TimeInterval?

  private var isRunLoopActive = false
  private var isPollLoopRunning = false
  private var isBackgroundTaskExpired = false
  private var rescheduleSleepOnly = false
  private var pollSleepTask: Task<Void, Never>?
  private var expiryTask: Task<Void, Never>?
  private var inFlightPollTask: Task<PollOutcome, Never>?
  private var stateWakeupContinuation: CheckedContinuation<Void, Never>?
  private let openURLHandler: (@MainActor (URL) -> Void)?
  nonisolated(unsafe) private var lifecycleObservers: [NSObjectProtocol] = []

  init(
    authService: AuthorizationService,
    authState: AuthState,
    backgroundTaskManager: AuthBackgroundTaskManaging? = nil,
    feedbackHandler: AuthFeedbackHandling? = nil,
    now: @escaping @Sendable () -> Date = { Date() },
    sleep: @escaping @Sendable (TimeInterval) async -> Void = {
      try? await Task.sleep(for: .seconds($0))
    },
    openURLHandler: (@MainActor (URL) -> Void)? = nil,
    observesSystemLifecycle: Bool = true
  ) {
    self.authService = authService
    self.authState = authState
    self.backgroundTaskManager = backgroundTaskManager ?? SystemAuthBackgroundTaskManager()
    self.feedbackHandler = feedbackHandler ?? SystemAuthFeedbackHandler()
    self.now = now
    self.sleep = sleep
    self.openURLHandler = openURLHandler

    if observesSystemLifecycle {
      installLifecycleObservers()
    }
  }

  deinit {
    for observer in lifecycleObservers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  // MARK: - Lifecycle

  /// Driven from `AuthView`'s `.task`. Re-entering `run()` while an unexpired code is
  /// already present preserves that code instead of requesting a new one.
  func run() async {
    isRunLoopActive = true
    defer {
      isRunLoopActive = false
      pollSleepTask?.cancel()
      pollSleepTask = nil
      resumeStateWakeup()
    }

    if authState.adoptKeychainTokenIfPresent() {
      return
    }

    await requestDeviceCodeIfNeeded()

    while !Task.isCancelled && authState.phase != .signedIn {
      if activeVerification != nil, !isExpired, errorMessage == nil, !(isInBackground && isBackgroundTaskExpired) {
        await runPollLoop()
      } else {
        await waitForStateWakeup()
      }
    }
  }

  /// Requests a device code only if there isn't already a valid, unexpired code.
  func requestDeviceCodeIfNeeded() async {
    if authState.adoptKeychainTokenIfPresent() {
      return
    }
    if let range = codeValidRange, activeVerification != nil {
      if now() < range.upperBound && !isExpired {
        isRefreshing = false
        scheduleExpiryTimer(until: range.upperBound)
        return
      } else {
        markExpired()
        return
      }
    }
    guard !isExpired else { return }
    await fetchNewDeviceCode()
  }

  /// Explicitly requests a brand-new device code (used initially and when the user taps
  /// "Get New Code" after expiration).
  func requestNewCode() async {
    cancelPollingAndTimers()
    activeVerification = nil
    isExpired = false
    errorMessage = nil
    slowDownInterval = nil
    await fetchNewDeviceCode()
    resumeStateWakeup()
  }

  /// Retries after an error or expiration. Preserves and polls the current device code
  /// if it is still unexpired; otherwise requests a new device code.
  func retry() async {
    if authState.adoptKeychainTokenIfPresent() {
      return
    }

    if isExpired || activeVerification == nil {
      await requestNewCode()
      return
    }

    if let expiresAt = codeValidRange?.upperBound, now() >= expiresAt {
      await requestNewCode()
      return
    }

    errorMessage = nil
    lastInteractionAt = now()
    let outcome = await pollOnce()
    if outcome == .pending {
      reschedulePollSleep()
      resumeStateWakeup()
    }
  }

  /// Called when the app transitions to background. Keeps the current device code intact
  /// and starts an iOS background task so polling can continue while the user switches
  /// to Safari to submit the code.
  func handleDidEnterBackground() {
    guard !isInBackground else { return }
    isInBackground = true
    isBackgroundTaskExpired = false

    guard authState.phase != .signedIn,
          activeVerification != nil,
          !isExpired else {
      return
    }

    backgroundTaskManager.beginBackgroundTask { [weak self] in
      guard let self else { return }
      self.isBackgroundTaskExpired = true
      self.pollSleepTask?.cancel()
      self.pollSleepTask = nil
      self.backgroundTaskManager.endBackgroundTask()
    }
  }

  /// Called when the app returns to the foreground (`scenePhase == .active` /
  /// `willEnterForegroundNotification`). Never resets an unexpired code; immediately
  /// checks whether the user completed activation while in Safari.
  func handleDidBecomeActive() async {
    isInBackground = false
    isBackgroundTaskExpired = false
    backgroundTaskManager.endBackgroundTask()

    guard authState.phase != .signedIn else { return }

    if authState.adoptKeychainTokenIfPresent() {
      feedbackHandler.didAuthorize(inBackground: false)
      cancelPollingAndTimers()
      resumeStateWakeup()
      return
    }

    if let expiresAt = codeValidRange?.upperBound, activeVerification != nil {
      if now() >= expiresAt {
        markExpired()
        return
      }

      // Code is still within its 5-minute validity window: preserve it, reset the
      // smart-polling interaction timestamp, clear any transient error, and immediately
      // poll before waiting for the next timer tick.
      lastInteractionAt = now()
      errorMessage = nil
      let outcome = await pollOnce()
      if outcome == .pending {
        reschedulePollSleep()
        resumeStateWakeup()
      }
      return
    }

    if !isExpired && !isRefreshing {
      await requestNewCode()
    }
  }

  /// Checks whether the active code has passed its `expiresAt` timestamp and transitions
  /// to the explicit expired state if so.
  @discardableResult
  func checkExpiration() -> Bool {
    guard !isExpired,
          authState.phase != .signedIn,
          let expiresAt = codeValidRange?.upperBound else {
      return isExpired
    }
    if now() >= expiresAt {
      markExpired()
      return true
    }
    return false
  }

  // MARK: - Smart Polling

  /// Computes the next polling interval for `response`:
  /// - 5s (or server floor) during the first 60s after code arrival, copy, activate, or foreground return
  /// - 15s during minutes 1–3
  /// - 25s during minutes 3–5
  /// Honours OAuth `slow_down` backoff when present.
  func currentPollInterval(for response: VerificationResponse? = nil) -> TimeInterval {
    let target = response ?? activeVerification
    let baseInterval = max(TimeInterval(target?.interval ?? 5), 5)
    if let slowDownInterval {
      return max(slowDownInterval, baseInterval)
    }

    let referenceDate = lastInteractionAt ?? codeValidRange?.lowerBound ?? now()
    let elapsed = max(0, now().timeIntervalSince(referenceDate))
    if elapsed < 60 {
      return baseInterval
    } else if elapsed < 180 {
      return max(baseInterval, 15)
    } else {
      return max(baseInterval, 25)
    }
  }

  /// Executes a single poll check against the backend (deduplicated if a poll is already in flight).
  @discardableResult
  func pollOnce() async -> PollOutcome {
    if authState.phase == .signedIn {
      return .authorized
    }
    if authState.adoptKeychainTokenIfPresent() {
      feedbackHandler.didAuthorize(inBackground: isInBackground)
      backgroundTaskManager.endBackgroundTask()
      cancelPollingAndTimers()
      return .authorized
    }
    guard let response = activeVerification,
          let expiresAt = codeValidRange?.upperBound else {
      return isExpired ? .expired : .pending
    }
    if now() >= expiresAt {
      markExpired()
      return .expired
    }

    if let inFlightPollTask {
      return await inFlightPollTask.value
    }

    let task = Task<PollOutcome, Never> { @MainActor in
      await self.performSinglePoll(with: response, expiresAt: expiresAt)
    }
    inFlightPollTask = task
    let outcome = await task.value
    inFlightPollTask = nil
    return outcome
  }

  private func performSinglePoll(with response: VerificationResponse, expiresAt: Date) async -> PollOutcome {
    do {
      try await authService.fetchToken(by: response)
      let completedInBackground = isInBackground
      cancelPollingAndTimers()
      activeVerification = nil
      isExpired = false
      errorMessage = nil
      authState.markSignedIn(activated: true)
      feedbackHandler.didAuthorize(inBackground: completedInBackground)
      backgroundTaskManager.endBackgroundTask()
      Logger.app.debug("Device token authorized")
      return .authorized
    } catch let error as APIClientError where error.isAuthorizationPending {
      errorMessage = nil
      return .pending
    } catch let error as APIClientError where error.isSlowDown {
      errorMessage = nil
      let base = max(TimeInterval(response.interval), 5)
      let nextInterval = min((slowDownInterval ?? base) * 2, 30)
      slowDownInterval = nextInterval
      Logger.app.debug("device poll slow_down — backing off to \(nextInterval)s")
      return .pending
    } catch let error as APIClientError where error.isDeviceCodeExpired {
      Logger.app.info("Device code rejected as expired/invalid by server")
      markExpired()
      return .expired
    } catch is CancellationError {
      return .pending
    } catch let error as APIClientError where error.isCancellation {
      return .pending
    } catch {
      if now() >= expiresAt {
        markExpired()
        return .expired
      }
      // Switching to Safari on iOS routinely aborts the in-flight socket as the app
      // backgrounds. Never treat a background transport drop as a user-visible error or
      // a reason to discard the active code.
      if isInBackground && Self.isTransientTransportError(error) {
        Logger.app.debug("Ignoring transient background poll transport error: \(String(describing: error))")
        return .pending
      }
      let message = error.userFacingMessage
      errorMessage = message
      Logger.app.debug("Token poll failed with error: \(String(describing: error))")
      return .failed(message)
    }
  }

  // MARK: - Actions & Sharing

  /// tvOS has no pasteboard worth writing to — there the code is read off the screen.
  var canCopyCode: Bool {
#if os(tvOS)
    false
#else
    !deviceCode.isEmpty && !isExpired
#endif
  }

  /// Full activation URL suitable for opening in a browser or sharing via `ShareLink`.
  var activationURL: URL? {
    let raw = activeVerification?.verificationUri ?? verificationURL
    guard !raw.isEmpty else { return nil }
    let normalized = raw.hasPrefix("http") ? raw : "https://\(raw)"
    return URL(string: normalized)
  }

  /// Non-optional URL for `ShareLink` (falls back to `https://kino.pub/device` while loading).
  var shareURL: URL {
    activationURL ?? URL(string: "https://kino.pub/device")!
  }

  /// Text shared alongside the activation URL when the user taps Share.
  var shareMessage: String {
    let hostPath = verificationURL.isEmpty ? "kino.pub/device" : verificationURL
    return String(format: "Auth_ShareMessage %@ %@".localized, hostPath, deviceCode)
  }

  func copyCode() {
    guard !deviceCode.isEmpty, !isExpired else { return }
    lastInteractionAt = now()
    feedbackHandler.prepareForActivation()
    guard canCopyCode else { return }
#if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(deviceCode, forType: .string)
#elseif canImport(UIKit) && !os(tvOS)
    UIPasteboard.general.string = deviceCode
#endif
    hudToast = HudToast(systemImage: "document.on.document.fill", title: "Copied".localized)
  }

  /// Opening the site without the code in hand means going back for it — so Activate
  /// copies first. One press, then paste.
  func activate() {
    guard !deviceCode.isEmpty, !isExpired else { return }
    copyCode()
    openActivationURL()
  }

  func openActivationURL() {
    guard let url = activationURL else { return }
    lastInteractionAt = now()
    feedbackHandler.prepareForActivation()
    Logger.app.debug("open activation url: \(url)")

    if let openURLHandler {
      openURLHandler(url)
      return
    }

#if canImport(UIKit)
    UIApplication.shared.open(url)
#elseif os(macOS)
    NSWorkspace.shared.open(url)
#endif
  }

  // MARK: - Private Helpers

  private func fetchNewDeviceCode() async {
    Logger.app.debug("Fetch device code...")
    isRefreshing = true
    errorMessage = nil
    isExpired = false

    do {
      let response = try await authService.fetchDeviceCode()
      Logger.app.debug("receive device code: \(response.userCode)")
      let issuedAt = now()
      let expiresAt = issuedAt.addingTimeInterval(TimeInterval(response.expiresIn))
      activeVerification = response
      deviceCode = response.userCode
      verificationURL = displayURL(from: response.verificationUri)
      codeValidRange = issuedAt...expiresAt
      lastInteractionAt = issuedAt
      slowDownInterval = nil
      isRefreshing = false
      isExpired = false
      errorMessage = nil
      scheduleExpiryTimer(until: expiresAt)
    } catch is CancellationError {
      isRefreshing = false
    } catch let error as APIClientError where error.isCancellation {
      isRefreshing = false
    } catch {
      Logger.app.debug("failed to fetch device code: \(String(describing: error))")
      isRefreshing = false
      errorMessage = error.userFacingMessage
    }
  }

  private func runPollLoop() async {
    guard !isPollLoopRunning else { return }
    isPollLoopRunning = true
    defer { isPollLoopRunning = false }

    while !Task.isCancelled {
      guard authState.phase != .signedIn,
            !isExpired,
            errorMessage == nil,
            !(isInBackground && isBackgroundTaskExpired) else { return }
      guard let response = activeVerification,
            let expiresAt = codeValidRange?.upperBound else { return }

      let remaining = expiresAt.timeIntervalSince(now())
      if remaining <= 0 {
        markExpired()
        return
      }

      let delay = min(currentPollInterval(for: response), remaining)
      let sleepJob = Task { await sleep(delay) }
      pollSleepTask = sleepJob
      await withTaskCancellationHandler {
        await sleepJob.value
      } onCancel: {
        sleepJob.cancel()
      }
      if pollSleepTask == sleepJob {
        pollSleepTask = nil
      }

      guard !Task.isCancelled,
            authState.phase != .signedIn,
            !isExpired,
            errorMessage == nil,
            !(isInBackground && isBackgroundTaskExpired) else {
        return
      }

      if rescheduleSleepOnly {
        rescheduleSleepOnly = false
        continue
      }

      let outcome = await pollOnce()
      switch outcome {
      case .authorized, .expired, .failed:
        return
      case .pending:
        continue
      }
    }
  }

  private func markExpired() {
    cancelPollingAndTimers()
    isRefreshing = false
    errorMessage = nil
    isExpired = true
    backgroundTaskManager.endBackgroundTask()
    Logger.app.debug("Device code expired")
  }

  private func scheduleExpiryTimer(until expiresAt: Date) {
    expiryTask?.cancel()
    let remaining = max(0, expiresAt.timeIntervalSince(now()))
    expiryTask = Task { [weak self] in
      guard let self else { return }
      await self.sleep(remaining)
      guard !Task.isCancelled else { return }
      if self.now() >= expiresAt, self.authState.phase != .signedIn {
        self.markExpired()
      }
    }
  }

  private func reschedulePollSleep() {
    guard isPollLoopRunning else { return }
    rescheduleSleepOnly = true
    pollSleepTask?.cancel()
  }

  private func cancelPollingAndTimers() {
    rescheduleSleepOnly = false
    pollSleepTask?.cancel()
    pollSleepTask = nil
    expiryTask?.cancel()
    expiryTask = nil
  }

  private func waitForStateWakeup() async {
    guard !Task.isCancelled else { return }
    await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        stateWakeupContinuation?.resume()
        stateWakeupContinuation = continuation
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        self?.resumeStateWakeup()
      }
    }
  }

  private func resumeStateWakeup() {
    guard let continuation = stateWakeupContinuation else { return }
    stateWakeupContinuation = nil
    continuation.resume()
  }

  private func installLifecycleObservers() {
#if os(iOS) || os(tvOS)
    let bg = NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.handleDidEnterBackground()
      }
    }
    let fg = NotificationCenter.default.addObserver(
      forName: UIApplication.willEnterForegroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.isInBackground else { return }
        await self.handleDidBecomeActive()
      }
    }
    lifecycleObservers = [bg, fg]
#elseif os(macOS)
    let bg = NotificationCenter.default.addObserver(
      forName: NSApplication.didResignActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.handleDidEnterBackground()
      }
    }
    let fg = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.isInBackground else { return }
        await self.handleDidBecomeActive()
      }
    }
    lifecycleObservers = [bg, fg]
#endif
  }

  private static func isTransientTransportError(_ error: Error) -> Bool {
    if error is URLError { return true }
    if case .networkError(let underlying) = error as? APIClientError {
      if underlying is URLError { return true }
      let nsError = underlying as NSError
      return nsError.domain == NSURLErrorDomain || nsError.domain == NSPOSIXErrorDomain
    }
    let nsError = error as NSError
    return nsError.domain == NSURLErrorDomain || nsError.domain == NSPOSIXErrorDomain
  }

  /// `https://kino.pub/device` reads better on a TV as `kino.pub/device`.
  private func displayURL(from uri: String) -> String {
    uri
      .replacingOccurrences(of: "https://", with: "")
      .replacingOccurrences(of: "http://", with: "")
      .replacingOccurrences(of: "www.", with: "")
  }

}
