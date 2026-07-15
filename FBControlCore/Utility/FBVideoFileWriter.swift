/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
import Foundation

@objc(FBVideoFileWriter)
public class FBVideoFileWriter: NSObject, AVCaptureFileOutputRecordingDelegate {

  // MARK: Properties

  private let session: AVCaptureSession
  private let output: AVCaptureMovieFileOutput
  private let logger: any FBControlCoreLogger
  private let outputURL: URL
  private let lifecycleLock = NSLock()
  private var hasStarted = false
  private var hasFinished = false
  private var startAwaiters: [CheckedContinuation<Void, Error>] = []
  private var finishAwaiters: [CheckedContinuation<Void, Error>] = []

  // MARK: Initializers

  @objc(writerWithSession:filePath:logger:error:)
  public class func writer(withSession session: AVCaptureSession, filePath: String, logger: any FBControlCoreLogger) throws -> Self {
    let output = AVCaptureMovieFileOutput()
    if !session.canAddOutput(output) {
      throw FBControlCoreError.describe("Cannot add File Output to session for \(filePath)").build()
    }
    session.addOutput(output)
    return self.init(session: session, output: output, filePath: filePath, logger: logger)
  }

  required init(session: AVCaptureSession, output: AVCaptureMovieFileOutput, filePath: String, logger: any FBControlCoreLogger) {
    self.session = session
    self.output = output
    self.outputURL = URL(fileURLWithPath: filePath)
    self.logger = logger
    super.init()
  }

  // MARK: Public Methods

  public func start() async throws {
    try await startWriting()
  }

  public func stop() async throws -> URL {
    try await stopWriting()
    return outputURL
  }

  // MARK: Private Methods

  private var filePath: String {
    outputURL.path
  }

  private func startWriting() async throws {
    if FileManager.default.fileExists(atPath: filePath) {
      logger.log("File already exists at \(filePath), deleting")
      do {
        try FileManager.default.removeItem(atPath: filePath)
      } catch {
        throw FBControlCoreError.describe("Failed to remove existing device video at \(filePath)").caused(by: error).build()
      }
      logger.log("Removed video file at \(filePath)")
    }
    do {
      try FileManager.default.createDirectory(atPath: (filePath as NSString).deletingLastPathComponent, withIntermediateDirectories: true, attributes: nil)
    } catch {
      throw FBControlCoreError.describe("Failed to remove create auxillary directory for device at \(filePath)").caused(by: error).build()
    }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      registerStartAwaiter(continuation)
      session.startRunning()
      output.startRecording(to: outputURL, recordingDelegate: self)
      logger.log("Started Video Session for Device Video at file \(filePath)")
    }
  }

  private func stopWriting() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      registerFinishAwaiter(continuation)
      output.stopRecording()
      session.stopRunning()
    }
  }

  private func registerStartAwaiter(_ continuation: CheckedContinuation<Void, Error>) {
    lifecycleLock.lock()
    if hasStarted {
      lifecycleLock.unlock()
      continuation.resume()
    } else {
      startAwaiters.append(continuation)
      lifecycleLock.unlock()
    }
  }

  private func registerFinishAwaiter(_ continuation: CheckedContinuation<Void, Error>) {
    lifecycleLock.lock()
    if hasFinished {
      lifecycleLock.unlock()
      continuation.resume()
    } else {
      finishAwaiters.append(continuation)
      lifecycleLock.unlock()
    }
  }

  private func markStarted() -> [CheckedContinuation<Void, Error>]? {
    lifecycleLock.lock()
    defer { lifecycleLock.unlock() }
    if hasStarted {
      return nil
    }
    hasStarted = true
    let awaiters = startAwaiters
    startAwaiters = []
    return awaiters
  }

  private func markFinished() -> [CheckedContinuation<Void, Error>]? {
    lifecycleLock.lock()
    defer { lifecycleLock.unlock() }
    if hasFinished {
      return nil
    }
    hasFinished = true
    let awaiters = finishAwaiters
    finishAwaiters = []
    return awaiters
  }

  // MARK: AVCaptureFileOutputRecordingDelegate

  public func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
    logger.log("Did Start Recording at \(filePath)")
    markStarted()?.forEach { $0.resume() }
  }

  public func fileOutput(_ output: AVCaptureFileOutput, didPauseRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
    logger.log("Did Pause Recording at \(filePath)")
  }

  public func fileOutput(_ output: AVCaptureFileOutput, willFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
    logger.log("Will Finish Recording at \(filePath)")
  }

  public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
    logger.log("Did Finish Recording at \(filePath)")
    markFinished()?.forEach { $0.resume() }
  }

  public func fileOutput(_ output: AVCaptureFileOutput, didResumeRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
    logger.log("Did Resume Recording at \(filePath)")
  }
}
