/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

static const char *const FBCMFrameworkPath = "/System/Library/Frameworks/CoreMotion.framework/CoreMotion";

@interface CMDeviceStateEvent : NSObject
/**
 * Physical orientation: 0 unknown, 1 portrait, 2 upside down, 3 landscape left,
 * 4 landscape right, 5 face up, 6 face down. The runtime names this `propertyA`;
 * its observed arm64 return encoding is `q` (NSInteger), not an object or byte.
 */
- (NSInteger)propertyA;
@end

@interface CMDeviceStateManager : NSObject
/** Returns the current event at **+0**; ARC retains it across the orientation read. */
- (nullable CMDeviceStateEvent *)currentDeviceState;
@end

@protocol CMDeviceStateManagerClass <NSObject>
+ (BOOL)isAvailable;
/** Returns the process-wide manager at **+0**, with no ownership transfer. */
+ (CMDeviceStateManager *)sharedManager;
@end

NS_ASSUME_NONNULL_END
