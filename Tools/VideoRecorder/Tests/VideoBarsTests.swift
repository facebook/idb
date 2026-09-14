/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import SimulatorVideo
import Testing

@Suite struct VideoBarsTests {
  @Test func emptyBarArgument() async {
    await #expect(processExitsWith: .success) {
      let logger = FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: true, withDebugLogging: false)
      let result = VideoBars(bars: ["", "top:24"], barStats: []).resolve(deprecatedBottomStatusBar: false, deprecatedTopStatusBar: false, logger: logger)
      #expect(result.parsedBars.count == 1)
      #expect(result.edgeInsets.top == 24)
    }
  }
}
