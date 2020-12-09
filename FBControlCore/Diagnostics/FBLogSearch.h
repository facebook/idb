/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBJSONConversion.h>

NS_ASSUME_NONNULL_BEGIN

@class FBDiagnostic;

/**
 A Predicate for finding substrings in text.
 */
@interface FBLogSearchPredicate : NSObject <NSCopying, FBJSONSerializable, FBJSONDeserializable>

#pragma mark Initializers

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

#pragma mark Helpers

/**
 Constructs the argument to to be passed to the '--predicate' parameter in log(1) from a list of predicates.

 @param predicates the predicates to compile.
 @param error an error out for any error that occurs.
 @return a String to be passed to '--predicate' if successful, nil if the expression could not be compiled.
 */
+ (nullable NSString *)logAgumentsFromPredicates:(NSArray<FBLogSearchPredicate *> *)predicates error:(NSError **)error;

@end

/**
 A Container for a Search.
 */
@interface FBLogSearch : NSObject

/**
 A Log search on a body of text.

 @param text the text to search through.
 @param predicate the predicate to search with.
 @return a Log Search.
 */
+ (FBLogSearch *)withText:(NSString *)text predicate:(FBLogSearchPredicate *)predicate;

/**
 Returns all of the Lines that will be Searched.
 */
- (NSArray<NSString *> *)lines;

/**
 Searches the Diagnostic Log, returning all matches of the predicate.
 If the Diagnostic is not searchable as text, an empty array will be returned.

 @return the all matches of the predicate in the diagnostic.
 */
- (NSArray<NSString *> *)allMatches;

/**
 Searches the Diagnostic Log, returning all lines that match the predicate of the predicate.
 If the Diagnostic is not searchable as text, an empty array will be returned.

 @return the all matching lines of the predicate in the diagnostic.
 */
- (NSArray<NSString *> *)matchingLines;

/**
 Searches the Diagnostic Log, returning the first match of the predicate.

 @return the first match of the predicate in the diagnostic, nil if nothing was found.
 */
- (nullable NSString *)firstMatch;

/**
 Searches the Diagnostic Log, returning the line where the first match was found.

 @return the first line matching the predicate in the diagnostic, nil if nothing was found.
 */
- (nullable NSString *)firstMatchingLine;

/**
 The Predicate to Search with.
 */
@property (nonatomic, copy, readonly) FBLogSearchPredicate *predicate;

@end

/**
 Wraps FBDiagnostic with Log Searching Abilities by augmenting FBLogSearch.

 Most Diagnostics have effectively constant content, except for file backed diagnostics.
 The content of file logs will be lazily fetched, so it's contents may change if the file backing it changes.
 This is worth bearing in mind of the caller expects idempotent results.
 */
@interface FBDiagnosticLogSearch : FBLogSearch

/**
 Creates a Log Searcher for the given diagnostic.

 @param diagnostic the diagnostic to search.
 @param predicate the predicate to search with.
 */
+ (FBDiagnosticLogSearch *)withDiagnostic:(FBDiagnostic *)diagnostic predicate:(FBLogSearchPredicate *)predicate;

/**
 The Diagnostic that will be Searched.
 */
@property (nonatomic, copy, readonly) FBDiagnostic *diagnostic;

@end

NS_ASSUME_NONNULL_END
