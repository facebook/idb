/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// The private frameworks XCTestBootstrap loads on demand.
public enum XCTestBootstrapFrameworkLoader {

  public static let allDependentFrameworks = FrameworkLoader(
    name: "XCTestBootstrap",
    frameworks: [
      WeakFramework.dtxConnectionServices,
      WeakFramework.xcTest,
    ]
  )
}
