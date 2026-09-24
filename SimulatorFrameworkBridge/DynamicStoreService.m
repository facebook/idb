/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "DynamicStoreService.h"

#if __has_include(<SimulatorFrameworkBridgeSupport/SimulatorFrameworkBridgeSupport-Swift.h>)
 #import <SimulatorFrameworkBridgeSupport/SimulatorFrameworkBridgeSupport-Swift.h>
#else
 #import "SimulatorFrameworkBridgeSupport-Swift.h"
#endif

NSString *dynamicStoreKeyForName(NSString *name)
{
  return [FBDynamicStoreService keyForName:name];
}

int handleDynamicStoreAction(NSString *action, NSArray<NSString *> *arguments)
{
  return (int)[FBDynamicStoreService handleDynamicStoreAction:action arguments:arguments];
}
