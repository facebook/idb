/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

/// Declares `FBDeviceManager`'s conformance from Swift rather than from its `@interface`.
///
/// `FBiOSTargetSet` is a Swift protocol. Declaring the conformance here rather than in Objective-C
/// is what allows it to stop being `@objc` — the members satisfying it are already implemented on
/// the class and are declared in its header for this purpose. The subclasses inherit it.
extension FBDeviceManager: FBiOSTargetSet {}
