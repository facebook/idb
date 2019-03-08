/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
