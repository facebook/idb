/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

typedef NSString *FBEventType NS_STRING_ENUM;

extern FBEventType _Nonnull const FBEventTypeStarted;
extern FBEventType _Nonnull const FBEventTypeEnded;
extern FBEventType _Nonnull const FBEventTypeDiscrete;
extern FBEventType _Nonnull const FBEventTypeSuccess;
extern FBEventType _Nonnull const FBEventTypeFailure;

/**
 A value type that holds data about a discrete event in time.
 Passed to the FBEventReporter protocol
 */
@interface FBEventReporterSubject : NSObject

/**
 Construct a sample for logging an event.

 @param eventName the event name
 @return a scuba sample
 */
+ (nonnull instancetype)subjectForEvent:(nonnull NSString *)eventName;

/**
 Construct a sample for a started call.

 @param call the name of the invoked call
 @param arguments the arguments to the invoked call
 @return a scuba sample
 */
+ (nonnull instancetype)subjectForStartedCall:(nonnull NSString *)call arguments:(nonnull NSArray<NSString *> *)arguments;

/**
 Construct a sample for a successful call.

 @param call the name of the invoked call.
 @param duration the duration of the call.
 @param size the size of a payload within a call.
 @param arguments the arguments to the invoked call.
 @return a scuba sample
 */
+ (nonnull instancetype)subjectForSuccessfulCall:(nonnull NSString *)call duration:(NSTimeInterval)duration size:(nullable NSNumber *)size arguments:(nonnull NSArray<NSString *> *)arguments;

/**
 Construct a sample for a failing call.

 @param call the name of the invoked call.
 @param duration the duration of the call.
 @param message the failure message.
 @param size the size of a payload within a call.
 @param arguments the arguments to the invoked call
 @return a scuba sample
 */
+ (nonnull instancetype)subjectForFailingCall:(nonnull NSString *)call duration:(NSTimeInterval)duration message:(nonnull NSString *)message size:(nullable NSNumber *)size arguments:(nonnull NSArray<NSString *> *)arguments;

#pragma mark Properties

/**
 The Event Name.
 */
@property (nonnull, nonatomic, readonly, copy) NSString *eventName;

/**
 The Event Type.
 */
@property (nonnull, nonatomic, readonly, copy) FBEventType eventType;

/**
 A JSON Serializable form of the arguments
 */
@property (nullable, nonatomic, readonly, copy) NSArray<NSString *> *arguments;

/**
 A duration if present.
 */
@property (nullable, nonatomic, readonly, copy) NSNumber *duration;

/**
 A size, if present
 */
@property (nullable, nonatomic, readonly, copy) NSNumber *size;

/**
 A message, if present
 */
@property (nullable, nonatomic, readonly, copy) NSString *message;

@end
