/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class XCTAttachment;

NS_ASSUME_NONNULL_BEGIN

@interface FBAttachment : NSObject

@property (nonatomic, copy, readonly, nullable) NSData *payload;
@property (nonatomic, copy, readonly) NSDate *timestamp;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *uniformTypeIdentifier;
@property (nonatomic, copy, readonly, nullable) NSDictionary<NSString *, id> *userInfo;

/**
 Constructs a attachment  from a XCTAttachment
 */
+ (instancetype)from:(XCTAttachment *)record;

@end

NS_ASSUME_NONNULL_END
