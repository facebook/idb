/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBIDBConfiguration.h"

@implementation FBIDBConfiguration

static id<FBEventReporter> reporter = nil;
static id<FBEventReporter> swiftReporter = nil;


+ (void)setEventReporter:(id<FBEventReporter>)eventReporter
{
  reporter = eventReporter;
}

+ (id<FBEventReporter>)eventReporter
{
  return reporter;
}

+ (id<FBEventReporter>)swiftEventReporter
{
  return swiftReporter;
}

+ (void)setSwiftEventReporter:(id<FBEventReporter>)eventReporter
{
  swiftReporter = eventReporter;
}

@end
