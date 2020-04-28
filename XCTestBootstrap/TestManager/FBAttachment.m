/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAttachment.h"
#import <XCTest/XCTAttachment.h>

@implementation FBAttachment

+ (instancetype)from:(XCTAttachment *)attachment
{
  return [[self alloc] initFromAttachment:attachment];
}

- (instancetype)initFromAttachment:(XCTAttachment *)attachment
{
  self = [super init];

  if (!self) {
    return nil;
  }

  _payload = attachment.hasPayload ? attachment.payload : nil;
  _timestamp = attachment.timestamp;
  _name = attachment.name;
  _uniformTypeIdentifier = attachment.uniformTypeIdentifier;

  return self;
}

@end
