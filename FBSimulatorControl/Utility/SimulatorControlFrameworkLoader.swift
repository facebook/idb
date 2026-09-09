/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

/// The private frameworks FBSimulatorControl loads on demand, grouped by what needs them.
public enum FBSimulatorControlFrameworkLoader {

  private static let name = "FBSimulatorControl"

  /// The frameworks needed for most operations.
  public static let essentialFrameworks = FBControlCoreFrameworkLoader(
    name: name,
    frameworks: [FBWeakFramework.coreSimulator])

  /// The frameworks needed for accessibility operations.
  public static let accessibilityFrameworks = FBControlCoreFrameworkLoader(
    name: name,
    frameworks: [FBWeakFramework.accessibilityPlatformTranslation])

  /// The frameworks needed for operations involving the HID and framebuffer.
  public static let xcodeFrameworks = FBControlCoreFrameworkLoader(
    name: name,
    frameworks: [FBWeakFramework.simulatorKit])
}
