/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "NSObject.h"

#import "NSCopying.h"

@interface AXPiOSElementData : NSObject <NSCopying>
{
    int _pid;
    CDStruct_26bd94fa _uid;
}

@property(nonatomic) int pid; // @synthesize pid=_pid;
@property(nonatomic) CDStruct_26bd94fa uid; // @synthesize uid=_uid;
- (id)description;
- (unsigned long long)hash;
- (BOOL)isEqual:(id)arg1;
- (id)copyWithZone:(struct _NSZone *)arg1;

@end

