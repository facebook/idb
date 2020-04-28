/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBActivityRecord.h"
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

  _start = record.start;
  _finish = record.finish;
  _uuid = record.uuid;
  _title = record.title;
  _duration = record.duration;

  return self;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Title %@ | Duration %f | Start %@ | Finish %@ | Uuid %@", self.title, self.duration, self.start, self.finish, self.uuid];
}

@end
