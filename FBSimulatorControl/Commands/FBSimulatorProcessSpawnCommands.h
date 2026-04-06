/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

// FBSimulatorProcessSpawnCommands class is now implemented in Swift.
// Note: We intentionally do NOT import the Swift header here to avoid
// circular dependencies during PCM compilation. The Swift class is
// accessible through the umbrella header FBSimulatorControl.h instead.
