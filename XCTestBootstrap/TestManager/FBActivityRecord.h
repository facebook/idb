/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class FBAttachment;
@class XCActivityRecord;

NS_ASSUME_NONNULL_BEGIN

/**
 A summary of an activity.
 */
@interface FBActivityRecord : NSObject

@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *activityType;
@property (nonatomic, copy, readonly) NSUUID *uuid;
@property (nonatomic, copy, readonly) NSDate *start;
@property (nonatomic, copy, readonly) NSDate *finish;
@property (nonatomic, readonly) NSArray<FBAttachment *> *attachments;
@property (nonatomic, assign, readonly) double duration;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy) NSMutableArray<FBActivityRecord *> *subactivities;

/**
 Constructs a activity summary from a XCActivityRecord
 */
+ (instancetype)from:(XCActivityRecord *)record;

@end

NS_ASSUME_NONNULL_END
