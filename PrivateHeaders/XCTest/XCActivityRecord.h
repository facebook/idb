/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

@class NSArray, NSData, NSDate, NSString, NSUUID, XCElementSnapshot, XCSynthesizedEventRecord;

@interface XCActivityRecord : NSObject <NSSecureCoding>
{
  NSString *_title;
  NSUUID *_uuid;
  NSDate *_start;
  NSDate *_finish;
  BOOL _hasSubactivities;
  NSData *_screenImageData;
  XCElementSnapshot *_snapshot;
  NSArray *_elementsOfInterest;
  XCSynthesizedEventRecord *_synthesizedEvent;
  NSData *_diagnosticReportData;
  NSData *_memoryGraphData;
}

@property(copy) NSData *memoryGraphData; // @synthesize memoryGraphData=_memoryGraphData;
@property(copy) NSData *diagnosticReportData; // @synthesize diagnosticReportData=_diagnosticReportData;
@property(retain) XCSynthesizedEventRecord *synthesizedEvent; // @synthesize synthesizedEvent=_synthesizedEvent;
@property(copy) NSArray *elementsOfInterest; // @synthesize elementsOfInterest=_elementsOfInterest;
@property(retain) XCElementSnapshot *snapshot; // @synthesize snapshot=_snapshot;
@property(copy) NSData *screenImageData; // @synthesize screenImageData=_screenImageData;
@property BOOL hasSubactivities; // @synthesize hasSubactivities=_hasSubactivities;
@property(copy) NSDate *start; // @synthesize start=_start;
@property(copy) NSDate *finish; // @synthesize finish=_finish;
@property(copy) NSUUID *uuid; // @synthesize uuid=_uuid;
@property(copy) NSString *title; // @synthesize title=_title;
@property(readonly) double duration;

- (id)init;

@end
