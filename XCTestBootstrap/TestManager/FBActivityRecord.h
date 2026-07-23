/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class FBAttachment;
@class XCActivityRecord;

/**
 A summary of an activity.
 */
@interface FBActivityRecord : NSObject

@property (nonnull, nonatomic, readonly, copy) NSString *title;
@property (nonnull, nonatomic, readonly, copy) NSString *activityType;
@property (nonnull, nonatomic, readonly, copy) NSUUID *uuid;
@property (nonnull, nonatomic, readonly, copy) NSDate *start;
@property (nonnull, nonatomic, readonly, copy) NSDate *finish;
@property (nonnull, nonatomic, readonly) NSArray<FBAttachment *> *attachments;
@property (nonatomic, readonly, assign) double duration;
@property (nonnull, nonatomic, readonly, copy) NSString *name;
@property (nonnull, nonatomic, copy) NSMutableArray<FBActivityRecord *> *subactivities;

/**
 Constructs a activity summary from a XCActivityRecord
 */
+ (nonnull instancetype)from:(nonnull XCActivityRecord *)record;

@end
