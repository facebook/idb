/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBJSONConversion.h>
#import <FBSimulatorControl/FBDebugDescribeable.h>

@class FBDiagnostic;

/**
 A Predicate for finding substrings in text.
 */
@interface FBLogSearchPredicate : NSObject <NSCopying, NSCoding, FBJSONSerializable, FBJSONDeserializable, FBDebugDescribeable>

/**
 A predicate that will match a line containing one of the substrings.
 Substrings cannot contain newline characters.
 
 @param substrings the substrings to search for.
 @return a Log Search Predicate.
 */
+ (instancetype)substrings:(NSArray *)substrings;

/**
 A predicate that will match a line matching the regular expression.

 @param regex a regex that will compile with NSRegularExpression
 @return a Log Search Predicate.
 */
+ (instancetype)regex:(NSString *)regex;

@end

/**
 Defines a model for batch searching diagnostics.
 This model is then used to concurrently search logs, returning the relevant matches.

 Diagnostics are defined in terms of thier short_name.
 Logs are defined in terms of Search Predicates.
 */
@interface FBBatchLogSearch : NSObject <NSCopying, NSCoding, FBJSONSerializable, FBJSONDeserializable, FBDebugDescribeable>

/**
 Constructs a Batch Log Search for the provided mapping of log names to predicates.
 The provided mapping is an NSDictionary where:
 - The keys are an NSArray of NSStrings of the names of the Logs to search.
 - The values are an NSArray of FBLogSearchPredicates of the predicates to search the named logs with.

 @param mapping the mapping to search with.
 @param error an error out for any error in the mapping format.
 @return an FBBatchLogSearch instance if the mapping is valid, nil otherwise.
 */
+ (instancetype)withMapping:(NSDictionary *)mapping error:(NSError **)error;

/**
 Runs the Reciever over an array of Diagnostics.
 The returned dictionary is a NSDictionary where:
 - The keys are the log names. A log must have 1 or more matches to have a key.
 - The values are an NSArrray of NSStrings for the lines that have been matched.

 @param diagnostics an NSArray
 @return an NSDictionary of valid search results.
 */
- (NSDictionary *)search:(NSArray *)diagnostics;

@end

/**
 Wraps FBDiagnostic with Log Searching Abilities.
 */
@interface FBLogSearch : NSObject

/**
 Creates a Log Searcher for the given diagnostic.
 
 @param diagnostic the diagnostic to search.
 @param predicate the predicate to search with.
 */
+ (instancetype)withDiagnostic:(FBDiagnostic *)diagnostic predicate:(FBLogSearchPredicate *)predicate;

/**
 Searches the Diagnostic Log, returning the first match.
 If the Diagnostic is not searchable as text, nil will be returned.

 @return the first line matching the predicate in the diagnostic, nil if nothing was found.
 */
- (NSString *)firstMatchingLine;

/**
 The Diagnostic to Search.
 */
@property (nonatomic, copy, readonly) FBDiagnostic *diagnostic;

/**
 The Predicate to Search with.
 */
@property (nonatomic, copy, readonly) FBLogSearchPredicate *predicate;

@end
