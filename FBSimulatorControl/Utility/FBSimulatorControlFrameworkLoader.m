/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorControlFrameworkLoader.h"

#import <FBControlCore/FBControlCore.h>

@implementation FBSimulatorControlFrameworkLoader

#pragma mark Initializers

+ (FBSimulatorControlFrameworkLoader *)essentialFrameworks
{
  static dispatch_once_t onceToken;
  static FBSimulatorControlFrameworkLoader *loader;
  dispatch_once(&onceToken, ^{
    loader = [FBSimulatorControlFrameworkLoader loaderWithName:@"FBSimulatorControl"
                                                    frameworks:@[
                FBWeakFramework.CoreSimulator,
              ]];
  });
  return loader;
}

+ (FBSimulatorControlFrameworkLoader *)accessibilityFrameworks
{
  static dispatch_once_t onceToken;
  static FBSimulatorControlFrameworkLoader *loader;
  dispatch_once(&onceToken, ^{
    loader = [FBSimulatorControlFrameworkLoader loaderWithName:@"FBSimulatorControl"
                                                    frameworks:@[
                FBWeakFramework.AccessibilityPlatformTranslation,
              ]];
  });
  return loader;
}

+ (FBSimulatorControlFrameworkLoader *)xcodeFrameworks
{
  static dispatch_once_t onceToken;
  static FBSimulatorControlFrameworkLoader *loader;
  dispatch_once(&onceToken, ^{
    loader = [FBSimulatorControlFrameworkLoader loaderWithName:@"FBSimulatorControl"
                                                    frameworks:@[
                FBWeakFramework.SimulatorKit,
              ]];
  });
  return loader;
}

@end
