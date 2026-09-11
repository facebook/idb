/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// A target that can run tests. The noun lives here rather than on `FBiOSTarget` so that a target can
/// be given it from a module of its own, additively, without the module declaring the target's
/// `FBiOSTarget` conformance having to see XCTestBootstrap.
public protocol XCTestTarget: FBiOSTarget {

  associatedtype XCTest: XCTestCommands
  var xctest: XCTest { get }
}

/// A target whose tests XCTestBootstrap can drive. The `where` clause narrows the inherited `xctest`
/// noun to the extended surface — the shim, the `xctest` path and the test manager transport — rather
/// than adding a second noun, so `target.xctest` reaches both.
public protocol XCTestExtendedTarget: XCTestTarget where XCTest: XCTestExtendedCommands {}

/// A target that can additionally run logic tests, where the `xctest` binary is spawned on the target
/// itself rather than hosted by an application. Simulators and the local Mac qualify; devices do not.
public protocol LogicTestTarget: XCTestExtendedTarget {

  associatedtype ProcessSpawn: ProcessSpawnCommands
  var processSpawn: ProcessSpawn { get }
}
