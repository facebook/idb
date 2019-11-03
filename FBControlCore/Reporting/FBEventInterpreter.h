/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBEventReporterSubject;

/**
 Protocol for providing a way of formatting FBEventReporterSubjects
 into an array of strings, where each string represents the subject itself
 or one of its subsubjects
 */
@protocol FBEventInterpreter <NSObject>

/**
 Interpret the Subject, converting it to a string representation.

 @param subject the subject to interpret.
 @return the string that has been interpreted.
 */
- (NSString *)interpret:(id<FBEventReporterSubject>)subject;

/**
 Interpret the Subject, converting it to an array of lines.

 @param subject the subject to interpret.
 @return the lines that have been interpreted.
 */
- (NSArray<NSString *> *)interpretLines:(id<FBEventReporterSubject>)subject;

@end

/**
 Implementations of Event Interpreters.
 */
@interface FBEventInterpreter : NSObject <FBEventInterpreter>

/**
 A JSON Interpreter.

 @param pretty YES if a pretty printed interpreter, NO otherwise.
 */
+ (instancetype)jsonEventInterpreter:(BOOL)pretty;

/**
 A Human Readable Event Interpreter.
 */
+ (instancetype)humanReadableInterpreter;

@end

NS_ASSUME_NONNULL_END
