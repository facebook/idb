/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBEventReporter.h"

#import "FBSubject.h"
#import "FBEventInterpreter.h"
#import "FBFileConsumer.h"

@implementation FBEventReporter

@synthesize interpreter = _interpreter;
@synthesize consumer = _consumer;

#pragma mark Initializers

+ (id<FBEventReporter>)reporterWithInterpreter:(id<FBEventInterpreter>)interpreter consumer:(id<FBFileConsumer>)consumer
{
  return [[self alloc] initWithInterpreter:interpreter consumer:consumer];
}

- (instancetype)initWithInterpreter:(id<FBEventInterpreter>)interpreter consumer:(id<FBFileConsumer>)consumer
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _interpreter = interpreter;
  _consumer = consumer;

  return self;
}

#pragma mark FBEventReporter Implementation

- (void)report:(id<FBEventReporterSubject>)subject
{
  NSString *output = [self.interpreter interpret:subject];
  NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
  [self.consumer consumeData:data];
}

@end
