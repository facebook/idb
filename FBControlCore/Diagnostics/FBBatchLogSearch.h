/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBDiagnostic.h>
#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBJSONConversion.h>
#import <FBControlCore/FBiOSTargetFuture.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The Action Type for the HID.
 */
extern FBiOSTargetFutureType const FBiOSTargetFutureTypeSearch;

@class FBDiagnostic;
@class FBLogSearchPredicate;

@protocol FBiOSTarget;

/**
 Options for the Log Search.
 */
typedef NS_OPTIONS(NSUInteger, FBBatchLogSearchOptions) {
  FBBatchLogSearchOptionsFullLines = 1 << 0, // Whether to return full lines.
  FBBatchLogSearchOptionsFirstMatch = 1 << 2, // Return only the first match.
};

/**
 Defines a model for the result of a batch search on diagnostics.
 */
@interface FBBatchLogSearchResult : NSObject <NSCopying, FBJSONSerializable, FBJSONDeserializable, FBDebugDescribeable>

/**
 The Results as a Mapping:
 The returned dictionary is a NSDictionary where:
 - The keys are the log names. A log must have 1 or more matches to have a key.
 - The values are an NSArrray of NSStrings for the lines that have been matched.
 */
@property (nonatomic, copy, readonly) NSDictionary<FBDiagnosticName, NSArray<NSString *> *> *mapping;

/**
 Returns all matches from all elements in the mapping
 */
- (NSArray<NSString *> *)allMatches;

@end

/**
 Defines a model for batch searching diagnostics.
 This model is then used to concurrently search logs, returning the relevant matches.

 Diagnostics are defined in terms of thier short_name.
 Logs are defined in terms of Search Predicates.
 */
@interface FBBatchLogSearch : NSObject <NSCopying, FBiOSTargetFuture>

#pragma mark Initializers

/**
 Constructs a Batch Log Search for the provided mapping of log names to predicates.
 The provided mapping is an NSDictionary where:
 - The keys are the names of the Diagnostics to search. The empty string matches against all input diagnostics.
 - The values are an NSArray of FBLogSearchPredicates of the predicates to search the the diagnostic with.

 @param mapping the mapping to search with.
 @param options the options to search with.
 @param since the date to search from. If nil then the log will be searched from the beginning.
 @param error an error out for any error in the mapping format.
 @return an FBBatchLogSearch instance if the mapping is valid, nil otherwise.
 */
+ (instancetype)searchWithMapping:(NSDictionary<FBDiagnosticName, NSArray<FBLogSearchPredicate *> *> *)mapping options:(FBBatchLogSearchOptions)options since:(nullable NSDate *)since error:(NSError **)error;

#pragma mark Public Methods

/**
 Runs the Receiver over an array of Diagnostics.

 @param diagnostics an NSArray of FBDiagnostics to search.
 @return a search result
 */
- (FBBatchLogSearchResult *)searchDiagnostics:(NSArray<FBDiagnostic *> *)diagnostics;

/**
 Runs the Receiver over an iOS Target.

 @param target the target to search.
 @return a search result, wrapped in a future.
 */
- (FBFuture<FBBatchLogSearchResult *> *)searchOnTarget:(id<FBiOSTarget>)target;

/**
 Convenience method for searching an array of diagnostics with a single predicate.

 @param diagnostics an NSArray of FBDiagnostics to search.
 @param predicate a Log Search Predicate to search with.
 @param options the options to search with.
 @return a NSDictionary specified by -[FBBatchLogSearchResult mapping].
 */
+ (NSDictionary<FBDiagnosticName, NSArray<NSString *> *> *)searchDiagnostics:(NSArray<FBDiagnostic *> *)diagnostics withPredicate:(FBLogSearchPredicate *)predicate options:(FBBatchLogSearchOptions)options;

#pragma mark Properties

/**
 The Search Mapping.
 Described in the Initializer.
 */
@property (nonatomic, copy, readonly) NSDictionary<FBDiagnosticName, NSArray<FBLogSearchPredicate *> *> *mapping;

/**
 Options for the Search.
 */
@property (nonatomic, assign, readonly) FBBatchLogSearchOptions options;

/**
 The start date to search from
 */
@property (nonatomic, strong, nullable, readonly) NSDate *since;

@end

NS_ASSUME_NONNULL_END
