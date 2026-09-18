/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A base framework loader, that will ensure that the current user can load frameworks.
open class FBControlCoreFrameworkLoader: NSObject {

  /// The named set of frameworks.
  public let frameworkName: String

  /// The frameworks to load.
  public let frameworks: [WeakFramework]

  /// Whether the frameworks have been loaded.
  public private(set) var hasLoadedFrameworks = false

  public init(name frameworkName: String, frameworks: [WeakFramework]) {
    self.frameworkName = frameworkName
    self.frameworks = frameworks
    super.init()
  }

  /// Loads the frameworks, at most once per instance.
  /// A nil logger loads silently.
  open func loadPrivateFrameworks(_ logger: (any ControlCoreLogger)?) throws {
    if hasLoadedFrameworks {
      return
    }
    for framework in frameworks {
      try framework.load(with: logger)
    }
    let names = frameworks.map { ($0.name as NSString).lastPathComponent }
    logger?.debug().log("Loaded All Private Frameworks \(CollectionInformation.oneLineDescription(from: names))")
    hasLoadedFrameworks = true
  }
}
