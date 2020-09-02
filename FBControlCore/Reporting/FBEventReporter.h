/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBEventConstants.h>
#import <FBControlCore/FBJSONConversion.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBEventInterpreter;
@protocol FBDataConsumer;
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
 Add metadata to attach to each report.

 @param metadata Metadata to append
 */
- (void)addMetadata:(NSDictionary<NSString *, NSString *> *)metadata;

/**
 The Event Interpreter.
 */
@property (nonatomic, strong, readonly) id<FBEventInterpreter> interpreter;

/**
 The Consumer
 */
@property (nonatomic, strong, readonly) id<FBDataConsumer> consumer;

/**
 Gets the total metadata.
 */
@property (nonatomic, strong, readonly) NSDictionary<NSString *, NSString *> *metadata;

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
+ (id<FBEventReporter>)reporterWithInterpreter:(id<FBEventInterpreter>)interpreter consumer:(id<FBDataConsumer>)consumer;

@end

NS_ASSUME_NONNULL_END
