/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBEventReporterSubject;

NS_ASSUME_NONNULL_BEGIN

/**
 * Protcol for providing a way of formatting FBEventReporterSubjects
 * into an array of strings, where each string represents the subject itself
 * or one of its subsubjects
 */
@protocol FBEventInterpreter <NSObject>

- (NSArray<NSString *> *)interpret:(FBEventReporterSubject *)eventReporterSubject;

@end

/**
 * Abstract base class for classes conforming to FBEventInterpreter
 * Using this is not required
 * Subclasses should implement
 * - (nullable NSString *)getStringFromEventReporterSubject:(nonnull FBEventReporterSubject *)subject
 */
@interface FBBaseEventInterpreter : NSObject <FBEventInterpreter>

- (nullable NSString *)getStringFromEventReporterSubject:(nonnull FBEventReporterSubject *)subject;
@end


@interface FBJSONEventInterpreter : FBBaseEventInterpreter

@property (nonatomic, assign, readonly) BOOL pretty;

- (instancetype)initWithPrettyFormatting:(BOOL)pretty;

@end


@interface FBHumanReadableEventInterpreter : FBBaseEventInterpreter
@end

NS_ASSUME_NONNULL_END
