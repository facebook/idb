/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBIDBConfiguration.h"

@implementation FBIDBConfiguration

static id<FBEventReporter> reporter = nil;

+ (id<FBEventReporter>)eventReporter
{
  return reporter;
}

+ (void)setEventReporter:(id<FBEventReporter>)eventReporter
{
  reporter = eventReporter;
}

@end
