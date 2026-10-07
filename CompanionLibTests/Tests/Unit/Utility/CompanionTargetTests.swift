/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
@preconcurrency import FBControlCore
import FBVideoCore
import Foundation
import Testing
import XCTestBootstrap

@Suite("CompanionTarget")
struct CompanionTargetTests {

  private let mac = MacDevice(logger: FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: false, withDebugLogging: false))

  @Test func theMacResolvesToACompanionTarget() {
    #expect(TargetProvider.companionTarget(mac) != nil)
  }

  @Test func theMacRefusesToRecordWithItsUnsupportedCommandError() async {
    let target: CompanionTarget = mac
    await #expect {
      _ = try await target.videoRecording.start(toFile: "/dev/null")
    } throws: { error in
      error.localizedDescription == "start is not supported on the mac target"
    }
  }

  @Test func theMacRefusesToStreamWithItsUnsupportedCommandError() async {
    let target: CompanionTarget = mac
    let configuration = VideoStreamConfiguration(
      format: .compressedVideo(withCodec: .h264, transport: .annexB), framesPerSecond: nil, rateControl: nil, scaleFactor: nil,
      keyFrameRate: nil)
    await #expect {
      _ = try await target.videoStream.create(configuration: configuration, to: FBNullDataConsumer())
    } throws: { error in
      error.localizedDescription == "create is not supported on the mac target"
    }
  }
}
