/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBEventReporter.h"

#import "FBEventReporterSubject.h"
#import "FBEventInterpreter.h"
#import "FBDataConsumer.h"

@interface FBEventReporter ()

@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, NSString *> *mutableMetadata;

@end

@implementation FBEventReporter

@synthesize interpreter = _interpreter;
@synthesize consumer = _consumer;

#pragma mark Initializers

+ (id<FBEventReporter>)reporterWithInterpreter:(id<FBEventInterpreter>)interpreter consumer:(id<FBDataConsumer>)consumer
{
  return [[self alloc] initWithInterpreter:interpreter consumer:consumer];
}

- (instancetype)initWithInterpreter:(id<FBEventInterpreter>)interpreter consumer:(id<FBDataConsumer>)consumer
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _interpreter = interpreter;
  _consumer = consumer;
  _mutableMetadata = NSMutableDictionary.dictionary;

  return self;
}

#pragma mark FBEventReporter Implementation

- (void)report:(id<FBEventReporterSubject>)subject
{
  NSString *output = [self.interpreter interpret:subject];
  NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
  [self.consumer consumeData:data];
}

- (void)addMetadata:(NSDictionary<NSString *, NSString *> *)metadata
{
  [self.mutableMetadata addEntriesFromDictionary:metadata];
}

- (NSDictionary<NSString *, NSString *> *)metadata
{
  return self.mutableMetadata.copy;
}

@end
