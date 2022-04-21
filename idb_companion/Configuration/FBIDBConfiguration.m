/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBIDBConfiguration.h"
#import "idb-Swift.h"

@implementation FBIDBConfiguration

static id<FBEventReporter> reporter = nil;
static id<FBEventReporter> swiftReporter = nil;


+ (void)setEventReporter:(id<FBEventReporter>)eventReporter
{
  reporter = eventReporter;
}

+ (id<FBEventReporter>)eventReporter
{
  if (reporter) {
    return reporter;
  }
  return EmptyEventReporter.shared;
}

+ (id<FBEventReporter>)swiftEventReporter
{
  if (swiftReporter) {
    return swiftReporter;
  }
  return EmptyEventReporter.shared;
}

+ (void)setSwiftEventReporter:(id<FBEventReporter>)eventReporter
{
  swiftReporter = eventReporter;
}

@end
