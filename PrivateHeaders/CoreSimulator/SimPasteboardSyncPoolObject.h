/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <objc/NSObject.h>

/**
 Removed from CoreSimulator as of Xcode 27 (CoreSimulator 1155.4): part of the simulator pasteboard / clipboard sync subsystem. No longer
 present in any Xcode 27 framework and not referenced by idb/FBSimulatorControl.
 Header retained for reference and for building against <= Xcode 26.x; scheduled
 for removal.
 */
@interface SimPasteboardSyncPoolObject : NSObject
{
  unsigned long long _lastSeenChangeCount;
  unsigned long long _regID;
}

@property (nonatomic, assign) unsigned long long regID;
@property (nonatomic, assign) unsigned long long lastSeenChangeCount;
- (id)initWithPasteboard:(id)arg1;

@end
