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
#import <FBControlCore/FBJSONEnums.h>
#import <FBControlCore/FBiOSTargetFormat.h>
#import <FBControlCore/FBiOSTarget.h>
#import <asl.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Abstract base class for providing data to EventReporters
 */
@interface FBEventReporterSubject : NSObject <FBJSONSerializable>

@property (nonatomic, copy, readonly) NSArray<FBEventReporterSubject *> *subSubjects;

@end

/**
 * An FBEventReporterSubject containing an event name, event type and another subject
 */
@interface FBSimpleSubject : FBEventReporterSubject

- (instancetype)initWithName:(FBEventName)name
                        type:(FBEventType)type
                     subject:(FBEventReporterSubject *)subject;

@end


/**
 * An FBEventReporterSubject that holds some FBJSONSerializable value
 */
@interface FBControlCoreSubject : FBEventReporterSubject

- (instancetype)initWithValue:(id<FBJSONSerializable>)controlCoreValue;

@end


/**
 * An FBEventReporterSubject containing a FBiOSTarget and FBiOSTargetFormat
 */
@interface FBiOSTargetSubject : FBEventReporterSubject

- (instancetype)initWithTarget:(id<FBiOSTarget>)target
                        format:(FBiOSTargetFormat *)format;

@end


/**
 * An FBEventReporterSubject containing a target subject,
 * as well as an event name, type and subject to contain
 */
@interface FBiOSTargetWithSubject : FBEventReporterSubject

- (instancetype)initWithTargetSubject:(FBiOSTargetSubject *)targetSubject
                            eventName:(FBEventName)eventName
                            eventType:(FBEventType)eventType
                              subject:(FBEventReporterSubject *)subject;

@end


/**
 * An FBEventReporterSubject that holds a string to log and its level
 */
@interface FBLogSubject : FBEventReporterSubject

- (instancetype)initWithLogString:(NSString *)string level:(int)level;

@end


/**
 * An FBEventReporterSubject that has subsubjects
 */
@interface FBCompositeSubject : FBEventReporterSubject

- (instancetype)initWithArray:(NSArray<FBEventReporterSubject *> *)eventReporterSubject;

@end

/**
 * An FBEventReporterSubject that can hold a single string
 */
@interface FBStringSubject : FBEventReporterSubject

- (instancetype)initWithString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
