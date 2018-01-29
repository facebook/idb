/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBEventConstants.h>
#import <FBControlCore/FBJSONConversion.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBEventInterpreter;
@protocol FBFileConsumer;
@protocol FBEventReporterSubject;

/**
 An Event Reporter Protocol to interface to event reporting.
 */
@protocol FBEventReporter <NSObject>

/**
 Reports a Subject

 @param subject the subject to report.
 */
- (void)report:(id<FBEventReporterSubject>)subject;

/**
 The Event Interpreter.
 */
@property (nonatomic, strong, readonly) id<FBEventInterpreter> interpreter;

/**
 The Consumer
 */
@property (nonatomic, strong, readonly) id<FBFileConsumer> consumer;

@end

/**
 Implementations of FBEventReporter.
 */
@interface FBEventReporter : NSObject <FBEventReporter>

/**
 The Designated Initializer

 @param interpreter the interpreter to use.
 @param consumer the consumer to write to.
 @return a new Event Reporter.
 */
+ (id<FBEventReporter>)reporterWithInterpreter:(id<FBEventInterpreter>)interpreter consumer:(id<FBFileConsumer>)consumer;

@end

NS_ASSUME_NONNULL_END
