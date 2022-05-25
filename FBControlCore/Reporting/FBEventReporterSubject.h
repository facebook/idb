/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSString *FBEventType NS_STRING_ENUM;

extern FBEventType const FBEventTypeStarted;
extern FBEventType const FBEventTypeEnded;
extern FBEventType const FBEventTypeDiscrete;
extern FBEventType const FBEventTypeSuccess;
extern FBEventType const FBEventTypeFailure;

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
+ (instancetype)subjectForEvent:(NSString *)eventName;

/**
 Construct a sample for a started call.

 @param call the name of the invoked call
 @param arguments the arguments to the invoked call
 @return a scuba sample
 */
+ (instancetype)subjectForStartedCall:(NSString *)call arguments:(NSArray<NSString *> *)arguments reportNativeSwiftMethodCall:(BOOL)reportNativeSwiftMethodCall;

/**
 Construct a sample for a successful call.

 @param call the name of the invoked call.
 @param duration the duration of the call.
 @param size the size of a payload within a call.
 @param arguments the arguments to the invoked call.
 @return a scuba sample
 */
+ (instancetype)subjectForSuccessfulCall:(NSString *)call duration:(NSTimeInterval)duration size:(nullable NSNumber *)size arguments:(NSArray<NSString *> *)arguments reportNativeSwiftMethodCall:(BOOL)reportNativeSwiftMethodCall;

/**
 Construct a sample for a failing call.

 @param call the name of the invoked call.
 @param duration the duration of the call.
 @param message the failure message.
 @param size the size of a payload within a call.
 @param arguments the arguments to the invoked call
 @return a scuba sample
 */
+ (instancetype)subjectForFailingCall:(NSString *)call duration:(NSTimeInterval)duration message:(NSString *)message size:(nullable NSNumber *)size arguments:(NSArray<NSString *> *)arguments reportNativeSwiftMethodCall:(BOOL)reportNativeSwiftMethodCall;

#pragma mark Properties

/**
 The Event Name, if present
 */
@property (nonatomic, copy, nullable, readonly) NSString * eventName;

/**
 The Event Type, if present
 */
@property (nonatomic, copy, nullable, readonly) FBEventType eventType;

/**
 A JSON Serializable form of the arguments
 */
@property (nonatomic, copy, nullable, readonly) NSArray<NSString *> *arguments;

/**
 A duration if present.
 */
@property (nonatomic, copy, nullable, readonly) NSNumber *duration;

/**
 A size, if present
 */
@property (nonatomic, copy, nullable, readonly) NSNumber *size;

/**
 A message, if present
 */
@property (nonatomic, copy, nullable, readonly) NSString *message;

/**
 Marks is method was called natively in swift
 */
@property (readonly) BOOL reportNativeSwiftMethodCall;

@end

NS_ASSUME_NONNULL_END
