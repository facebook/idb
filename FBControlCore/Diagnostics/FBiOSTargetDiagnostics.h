/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBDiagnostic.h>

NS_ASSUME_NONNULL_BEGIN

@class FBDiagnostic;
@class FBDiagnosticBuilder;
@class FBDiagnosticQuery;

/**
 The Name of the Video Log
 */
extern FBDiagnosticName const FBDiagnosticNameVideo;

/**
 A Base Class for Providing Diagnostics from a target.
 */
@interface FBiOSTargetDiagnostics : NSObject

/**
 The Designated Initializer

 @param storageDirectory the default location for persisting diagnostics to.
 @return a new Target Diagnostics instance.
 */
- (instancetype)initWithStorageDirectory:(NSString *)storageDirectory;

/**
 The default location for persisting Diagnostics to.
 */
@property (nonatomic, copy, readonly) NSString *storageDirectory;

/**
 The FBDiagnostic Instance from which all other diagnostics are derived.
 */
- (FBDiagnostic *)base;

/**
 A Video of the Simulator
 */
- (FBDiagnostic *)video;

/**
 The FBDiagnostic Builder from which all other diagnostics are derived.
 */
- (FBDiagnosticBuilder *)baseLogBuilder;

/**
 All of the FBDiagnostic instances for the Simulator.
 Prunes empty logs.

 @return an NSArray<FBDiagnostic> of all the Diagnostics associated with the Simulator.
 */
- (NSArray<FBDiagnostic *> *)allDiagnostics;

/**
 All of the FBDiagnostic instances for the Simulator, bucketed by diagnostic name.
 Prunes empty and unnamed logs

 @return a dictionary mapping diagnostic names to diagnostics.
 */
- (NSDictionary<NSString *, FBDiagnostic *> *)namedDiagnostics;

/**
 Returns an array of the diagnostics that match the query.

 @param query the query to fetch with.
 @return an Array of Diagnostics that match
 */
- (NSArray<FBDiagnostic *> *)perform:(FBDiagnosticQuery *)query;

/**
 A Predicate for FBDiagnostics that have content.
 */
+ (NSPredicate *)predicateForHasContent;

@end

NS_ASSUME_NONNULL_END
