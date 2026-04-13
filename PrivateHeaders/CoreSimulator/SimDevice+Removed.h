/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/SimDevice.h>

/**
 Methods that have been removed or had their signatures changed in newer
 CoreSimulator versions. Kept here for reference and backward compatibility
 with older Xcode versions if needed.
 */
@interface SimDevice (Removed)

/**
 Removed in Xcode 8 Betas. Replaced by lookup:error: which returns a mach_port_t.
 */
- (id)portForServiceNamed:(id)arg1 error:(NSError **)arg2;

/**
 Old 6-arg factory. Replaced by 9-arg version adding runtimePolicy:, runtimeSpecifier:, lastBootedAt:.
 Changed around Xcode 14.
 */
+ (instancetype)simDevice:(NSString *)arg1 UDID:(NSUUID *)arg2 deviceTypeIdentifier:(NSString *)arg3 runtimeIdentifier:(NSString *)arg4 state:(unsigned long long)arg5 deviceSet:(SimDeviceSet *)arg6;

/**
 Old 5-arg factory without error: parameter. Now includes error: as 6th arg.
 Changed around Xcode 14.
 */
+ (instancetype)createDeviceWithName:(NSString *)arg1 deviceSet:(SimDeviceSet *)arg2 deviceType:(SimDeviceType *)arg3 runtime:(SimRuntime *)arg4 initialDataPath:(NSString *)arg5;

/**
 Old 7-arg init. Replaced by 12-arg version adding runtimePolicy:, runtimeSpecifier:,
 preparingForDeletion:, isEphemeral:, lastBootedAt:.
 Changed around Xcode 14.
 */
- (instancetype)initDevice:(NSString *)arg1 UDID:(NSUUID *)arg2 deviceTypeIdentifier:(NSString *)arg3 runtimeIdentifier:(NSString *)arg4 state:(unsigned long long)arg5 initialDataPath:(NSString *)arg6 deviceSet:(SimDeviceSet *)arg7;

/**
 Old 3-arg createLaunchdJob. Replaced by 5-arg version adding binpref:, enableCheckedAllocations:,
 and moving error: to the end.
 Changed around Xcode 15.
 */
- (BOOL)createLaunchdJobWithError:(NSError **)arg1 extraEnvironment:(NSDictionary *)arg2 disabledJobs:(NSDictionary *)arg3;

@end
