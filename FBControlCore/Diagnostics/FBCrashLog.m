/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBCrashLog.h"
#import "FBCrashLogInfo.h"

#import <stdio.h>

#import "FBControlCoreGlobalConfiguration.h"
#import "FBDiagnostic.h"
#import "FBConcurrentCollectionOperations.h"
#import "NSPredicate+FBControlCore.h"

#import <Foundation/Foundation.h>


@implementation FBCrashLog

#pragma mark Initializers

+ (instancetype)fromInfo:(FBCrashLogInfo *)info contents:(NSString *)contents
{
    return [[FBCrashLog alloc] initWithInfo:info contents:contents];
}

- (instancetype)initWithInfo:(FBCrashLogInfo *)info contents:(NSString *)contents
{
    self = [super init];
    if (!self) {
        return nil;
    }
    _info = info;
    _contents = contents;
    return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
    // Is immutable
    return self;
}

@end
