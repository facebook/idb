/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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

@end

NS_ASSUME_NONNULL_END
