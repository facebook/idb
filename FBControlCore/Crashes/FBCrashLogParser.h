/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBCrashLogParser <NSObject>
-(void)parseCrashLogFromString:(NSString *)str executablePathOut:(NSString *_Nonnull * _Nonnull)executablePathOut identifierOut:(NSString *_Nonnull * _Nonnull)identifierOut processNameOut:(NSString *_Nonnull * _Nonnull)processNameOut parentProcessNameOut:(NSString *_Nonnull * _Nonnull)parentProcessNameOut processIdentifierOut:(pid_t *)processIdentifierOut parentProcessIdentifierOut:(pid_t *)parentProcessIdentifierOut dateOut:(NSDate *_Nonnull * _Nonnull)dateOut  exceptionDescription:(NSString *_Nonnull * _Nonnull)exceptionDescription crashedThreadDescription:(NSString *_Nonnull * _Nonnull)crashedThreadDescription error:(NSError **)error;
@end

/**
 .ips file for macOS 12+ is two concatenated json strings.
 1st is is metadata json, second is content json. Some of the fields from metadata repeats in content json. Considering the facts that:
 1. The layout can be changed by apple easily
 2. Json structure inself can be easily changed
 3. Crashes is not often happening operation of idb
 we prefer reliability over performance gain here and parse all json strings finding the fields that we need in all of json entries
*/
@interface FBConcatedJSONCrashLogParser : NSObject <FBCrashLogParser>
@end

/**
 This parser handles old plain text implementation of crash results
 */
@interface FBPlainTextCrashLogParser : NSObject <FBCrashLogParser>
@end

NS_ASSUME_NONNULL_END
