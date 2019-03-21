/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import "FBCrashLogInfo.h"

@class FBDiagnostic;
@class FBDiagnosticBuilder;

NS_ASSUME_NONNULL_BEGIN

/**
 More detailed information about Crash Logs.
 */
@interface FBCrashLog : NSObject <NSCopying>

#pragma mark Properties

/**
 Crash info.
 */
@property (nonatomic, copy, readonly) FBCrashLogInfo *info;

/**
 Crash contents.
 */
@property (nonatomic, copy, readonly) NSString *contents;

#pragma mark Initializers

+ (nullable instancetype)fromInfo:(FBCrashLogInfo *)info contents:(NSString *)contents;

@end

NS_ASSUME_NONNULL_END
