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
