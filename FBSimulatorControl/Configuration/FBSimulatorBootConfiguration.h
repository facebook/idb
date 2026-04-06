/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 An Option Set for Direct Launching.
 */
typedef NS_OPTIONS(NSUInteger, FBSimulatorBootOptions) {
  FBSimulatorBootOptionsTieToProcessLifecycle = 1 << 1, /** When set, will tie the Simulator's lifecycle to that of the launching process. This means that when the process that performs the boot dies, the Simulator is shutdown automatically. */
  FBSimulatorBootOptionsVerifyUsable = 1 << 3, /** A Simulator can be report that it is 'Booted' very quickly but is not in Usable. Setting this option requires that the Simulator is 'Usable' before the boot API completes */
};

// C type definitions required by the generated Swift header.
#import <FBSimulatorControl/FBSimulatorIndigoHID.h>

// FBSimulatorBootConfiguration class is now implemented in Swift.
#if __has_include(<FBSimulatorControl/FBSimulatorControl-Swift.h>)
 #import <FBSimulatorControl/FBSimulatorControl-Swift.h>
#endif
