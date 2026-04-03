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
  private let filePath: String

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
    self.filePath = filePath
    self.logger = logger
    self.startFuture = FBMutableFuture()
    self.finishFuture = FBMutableFuture()
    super.init()
  }

  // MARK: Public Methods

  @objc public func startRecording() -> FBFuture<NSNull> {
    if FileManager.default.fileExists(atPath: filePath) {
      logger.log("File already exists at \(filePath), deleting")
      do {
        try FileManager.default.removeItem(atPath: filePath)
      } catch {
        return FBControlCoreError.describe("Failed to remove existing device video at \(filePath)").caused(by: error).failFuture() as! FBFuture<NSNull>
      }
      logger.log("Removed video file at \(filePath)")
    }
    do {
      try FileManager.default.createDirectory(atPath: (filePath as NSString).deletingLastPathComponent, withIntermediateDirectories: true, attributes: nil)
    } catch {
      return FBControlCoreError.describe("Failed to remove create auxillary directory for device at \(filePath)").caused(by: error).failFuture() as! FBFuture<NSNull>
    }
    let file = URL(fileURLWithPath: filePath)
    session.startRunning()
    output.startRecording(to: file, recordingDelegate: self)
    logger.log("Started Video Session for Device Video at file \(filePath)")
    return unsafeBitCast(startFuture, to: FBFuture<NSNull>.self)
  }

  @objc public func stopRecording() -> FBFuture<NSNull> {
    output.stopRecording()
    session.stopRunning()
    return unsafeBitCast(finishFuture, to: FBFuture<NSNull>.self)
  }

  @objc public func completed() -> FBFuture<NSNull> {
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

  public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
    logger.log("Did Finish Recording at \(filePath)")
    finishFuture.resolve(withResult: NSNull())
  }

  public func fileOutput(_ output: AVCaptureFileOutput, didResumeRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
    logger.log("Did Resume Recording at \(filePath)")
  }
}
