/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <FBControlCore/FBJSONConversion.h>
#import <FBControlCore/FBEventConstants.h>
#import <FBControlCore/FBiOSTargetFormat.h>
#import <FBControlCore/FBiOSTarget.h>
#import <asl.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A Protocol for providing value-data for further Event Reporting.
 */
@protocol FBEventReporterSubject <NSObject, FBJSONSerializable>

/**
 An Array of all the composed Subjects.
 */
@property (nonatomic, copy, readonly) NSArray<id<FBEventReporterSubject>> *subSubjects;

/**
 The Event Name, if present
 */
@property (nonatomic, copy, nullable, readonly) FBEventName eventName;

/**
 The Event Type, if present
 */
@property (nonatomic, copy, nullable, readonly) FBEventType eventType;

/**
 A JSON Serializable form of the argument.
 */
@property (nonatomic, copy, nullable, readonly) NSDictionary<NSString *, NSString *> *argument;

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

@end

/**
 Implementations of Subjects.
 */
@interface FBEventReporterSubject : NSObject <FBEventReporterSubject>

/**
 An FBEventReporterSubject containing an event name, event type and another subject.

 @param name the Event Name.
 @param type the Event Type.
 @param subject the other content.
 @return a Event Reporter Subject.
 */
+ (instancetype)subjectWithName:(FBEventName)name type:(FBEventType)type subject:(id<FBEventReporterSubject>)subject NS_SWIFT_NAME(init(name:type:subject:));

/**
 An FBEventReporterSubject containing an event name, event type and another value.

 @param name the Event Name.
 @param type the Event Type.
 @param value the value.
 @return a Event Reporter Subject.
 */
+ (instancetype)subjectWithName:(FBEventName)name type:(FBEventType)type value:(id<FBJSONSerializable>)value NS_SWIFT_NAME(init(name:type:value:));

/**
 An FBEventReporterSubject containing an event name, event type and some values.

 @param name the Event Name.
 @param type the Event Type.
 @param values the Serializable Values.
 @return a Event Reporter Subject.
 */
+ (instancetype)subjectWithName:(FBEventName)name type:(FBEventType)type values:(NSArray<id<FBJSONSerializable>> *)values NS_SWIFT_NAME(init(name:type:values:));

/**
 An FBEventReporterSubject for a reportable value.

 @param controlCoreValue the ControlCoreValue, which will conform to (FBJSONSerializable & CustomStringConvertible)
 @return a Event Reporter Subject.
 */
+ (instancetype)subjectWithControlCoreValue:(id<FBJSONSerializable>)controlCoreValue NS_SWIFT_NAME(init(value:));

/**
 A Formated iOS Target Subject.

 @param target the iOS Target.
 @param format the Target Format.
 @return a Event Reporter Subject.
 */
+ (instancetype)subjectWithTarget:(id<FBiOSTarget>)target format:(FBiOSTargetFormat *)format NS_SWIFT_NAME(init(target:format:));

/**
 A Formatted iOS Target, composing another subject.

 @param target the iOS Target.
 @param format the Target Format.
 @param eventName the Event Name.
 @param eventType the Event Type.
 @param subject the other content.
 */
+ (instancetype)subjectWithTarget:(id<FBiOSTarget>)target format:(FBiOSTargetFormat *)format eventName:(FBEventName)eventName eventType:(FBEventType)eventType subject:(id<FBEventReporterSubject>)subject NS_SWIFT_NAME(init(target:format:name:type:subject:));

/**
 A Subject of a single String.

 @param string the String.
 @return a Event Reporter Subject.
 */
+ (instancetype)subjectWithString:(NSString *)string NS_SWIFT_NAME(init(string:));

/**
 A Subject of Strings.

 @param strings the Strings.
 @return a Event Reporter Subject.
 */
+ (instancetype)subjectWithStrings:(NSArray<NSString *> *)strings NS_SWIFT_NAME(init(strings:));

/**
 A Logging Subject.

 @param string the string to log.
 @param level the log level.
 @return a Event Reporter Subject.
 */
+ (instancetype)logSubjectWithString:(NSString *)string level:(int)level NS_SWIFT_NAME(init(logString:level:));

/**
 A Subject that composes multiple other subjects.

 @param subjects the composed subjects.
 @return a Event Reporter Subject.
 */
+ (instancetype)compositeSubjectWithArray:(NSArray<id<FBEventReporterSubject>> *)subjects NS_SWIFT_NAME(init(subjects:));

/**
 Construct a sample for logging an event.

 @param eventName the event name
 @return a scuba sample
 */
+ (id<FBEventReporterSubject>)subjectForEvent:(FBEventName)eventName;

/**
 Construct a sample for a started call.

 @param call the name of the invoked call
 @param argument a key-value representation of the argument to the call.
 @return a scuba sample
 */
+ (id<FBEventReporterSubject>)subjectForStartedCall:(NSString *)call argument:(NSDictionary<NSString *, NSString *> *)argument;

/**
 Construct a sample for a started call.

 @param call the name of the invoked call
 @param arguments the arguments to the invoked call
 @return a scuba sample
 */
+ (id<FBEventReporterSubject>)subjectForStartedCall:(NSString *)call arguments:(NSArray<NSString *> *)arguments;

/**
 Construct a sample for a successful call.

 @param call the name of the invoked call
 @param duration the duration of the call.
 @param argument a key-value representation of the argument to the call.
 @return a scuba sample
 */
+ (id<FBEventReporterSubject>)subjectForSuccessfulCall:(NSString *)call duration:(NSTimeInterval)duration argument:(NSDictionary<NSString *, NSString *> *)argument;

/**
 Construct a sample for a successful call.

 @param call the name of the invoked call.
 @param duration the duration of the call.
 @param size the size of a payload within a call.
 @param arguments the arguments to the invoked call.
 @return a scuba sample
 */
+ (id<FBEventReporterSubject>)subjectForSuccessfulCall:(NSString *)call duration:(NSTimeInterval)duration size:(nullable NSNumber *)size arguments:(NSArray<NSString *> *)arguments;

/**
 Construct a sample for a failing call.

 @param call the name of the invoked call.
 @param duration the duration of the call.
 @param message the failure message.
 @param argument a key-value representation of the argument to the call.
 @return a scuba sample
 */
+ (id<FBEventReporterSubject>)subjectForFailingCall:(NSString *)call duration:(NSTimeInterval)duration message:(nullable NSString *)message argument:(NSDictionary<NSString *, NSString *> *)argument;

/**
 Construct a sample for a failing call.

 @param call the name of the invoked call.
 @param duration the duration of the call.
 @param message the failure message.
 @param size the size of a payload within a call.
 @param arguments the arguments to the invoked call
 @return a scuba sample
 */
+ (id<FBEventReporterSubject>)subjectForFailingCall:(NSString *)call duration:(NSTimeInterval)duration message:(NSString *)message size:(nullable NSNumber *)size arguments:(NSArray<NSString *> *)arguments;

@end

NS_ASSUME_NONNULL_END
