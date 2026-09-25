/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// Arbitrates the hand-off between the process exit source, an explicit `terminate()` and whoever
/// is waiting on the exit.
///
/// `@unchecked Sendable`: all mutable state is guarded by `lock`.
private final class TerminationState: @unchecked Sendable {
  private let lock = NSLock()
  private var continuations: [CheckedContinuation<Void, Never>] = []
  private var exited = false
  private var explicitlyTerminated = false

  var hasExited: Bool {
    lock.withLock { exited }
  }

  var wasExplicitlyTerminated: Bool {
    lock.withLock { explicitlyTerminated }
  }

  /// Returns false when the process had already exited, in which case there is nothing left to
  /// terminate and waiters still see a normal exit, or when another caller is already
  /// terminating it, so the kill is issued once.
  func markExplicitlyTerminated() -> Bool {
    lock.withLock {
      if exited || explicitlyTerminated {
        return false
      }
      explicitlyTerminated = true
      return true
    }
  }

  /// Undoes `markExplicitlyTerminated()` for a kill that did not happen, so an exit that
  /// follows is reported as the normal exit it is.
  func clearExplicitTermination() {
    lock.withLock { explicitlyTerminated = false }
  }

  /// Idempotent: the exit source's handler can be invoked again before the cancellation it
  /// requests takes effect.
  func markExited() {
    lock.lock()
    if exited {
      lock.unlock()
      return
    }
    exited = true
    let continuations = self.continuations
    self.continuations = []
    lock.unlock()

    for continuation in continuations {
      continuation.resume()
    }
  }

  func waitForExit() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      lock.lock()
      if exited {
        lock.unlock()
        continuation.resume()
        return
      }
      continuations.append(continuation)
      lock.unlock()
    }
  }
}

/// Carries the attachment into the termination task.
///
/// `@unchecked Sendable`: `FBProcessFileAttachment` is not annotated, but the task is its only
/// consumer there and `detach` is documented as safe to call more than once.
private final class AttachmentBox: @unchecked Sendable {
  let attachment: FBProcessFileAttachment

  init(_ attachment: FBProcessFileAttachment) {
    self.attachment = attachment
  }
}

public final class SimulatorLaunchedApplication: LaunchedApplication, CustomStringConvertible {

  public let configuration: ApplicationLaunchConfiguration
  public let processIdentifier: pid_t

  // MARK: - Private Properties

  private let attachment: FBProcessFileAttachment
  private let terminationStrategy: ProcessTerminationStrategy
  private let state: TerminationState
  private let terminationTask: Task<Void, Never>

  // MARK: - LaunchedApplication Protocol

  public var bundleID: String {
    configuration.bundleID
  }

  public func waitForTermination() async throws {
    await terminationTask.value
    // An explicit `terminate()` is reported as a cancellation rather than as an observed exit.
    if state.wasExplicitlyTerminated {
      throw CancellationError()
    }
  }

  public func terminate() async throws {
    guard state.markExplicitlyTerminated() else {
      await terminationTask.value
      return
    }
    do {
      try await terminationStrategy.killProcessIdentifier(processIdentifier)
    } catch {
      state.clearExplicitTermination()
      throw error
    }
    await terminationTask.value
  }

  public var stdOut: (any ProcessFileOutput)? {
    attachment.stdOut
  }

  public var stdErr: (any ProcessFileOutput)? {
    attachment.stdErr
  }

  // MARK: - Factory

  public class func application(
    withSimulator simulator: Simulator,
    configuration: ApplicationLaunchConfiguration,
    attachment: FBProcessFileAttachment,
    launchFuture: FBFuture<NSNumber>
  ) async throws -> SimulatorLaunchedApplication {
    let processIdentifier = try await bridgeFBFuture(launchFuture).int32Value
    return SimulatorLaunchedApplication(
      simulator: simulator,
      configuration: configuration,
      attachment: attachment,
      processIdentifier: processIdentifier
    )
  }

  private init(
    simulator: Simulator,
    configuration: ApplicationLaunchConfiguration,
    attachment: FBProcessFileAttachment,
    processIdentifier: pid_t
  ) {
    let state = TerminationState()
    self.configuration = configuration
    self.attachment = attachment
    self.processIdentifier = processIdentifier
    self.state = state
    self.terminationStrategy = ProcessTerminationStrategy.strategy(
      withProcessFetcher: ProcessFetcher(),
      workQueue: simulator.workQueue,
      logger: simulator.logger)
    // Armed before the task so that a `terminate()` racing construction cannot signal the process
    // before anything is watching for its exit.
    Self.armExitSource(forProcessIdentifier: processIdentifier, state: state)
    let attachmentBox = AttachmentBox(attachment)
    self.terminationTask = Task {
      await state.waitForExit()
      // Detaching is best-effort; its outcome was never reported to a waiter.
      try? await bridgeFBFutureVoid(attachmentBox.attachment.detach())
    }
  }

  private class func armExitSource(forProcessIdentifier processIdentifier: pid_t, state: TerminationState) {
    let queue = DispatchQueue(label: "com.facebook.fbsimulatorcontrol.application_termination_notifier")
    let source = DispatchSource.makeProcessSource(
      identifier: processIdentifier,
      eventMask: .exit,
      queue: queue
    )
    source.setEventHandler {
      source.cancel()
      state.markExited()
    }
    source.resume()
  }

  public var description: String {
    "Application Operation \(configuration.description) | pid \(processIdentifier) | Exited \(state.hasExited)"
  }
}
