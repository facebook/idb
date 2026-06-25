/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public protocol LifecycleCommands: AnyObject {

  func resolveState(_ state: FBiOSTargetState) async throws

  func resolveLeavesState(_ state: FBiOSTargetState) async throws
}
