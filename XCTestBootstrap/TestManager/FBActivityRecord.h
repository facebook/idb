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

@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, copy) NSString *activityType;
@property (nonatomic, readonly, copy) NSUUID *uuid;
@property (nonatomic, readonly, copy) NSDate *start;
@property (nonatomic, readonly, copy) NSDate *finish;
@property (nonatomic, readonly) NSArray<FBAttachment *> *attachments;
@property (nonatomic, readonly, assign) double duration;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, copy) NSMutableArray<FBActivityRecord *> *subactivities;

/**
 Constructs a activity summary from a XCActivityRecord
 */
+ (instancetype)from:(XCActivityRecord *)record;

@end

NS_ASSUME_NONNULL_END
