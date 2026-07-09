/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class XCTAttachment;

@interface FBAttachment : NSObject

@property (nullable, nonatomic, readonly, copy) NSData *payload;
@property (nonnull, nonatomic, readonly, copy) NSDate *timestamp;
@property (nonnull, nonatomic, readonly, copy) NSString *name;
@property (nonnull, nonatomic, readonly, copy) NSString *uniformTypeIdentifier;
@property (nullable, nonatomic, readonly, copy) NSDictionary<NSString *, id> *userInfo;

/**
 Constructs a attachment  from a XCTAttachment
 */
+ (nonnull instancetype)from:(nonnull XCTAttachment *)record;

@end
