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
  private let startFuture: FBMutableFuture<NSNull>
  private let finishFuture: FBMutableFuture<NSNull>
  private let outputURL: URL

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
    self.startFuture = FBMutableFuture()
    self.finishFuture = FBMutableFuture()
    super.init()
  }

  // MARK: Public Methods

  public func start() async throws {
    try await bridgeFBFutureVoid(startWriting())
  }

  public func stop() async throws -> URL {
    try await bridgeFBFutureVoid(stopWriting())
    return outputURL
  }

  // MARK: Private Methods

  private var filePath: String {
    outputURL.path
  }

  private func startWriting() -> FBFuture<NSNull> {
    if FileManager.default.fileExists(atPath: filePath) {
      logger.log("File already exists at \(filePath), deleting")
      do {
        try FileManager.default.removeItem(atPath: filePath)
      } catch {
        return unsafeBitCast(
          FBControlCoreError.describe("Failed to remove existing device video at \(filePath)").caused(by: error).failFuture(),
          to: FBFuture<NSNull>.self
        )
      }
      logger.log("Removed video file at \(filePath)")
    }
    do {
      try FileManager.default.createDirectory(atPath: (filePath as NSString).deletingLastPathComponent, withIntermediateDirectories: true, attributes: nil)
    } catch {
      return unsafeBitCast(
        FBControlCoreError.describe("Failed to remove create auxillary directory for device at \(filePath)").caused(by: error).failFuture(),
        to: FBFuture<NSNull>.self
      )
    }
    session.startRunning()
    output.startRecording(to: outputURL, recordingDelegate: self)
    logger.log("Started Video Session for Device Video at file \(filePath)")
    return unsafeBitCast(startFuture, to: FBFuture<NSNull>.self)
  }

  private func stopWriting() -> FBFuture<NSNull> {
    output.stopRecording()
    session.stopRunning()
    return unsafeBitCast(finishFuture, to: FBFuture<NSNull>.self)
  }

  // MARK: AVCaptureFileOutputRecordingDelegate

  public func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
    logger.log("Did Start Recording at \(filePath)")
    startFuture.resolve(withResult: NSNull())
  }

  public func fileOutput(_ output: AVCaptureFileOutput, didPauseRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
    logger.log("Did Pause Recording at \(filePath)")
  }

  public func fileOutput(_ output: AVCaptureFileOutput, willFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
    logger.log("Will Finish Recording at \(filePath)")
  }

  public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
    logger.log("Did Finish Recording at \(filePath)")
    finishFuture.resolve(withResult: NSNull())
  }

  public func fileOutput(_ output: AVCaptureFileOutput, didResumeRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
    logger.log("Did Resume Recording at \(filePath)")
  }
}
