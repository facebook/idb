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

  @Test("The factory carries an error channel for framework loading")
  func factoryCarriesAnErrorChannel() {
    #expect(!FBSimulatorSet.responds(to: NSSelectorFromString("setWithConfiguration:deviceSet:delegate:logger:")))
    #expect(FBSimulatorSet.responds(to: NSSelectorFromString("setWithConfiguration:deviceSet:delegate:logger:error:")))
  }
}
