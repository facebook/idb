/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBiOSTargetFuture.h>
#import <FBControlCore/FBCrashLog.h>
#import <FBControlCore/NSPredicate+FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBDiagnostic;

/**
 The Action Type for a Diagnostic Query.
 */
extern FBiOSTargetFutureType const FBiOSTargetFutureTypeDiagnosticQuery;

typedef NSString *FBDiagnosticQueryFormat NS_STRING_ENUM;
extern FBDiagnosticQueryFormat FBDiagnosticQueryFormatCurrent;
extern FBDiagnosticQueryFormat FBDiagnosticQueryFormatPath;
extern FBDiagnosticQueryFormat FBDiagnosticQueryFormatContent;

/**
 A value object for describing which diagnostics to fetch.
 */
@interface FBDiagnosticQuery : NSObject <NSCopying, FBiOSTargetFuture>

#pragma mark Initializers

/**
 A Query for all diagnostics that match a given name.

 @param names the names to search for.
 @return a FBDiagnosticQuery.
 */
+ (instancetype)named:(NSArray<NSString *> *)names;

/**
 A Query for all static diagnostics.

 @return a FBDiagnosticQuery.
 */
+ (instancetype)all;

/**
 A Query for Crashes of a Process Type, after a date.

 @param processType the Process Types to search for.
 @param date the date to search from.
 @return a FBDiagnosticQuery.
 */
+ (instancetype)crashesOfType:(FBCrashLogInfoProcessType)processType since:(NSDate *)date;

/**
 Derives a new Diagnostic Query, with the new format applied.

 @param format the format to apply.
 @return a new Diagnostic Query.
 */
- (instancetype)withFormat:(FBDiagnosticQueryFormat)format;

#pragma mark Properties

/**
 The Output Format of a Query.
 */
@property (nonatomic, copy, readonly) FBDiagnosticQueryFormat format;

#pragma mark Public Methods

/**
 Run the query against a target.

 @param target the target to run against.
 @return a future returning the diagnostics that were fetched.
 */
- (FBFuture<NSArray<FBDiagnostic *> *> *)run:(id<FBiOSTarget>)target;

@end

NS_ASSUME_NONNULL_END
