/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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

  _memoryGraphData = record.memoryGraphData;
  _diagnosticReportData = record.diagnosticReportData;
  _elementsOfInterest = record.elementsOfInterest;
  _screenImageData = record.screenImageData;
  _hasSubactivities = record.hasSubactivities;
  _start = record.start;
  _finish = record.finish;
  _uuid = record.uuid;
  _title = record.title;
  _duration = record.duration;

  return self;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Title %@ | Duration %f | HasSubactivities %hhd | ScreenImageData %@ | ElementsOfInterest %@ | DiagnosticReportData %@ | MemoryGraphData %@ | Start %@ | Finish %@ | Uuid %@", self.title, self.duration, self.hasSubactivities, self.screenImageData, self.elementsOfInterest, self.diagnosticReportData, self.memoryGraphData, self.start, self.finish, self.uuid];
}

@end
