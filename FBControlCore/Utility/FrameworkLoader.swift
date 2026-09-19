/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Something that can load the private frameworks a caller depends on.
public protocol FrameworkLoading: Sendable {

  /// Loads the frameworks. A nil logger loads silently.
  func loadPrivateFrameworks(_ logger: (any ControlCoreLogger)?) throws
}

/// Loads a named set of frameworks, at most once per instance.
///
/// `@unchecked Sendable`: the loaded latch is the only mutable state, and `lock` guards it.
// patternlint-disable-next-line unchecked-sendable
public final class FrameworkLoader: FrameworkLoading, @unchecked Sendable {

  /// The named set of frameworks.
  public let frameworkName: String

  /// The frameworks to load.
  public let frameworks: [WeakFramework]

  private let lock = NSLock()
  private var loaded = false

  /// Whether the frameworks have been loaded.
  public var hasLoadedFrameworks: Bool {
    lock.withLock { loaded }
  }

  public init(name frameworkName: String, frameworks: [WeakFramework]) {
    self.frameworkName = frameworkName
    self.frameworks = frameworks
  }

  public func loadPrivateFrameworks(_ logger: (any ControlCoreLogger)?) throws {
    try lock.withLock {
      if loaded {
        return
      }
      for framework in frameworks {
        try framework.load(with: logger)
      }
      let names = frameworks.map { ($0.name as NSString).lastPathComponent }
      logger?.debug().log("Loaded All Private Frameworks \(CollectionInformation.oneLineDescription(from: names))")
      loaded = true
    }
  }
}
