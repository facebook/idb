/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

// MARK: - FBiOSTargetSetDelegate Protocol

/// Delegate that informs of updates regarding the set of iOS Targets.
public protocol FBiOSTargetSetDelegate: AnyObject {

  /// Called every time an iOS Target is added to the set.
  func targetAdded(_ targetInfo: any FBiOSTargetInfo, in targetSet: any FBiOSTargetSet)

  /// Called every time an iOS Target is removed from the set.
  func targetRemoved(_ targetInfo: any FBiOSTargetInfo, in targetSet: any FBiOSTargetSet)

  /// Called every time the target info is changed.
  func targetUpdated(_ targetInfo: any FBiOSTargetInfo, in targetSet: any FBiOSTargetSet)
}

// MARK: - FBiOSTargetSet Protocol

/// Common properties of iOS Target Sets, shared by Simulator & Device Sets.
public protocol FBiOSTargetSet: AnyObject {

  /// Conformers must hold this weakly; a protocol requirement cannot say so.
  var delegate: (any FBiOSTargetSetDelegate)? { get set }

  /// Obtains all current targets infos within a set.
  var allTargetInfos: [any FBiOSTargetInfo] { get }

  /// Fetches a Target by a UDID.
  func target(withUDID udid: String) -> (any FBiOSTargetInfo)?
}
