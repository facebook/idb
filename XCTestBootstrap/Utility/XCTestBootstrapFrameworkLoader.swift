/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

@objc public final class XCTestBootstrapFrameworkLoader: FBControlCoreFrameworkLoader {

  @objc public static nonisolated(unsafe) let allDependentFrameworks: XCTestBootstrapFrameworkLoader = {
    return XCTestBootstrapFrameworkLoader(
      name: "XCTestBootstrap",
      frameworks: [
        FBWeakFramework.dtxConnectionServices,
        FBWeakFramework.xcTest,
      ]
    )
  }()
}
