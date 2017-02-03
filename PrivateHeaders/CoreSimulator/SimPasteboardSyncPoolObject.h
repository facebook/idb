/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <objc/NSObject.h>

@interface SimPasteboardSyncPoolObject : NSObject
{
    unsigned long long _lastSeenChangeCount;
    unsigned long long _regID;
}

@property (nonatomic, assign) unsigned long long regID;
@property (nonatomic, assign) unsigned long long lastSeenChangeCount;
- (id)initWithPasteboard:(id)arg1;

@end
