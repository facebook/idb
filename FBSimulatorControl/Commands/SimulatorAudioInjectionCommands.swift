/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import Darwin
import FBControlCore
import Foundation
internal import ShimulatorAudioInjectionCore
@_implementationOnly import ShimulatorProtocol
import SimulatorIPC

extension SimulatorAudioCommands {
  // MARK: - Microphone injection

  public static let injectionShimName = "libShimulator-iOS.dylib"

  private static let injectionPollInterval = Duration.milliseconds(50)

  /// Only a process launched after arming claims audio, so nothing may ever claim it.
  static let injectionClaimTimeout = Duration.seconds(10)

  /// A process that recorded earlier can claim audio and then never render it.
  private static let injectionPlaybackGrace = Duration.seconds(30)

  /// Pins a regular file and copies at most the payload limit plus one byte before decoding it.
  static func wav(
    of url: URL,
    read: (Int32, UnsafeMutableRawPointer, Int) throws -> Int = { Darwin.read($0, $1, $2) }
  ) throws -> (duration: Duration, data: Data)? {
    func unreadable(_ reason: String) -> SimulatorAudioError {
      .injectionFileUnreadable(path: url.path, reason: reason)
    }
    func readFailure() -> SimulatorAudioError {
      unreadable(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO).localizedDescription)
    }
    guard url.isFileURL else {
      throw unreadable("Audio input must be a local regular file.")
    }
    // Nonblocking at open prevents waiting for a FIFO writer before descriptor validation.
    // Follow symlinks, as before; validate the opened target, not an earlier pathname stat.
    let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
    guard descriptor >= 0 else {
      throw readFailure()
    }
    defer { close(descriptor) }
    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0 else {
      throw readFailure()
    }
    guard metadata.st_mode & S_IFMT == S_IFREG else {
      throw unreadable("Audio input must be a regular file.")
    }
    let maximum = ShimulatorAudioInjection.maximumPayloadBytes
    guard metadata.st_size <= off_t(maximum) else {
      throw SimulatorAudioError.injectionFileTooLarge(
        path: url.path, size: Int(clamping: metadata.st_size), maximum: maximum)
    }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while data.count <= maximum {
      let requested = min(buffer.count, maximum + 1 - data.count)
      let count = try buffer.withUnsafeMutableBytes { buffer in
        guard let address = buffer.baseAddress else {
          throw unreadable("Audio read buffer is unavailable.")
        }
        return try read(descriptor, address, requested)
      }
      if count < 0 {
        if errno == EINTR {
          continue
        }
        throw readFailure()
      }
      if count == 0 {
        break
      }
      data.append(contentsOf: buffer.prefix(count))
    }
    guard data.count <= maximum else {
      // A growing file's size is only an observation; the prefix proves at least maximum + 1.
      let observed = fstat(descriptor, &metadata) == 0 ? Int(clamping: metadata.st_size) : data.count
      throw SimulatorAudioError.injectionFileTooLarge(
        path: url.path, size: max(data.count, observed), maximum: maximum)
    }
    return WAVAudio(data: data).map { (.seconds(Double($0.samples.count) / $0.sampleRate), data) }
  }

  private var injectionSocketPath: String {
    ShimulatorWireProtocol.socketPath(capability: ShimulatorAudioInjection.capability, simulatorUDID: simulator.udid)
  }

  /// Prepares only the launched app to accept microphone playback, without changing guest launchd.
  ///
  /// A launch that cannot be prepared still goes ahead, unarmed; `inject` then names the reason.
  public func appLaunchEnvironment(_ environment: [String: String]) async -> [String: String] {
    guard [.iPhone, .iPad].contains(simulator.productFamily) else {
      return environment
    }
    return await Self.appLaunchEnvironment(
      environment,
      recordingIn: preparation,
      log: { simulator.logger.log($0) },
      prepare: { try await preparedAppLaunchEnvironment(environment) })
  }

  static func appLaunchEnvironment(
    _ environment: [String: String],
    recordingIn preparation: AudioInjectionPreparation,
    log: (String) -> Void,
    prepare: () async throws -> [String: String]
  ) async -> [String: String] {
    do {
      let prepared = try await prepare()
      preparation.record(failure: nil)
      return prepared
    } catch {
      let reason = error.localizedDescription
      log("Launching the app without microphone injection: \(reason)")
      preparation.record(failure: reason)
      return environment
    }
  }

  private var preparation: AudioInjectionPreparation {
    simulator.commandCache.resolve { AudioInjectionPreparation() }
  }

  private func preparedAppLaunchEnvironment(_ environment: [String: String]) async throws -> [String: String] {
    guard let shimPath = BundledResources.path(forItem: Self.injectionShimName) else {
      throw SimulatorAudioError.injectionShimMissing(item: Self.injectionShimName)
    }
    let directory = ShimulatorWireProtocol.socketDirectory()
    do {
      try IPCSocket.requirePrivateDirectory(directory, creating: true)
    } catch {
      throw SimulatorAudioError.injectionSocketUnavailable(path: directory, reason: String(describing: error))
    }
    let inherited =
      if environment[Self.insertLibrariesVariable] != nil {
        ""
      } else {
        try await launchctl("getenv", Self.insertLibrariesVariable)
      }
    return Self.appLaunchEnvironment(environment, shimPath: shimPath, inheritedLibraries: inherited)
  }

  static func appLaunchEnvironment(
    _ environment: [String: String], shimPath: String, inheritedLibraries: String
  ) -> [String: String] {
    let libraries = environment[Self.insertLibrariesVariable] ?? inheritedLibraries
    let others = libraries.split(separator: ":").map(String.init).filter {
      ($0 as NSString).lastPathComponent != Self.injectionShimName
    }
    var prepared = environment
    prepared[Self.insertLibrariesVariable] = (others + [shimPath]).joined(separator: ":")
    prepared[ShimulatorAudioInjection.armedEnvironmentVariable] =
      environment[ShimulatorAudioInjection.armedEnvironmentVariable] ?? "1"
    return prepared
  }

  private func requireInjectableProductFamily() throws {
    guard [.iPhone, .iPad].contains(simulator.productFamily) else {
      throw SimulatorAudioError.injectionUnsupportedPlatform(udid: simulator.udid)
    }
  }

  private static let insertLibrariesVariable = "DYLD_INSERT_LIBRARIES"

  /// Runs the runtime's own `launchctl`; `launchctl getenv` exits zero and prints nothing when unset.
  private func launchctl(_ arguments: String...) async throws -> String {
    let output = try await simulator.runtimeTools.launchConsumingOutput(
      launchPath: try SimulatorLaunchCtlCommands.launchCtlLaunchPath(for: simulator), arguments: arguments)
    guard output.exitCode == 0, let stdout = String(data: output.stdout, encoding: .utf8) else {
      throw SimulatorAudioError.injectionArmingFailed(
        udid: simulator.udid,
        stderr: "launchctl \(arguments.joined(separator: " ")) exited \(output.exitCode): \(String(decoding: output.stderr, as: UTF8.self))")
    }
    return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Plays WAV audio into apps prepared by an idb launch, returning when playback finishes.
  public func inject(from audioFileURL: URL) async throws {
    try requireInjectableProductFamily()
    guard let audio = try Self.wav(of: audioFileURL) else {
      throw SimulatorAudioError.injectionUnreadable(path: audioFileURL.path)
    }
    guard BundledResources.path(forItem: Self.injectionShimName) != nil else {
      throw SimulatorAudioError.injectionShimMissing(item: Self.injectionShimName)
    }
    if audio.duration == .zero {
      return
    }
    let socketPath = injectionSocketPath
    let audioPath = (socketPath as NSString).deletingPathExtension + ".wav"
    let bound: ShimulatorServer?
    do {
      bound = try ShimulatorServer(path: socketPath, parameters: AudioInjectionParameters(path: audioPath))
    } catch {
      throw SimulatorAudioError.injectionSocketUnavailable(path: socketPath, reason: String(describing: error))
    }
    guard let server = bound else {
      throw SimulatorAudioError.injectionAlreadyRunning(udid: simulator.udid)
    }
    defer { try? FileManager.default.removeItem(atPath: audioPath) }
    do {
      try audio.data.write(to: URL(fileURLWithPath: audioPath), options: .atomic)
    } catch {
      throw SimulatorAudioError.injectionSocketUnavailable(path: audioPath, reason: error.localizedDescription)
    }

    var claimed = false
    var departed: [InjectionReport] = []
    var confirmingCompletion = false
    let claimDeadline = ContinuousClock.now + Self.injectionClaimTimeout
    let playbackDeadline =
      ContinuousClock.now + Self.injectionClaimTimeout + audio.duration
      + Self.injectionPlaybackGrace
    while true {
      let polled = server.poll()
      departed += polled.filter { !$0.connected }.compactMap(Self.report)
      let reports = departed + polled.filter(\.connected).compactMap(Self.report)
      if reports.contains(where: { $0.state == .finished }) {
        server.stopAdmitting()
      }
      let progress = Self.injectionProgress(
        reports: reports,
        claimed: claimed,
        confirmingCompletion: confirmingCompletion,
        claimExpired: ContinuousClock.now > claimDeadline,
        playbackExpired: ContinuousClock.now > playbackDeadline)
      claimed = progress.claimed
      confirmingCompletion = progress.confirmingCompletion
      switch progress.decision {
      case .wait:
        try await Task.sleep(for: Self.injectionPollInterval)
      case .completed:
        return
      case let .failed(process, message):
        throw SimulatorAudioError.injectionFailedInGuest(
          udid: simulator.udid,
          process: process,
          reason: message)
      case .unclaimed:
        throw SimulatorAudioError.injectionUnclaimed(
          udid: simulator.udid, preparationFailure: preparation.lastFailure)
      case .didNotFinish:
        throw SimulatorAudioError.injectionDidNotFinish(udid: simulator.udid)
      }
    }
  }

  private static func report(_ responder: ShimulatorResponder) -> InjectionReport? {
    if let error = responder.error {
      return InjectionReport(state: .failed, process: "a process in the simulator", message: error)
    }
    guard let response = responder.response else {
      return nil
    }
    let state: InjectionState =
      switch response.state {
      case .accepted: .playing
      case .completed: .finished
      case .failed: .failed
      }
    return InjectionReport(
      state: state,
      process: response.processName.isEmpty ? "pid \(response.processIdentifier)" : response.processName,
      message: response.message,
      processIsAlive: responder.connected)
  }

  struct InjectionProgress: Equatable {
    enum Decision: Equatable {
      case wait
      case completed
      case failed(process: String, message: String?)
      case unclaimed
      case didNotFinish
    }

    let decision: Decision
    let claimed: Bool
    let confirmingCompletion: Bool
  }

  static func injectionProgress(
    reports: [InjectionReport],
    claimed: Bool,
    confirmingCompletion: Bool,
    claimExpired: Bool,
    playbackExpired: Bool
  ) -> InjectionProgress {
    let states = reports.map(\.state)
    let isPlaying = reports.contains { $0.state == .playing && $0.processIsAlive }
    let isFinished = states.contains(.finished)
    let updatedClaimed = claimed || isPlaying || isFinished

    if !isPlaying, !isFinished,
      let failure = reports.first(where: { $0.state == .failed })
    {
      return InjectionProgress(
        decision: claimed || claimExpired ? .failed(process: failure.process, message: failure.message) : .wait,
        claimed: updatedClaimed,
        confirmingCompletion: false)
    }
    if isFinished, !isPlaying {
      return InjectionProgress(
        decision: confirmingCompletion ? .completed : .wait,
        claimed: updatedClaimed,
        confirmingCompletion: true)
    }
    if !updatedClaimed, claimExpired {
      return InjectionProgress(
        decision: .unclaimed,
        claimed: false,
        confirmingCompletion: false)
    }
    if playbackExpired {
      return InjectionProgress(
        decision: .didNotFinish,
        claimed: updatedClaimed,
        confirmingCompletion: false)
    }
    return InjectionProgress(
      decision: .wait,
      claimed: updatedClaimed,
      confirmingCompletion: false)
  }

  struct InjectionReport: Equatable {
    let state: InjectionState
    let process: String
    let message: String?
    var processIsAlive = true
  }

  enum InjectionState: String {
    case playing
    case finished
    case failed
  }
}

/// Why the simulator's last idb app launch could not be prepared for microphone injection.
final class AudioInjectionPreparation: @unchecked Sendable {
  private let lock = NSLock()
  private var failure: String?

  /// Nil once a launch has been prepared, until one fails again.
  var lastFailure: String? {
    lock.withLock { failure }
  }

  func record(failure: String?) {
    lock.withLock { self.failure = failure }
  }
}
