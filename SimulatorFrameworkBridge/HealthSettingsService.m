/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "HealthSettingsService.h"

#if __has_include(<SimulatorFrameworkBridgeSupport/SimulatorFrameworkBridgeSupport-Swift.h>)
 #import <SimulatorFrameworkBridgeSupport/SimulatorFrameworkBridgeSupport-Swift.h>
#else
 #import "SimulatorFrameworkBridgeSupport-Swift.h"
#endif

int handleHealthSettingsAction(NSString *action, NSString *bundleID, NSArray<NSString *> *typeIdentifiers)
{
  return (int)[HealthSettingsServiceStaticFuncs handleHealthSettingsAction:action ?: @"(null)" bundleID:bundleID typeIdentifiers:typeIdentifiers ?: @[]];
}
