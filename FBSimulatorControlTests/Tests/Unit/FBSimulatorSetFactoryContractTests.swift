/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorControl
import Foundation
import Testing

/// Pins the Objective-C contract of the `FBSimulatorSet` factory.
@Suite("FBSimulatorSet factory contract")
struct FBSimulatorSetFactoryContractTests {

  @Test("The factory exposes no error channel for framework loading")
  func factoryExposesNoErrorChannel() {
    // BUG: the factory routes framework-load failure to loadPrivateFrameworksOrAbort() — log,
    // NSAssert, abort() — instead of the NSError out-parameter an @objc factory could carry, so a
    // consumer that does not pre-load the private frameworks dies before it can present an error.
    // Flipped in the following commit, which makes the factory throwing.
    #expect(FBSimulatorSet.responds(to: NSSelectorFromString("setWithConfiguration:deviceSet:delegate:logger:reporter:")))
    #expect(!FBSimulatorSet.responds(to: NSSelectorFromString("setWithConfiguration:deviceSet:delegate:logger:reporter:error:")))
  }
}
