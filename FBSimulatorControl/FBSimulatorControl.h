/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Re-exported for consumers of this umbrella; it used to arrive transitively via the framework
// loader header, which is now Swift.
#import <FBControlCore/FBControlCore.h>

#if __has_include(<FBSimulatorControl/FBSimulatorControl-Swift.h>)
 #import <FBSimulatorControl/FBSimulatorControl-Swift.h>
#endif
