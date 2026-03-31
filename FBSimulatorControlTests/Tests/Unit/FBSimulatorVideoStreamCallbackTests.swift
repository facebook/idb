// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import CoreMedia
import FBControlCore
import VideoToolbox
import XCTest

@testable import FBSimulatorControl

final class FBSimulatorVideoStreamCallbackTests: XCTestCase {

  // MARK: - Helpers

  private func makeReadySampleBuffer() -> CMSampleBuffer {
    CreateH264SampleBuffer().takeRetainedValue()
  }

  private func makeNotReadySampleBuffer() -> CMSampleBuffer {
    CreateNotReadySampleBuffer().takeRetainedValue()
  }

  // MARK: - Tests

  func testWarmupFramesSuppressed() {
    let logger = FBCapturingLogger()
    let pusher = CreateTestVideoStreamPusher(logger)

    // Send 5 not-ready buffers (simulates warmup)
    for _ in 0..<5 {
      let notReady = makeNotReadySampleBuffer()
      pusher.handleCompressedSampleBuffer(notReady, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())
    }

    // No per-frame messages during warmup
    for msg in logger.messages {
      XCTAssertFalse((msg as! String).contains("Sample Buffer is not ready"), "Should not log per-frame not-ready messages during warmup")
    }

    // Now send a ready buffer to complete warmup
    let ready = makeReadySampleBuffer()
    pusher.handleCompressedSampleBuffer(ready, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())

    // Should have a single warmup message
    var warmupMessageCount: UInt = 0
    for msg in logger.messages {
      if (msg as! String).contains("Encoder warmed up after 5 skipped frames") {
        warmupMessageCount += 1
      }
    }
    XCTAssertEqual(warmupMessageCount, 1, "Should log exactly one warmup completion message")
    XCTAssertTrue(pusher.warmupComplete)
  }

  func testStarvationDetectedDuringWarmup() {
    let logger = FBCapturingLogger()
    let pusher = CreateTestVideoStreamPusher(logger)

    // Send 20 not-ready buffers without any success
    for _ in 0..<20 {
      let notReady = makeNotReadySampleBuffer()
      pusher.handleCompressedSampleBuffer(notReady, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())
    }

    var foundStarvationWarning = false
    for msg in logger.messages {
      if (msg as! String).contains("has not produced a frame after 20 attempts") {
        foundStarvationWarning = true
      }
    }
    XCTAssertTrue(foundStarvationWarning, "Should warn about possible starvation after 20 warmup frames")
    XCTAssertTrue(pusher.starvationWarningLogged)
  }

  func testPostWarmupStarvation() {
    let logger = FBCapturingLogger()
    let pusher = CreateTestVideoStreamPusher(logger)

    // First, complete warmup with a ready buffer
    let ready = makeReadySampleBuffer()
    pusher.handleCompressedSampleBuffer(ready, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())
    XCTAssertTrue(pusher.warmupComplete)

    // Now send 10 not-ready buffers post-warmup
    for _ in 0..<10 {
      let notReady = makeNotReadySampleBuffer()
      pusher.handleCompressedSampleBuffer(notReady, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())
    }

    var foundStarvationWarning = false
    for msg in logger.messages {
      if (msg as! String).contains("Encoder starvation: 10 consecutive frames not ready after warmup") {
        foundStarvationWarning = true
      }
    }
    XCTAssertTrue(foundStarvationWarning, "Should warn about post-warmup starvation after 10 consecutive failures")
    XCTAssertTrue(pusher.starvationWarningLogged)
  }

  func testEncodeErrorLogged() {
    let logger = FBCapturingLogger()
    let pusher = CreateTestVideoStreamPusher(logger)

    HandleCompressedSampleBufferNullable(pusher, nil, -12345, VTEncodeInfoFlags())

    var foundError = false
    for msg in logger.messages {
      if (msg as! String).contains("VideoToolbox encode error: OSStatus -12345") {
        foundError = true
      }
    }
    XCTAssertTrue(foundError, "Should log VideoToolbox encode error with status code")
    XCTAssertEqual(pusher.stats.callbackCount, 1)
  }

  func testFrameDroppedCountedAsFailure() {
    let logger = FBCapturingLogger()
    let pusher = CreateTestVideoStreamPusher(logger)

    HandleCompressedSampleBufferNullable(pusher, nil, noErr, .frameDropped)

    // Dropped frame should increment failure counter, not produce a per-frame log
    XCTAssertEqual(pusher.consecutiveNotReadyFrameCount, 1)
    XCTAssertEqual(pusher.stats.callbackCount, 1)
    XCTAssertEqual(UInt(logger.messages.count), 1, "Should only log the first-callback message, not per-frame drop messages")
  }

  func testDroppedFramesTriggersStarvationWarning() {
    let logger = FBCapturingLogger()
    let pusher = CreateTestVideoStreamPusher(logger)

    // Send 20 dropped frames — should trigger starvation warning
    for _ in 0..<20 {
      HandleCompressedSampleBufferNullable(pusher, nil, noErr, .frameDropped)
    }

    var foundStarvationWarning = false
    for msg in logger.messages {
      if (msg as! String).contains("has not produced a frame after 20 attempts") {
        foundStarvationWarning = true
      }
    }
    XCTAssertTrue(foundStarvationWarning, "20 consecutive dropped frames should trigger starvation warning")
    XCTAssertEqual(UInt(logger.messages.count), 2, "Should produce the first-callback message and one starvation warning")
  }

  func testNoWarmupMessageWhenFirstFrameSucceeds() {
    let logger = FBCapturingLogger()
    let pusher = CreateTestVideoStreamPusher(logger)

    // Send a ready buffer immediately
    let ready = makeReadySampleBuffer()
    pusher.handleCompressedSampleBuffer(ready, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())

    XCTAssertTrue(pusher.warmupComplete)

    // No warmup message should be logged
    for msg in logger.messages {
      XCTAssertFalse((msg as! String).contains("Encoder warmed up"), "Should not log warmup message when first frame succeeds immediately")
    }
  }

  func testPeriodicStatsNotLoggedBeforeInterval() {
    let logger = FBCapturingLogger()
    let pusher = CreateTestVideoStreamPusher(logger)

    // Send a few successful frames — stats interval hasn't elapsed
    for _ in 0..<3 {
      let ready = makeReadySampleBuffer()
      pusher.handleCompressedSampleBuffer(ready, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())
    }

    for msg in logger.messages {
      XCTAssertFalse((msg as! String).contains("Video stats"), "Should not log stats before interval elapses")
    }
  }

  func testPeriodicStatsLoggedAfterInterval() {
    let logger = FBCapturingLogger()
    let pusher = CreateTestVideoStreamPusher(logger)

    // Send one frame to initialize timing
    var ready = makeReadySampleBuffer()
    pusher.handleCompressedSampleBuffer(ready, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())

    // Backdate statsTimer by 6 seconds to trigger stats on next frame
    var timer = pusher.statsTimer
    timer.lastLogTime = CFAbsoluteTimeGetCurrent() - 6.0
    pusher.statsTimer = timer

    ready = makeReadySampleBuffer()
    pusher.handleCompressedSampleBuffer(ready, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())

    var foundStats = false
    for msg in logger.messages {
      if (msg as! String).contains("Video stats") {
        foundStats = true
      }
    }
    XCTAssertTrue(foundStats, "Should log stats after interval elapses")
  }

  func testPeriodicStatsCountersAccurate() {
    let logger = FBCapturingLogger()
    let pusher = CreateTestVideoStreamPusher(logger)

    // 3 successful writes
    for _ in 0..<3 {
      let ready = makeReadySampleBuffer()
      pusher.handleCompressedSampleBuffer(ready, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())
    }

    // 2 dropped frames
    for _ in 0..<2 {
      HandleCompressedSampleBufferNullable(pusher, nil, noErr, .frameDropped)
    }

    // 1 encode error
    HandleCompressedSampleBufferNullable(pusher, nil, -12345, VTEncodeInfoFlags())

    // Verify counters
    XCTAssertEqual(pusher.stats.writeCount, 3)
    XCTAssertEqual(pusher.stats.dropCount, 2)
    XCTAssertEqual(pusher.stats.encodeErrorCount, 1)
    XCTAssertEqual(pusher.stats.callbackCount, 6)

    // Backdate to trigger stats log
    var timer = pusher.statsTimer
    timer.lastLogTime = CFAbsoluteTimeGetCurrent() - 6.0
    pusher.statsTimer = timer

    let ready = makeReadySampleBuffer()
    pusher.handleCompressedSampleBuffer(ready, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())

    var foundStats = false
    for msg in logger.messages {
      let s = msg as! String
      if s.contains("Video stats")
        && s.contains("4 written")
        && s.contains("2 dropped")
        && s.contains("1 encode errors")
      {
        foundStats = true
      }
    }
    XCTAssertTrue(foundStats, "Stats message should contain accurate counters")
  }

  func testPeriodicStatsDuringWarmup() {
    let logger = FBCapturingLogger()
    let pusher = CreateTestVideoStreamPusher(logger)

    // Send 10 not-ready buffers (write failures during warmup)
    for _ in 0..<10 {
      let notReady = makeNotReadySampleBuffer()
      pusher.handleCompressedSampleBuffer(notReady, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())
    }

    // Backdate to trigger stats log
    var timer = pusher.statsTimer
    timer.lastLogTime = CFAbsoluteTimeGetCurrent() - 6.0
    pusher.statsTimer = timer

    // Send one more not-ready buffer to trigger the stats log
    let notReady = makeNotReadySampleBuffer()
    pusher.handleCompressedSampleBuffer(notReady, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())

    var foundStats = false
    for msg in logger.messages {
      let s = msg as! String
      if s.contains("Video stats")
        && s.contains("0 written")
        && s.contains("11 write failures")
      {
        foundStats = true
      }
    }
    XCTAssertTrue(foundStats, "Stats during warmup should show 0 written and write failures")
  }
}
