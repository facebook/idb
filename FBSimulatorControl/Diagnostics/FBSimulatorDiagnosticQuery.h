/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBSimulatorDiagnostics;

NS_ASSUME_NONNULL_BEGIN

/**
 A Value object for searching for, and returning diagnostics.
 */
@interface FBSimulatorDiagnosticQuery : NSObject <NSCopying, NSCoding, FBJSONSerializable, FBJSONDeserializable, FBDebugDescribeable>

#pragma mark Initializers

/**
 A Query for all diagnostics that match a given name.

 @param names the names to search for.
 @return a FBSimulatorDiagnosticQuery.
 */
+ (instancetype)named:(NSArray<NSString *> *)names;

/**
 A Query for all static diagnostics.

 @return a FBSimulatorDiagnosticQuery.
 */
+ (instancetype)all;

/**
 A Query for Diagnostics in an Application's Sandbox.

 @param bundleID the Application Bundle ID to search in.
 @param filenames the filenames to search for.
 @return a FBSimulatorDiagnosticQuery.
 */
+ (instancetype)filesInApplicationOfBundleID:(NSString *)bundleID withFilenames:(NSArray<NSString *> *)filenames;

/**
 A Query for Crashes of a Process Type, after a date.

 @param processType the Process Types to search for.
 @param date the date to search from.
 @return a FBSimulatorDiagnosticQuery.
 */
+ (instancetype)crashesOfType:(FBCrashLogInfoProcessType)processType since:(NSDate *)date;

#pragma mark Performing

/**
 Returns an array of the diagnostics that match the query.

 @param diagnostics the Simulator diagnostics object to fetch from.
 @return an Array of Diagnostics that match
 */
- (NSArray<FBDiagnostic *> *)perform:(FBSimulatorDiagnostics *)diagnostics;

@end

NS_ASSUME_NONNULL_END
