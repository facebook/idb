/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/SimServiceContext.h>

@interface SimServiceContext (Removed)

/**
 Removed in Xcode 27 (CoreSimulator 1155.4). Connection-type configuration, the
 per-path profile loaders, and the direct connect/init entry points are gone;
 idb/FBSimulatorControl uses +sharedServiceContextForDeveloperDir:error: and the
 surviving deviceSet / supportedRuntimes / supportedDeviceTypes accessors. Not
 called by idb/FBSimulatorControl.
 */
+ (void)setSharedContextConnectionType:(long long)arg1;
- (void)supportedRuntimesAddProfilesAtPath:(id)arg1;
- (void)supportedDeviceTypesAddProfilesAtPath:(id)arg1;
- (void)connect;
- (id)initWithDeveloperDir:(id)arg1 connectionType:(long long)arg2;

@end
