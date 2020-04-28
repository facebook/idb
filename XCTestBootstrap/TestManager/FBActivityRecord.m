/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBActivityRecord.h"
#import "FBAttachment.h"
#import <XCTest/XCActivityRecord.h>

@implementation FBActivityRecord

+ (instancetype)from:(XCActivityRecord *)record
{
  return [[self alloc] initFromRecord:record];
}

- (instancetype)initFromRecord:(XCActivityRecord *)record
{
  self = [super init];

  if (!self) {
    return nil;
  }

  _title = record.title;
  _activityType = record.activityType;
  _uuid = record.uuid;
  _start = record.start;
  _finish = record.finish;
  NSMutableArray <FBAttachment *> *attachments = [NSMutableArray array];
  for (XCTAttachment *attachment in record.attachments) {
    [attachments addObject:[FBAttachment from:attachment]];
  }
  _attachments = attachments;
  _duration = record.duration;
  _name = record.name;
  _subactivities = [NSMutableArray array];

  return self;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Title %@ | Duration %f | Start %@ | Finish %@ | Uuid %@", self.title, self.duration, self.start, self.finish, self.uuid];
}

@end
