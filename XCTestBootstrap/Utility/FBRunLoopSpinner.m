/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBRunLoopSpinner.h"

#import "NSError+XCTestBootstrap.h"

@interface FBRunLoopSpinner ()
@property (nonatomic, copy) NSString *timeoutErrorMessage;
@property (nonatomic, assign) NSTimeInterval timeout;
@property (nonatomic, copy) NSString *reminderMessage;
@property (nonatomic, assign) NSTimeInterval reminderInterval;
@end

@implementation FBRunLoopSpinner

+ (id)spinUntilBlockFinished:(id (^)())block
{
  __block volatile uint32_t didFinish = 0;
  __block id returnObject;
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    returnObject = block();
    OSAtomicOr32Barrier(1, &didFinish);
  });
  while (!didFinish) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
  }
  return returnObject;
}

- (instancetype)init
{
  self = [super init];
  if (self) {
    _timeout = 60;
    _reminderInterval = 5;
  }
  return self;
}

- (instancetype)reminderMessage:(NSString *)reminderMessage
{
  self.reminderMessage = reminderMessage;
  return self;
}

- (instancetype)reminderInterval:(NSTimeInterval)reminderInterval
{
  self.reminderInterval = reminderInterval;
  return self;
}

- (instancetype)timeoutErrorMessage:(NSString *)timeoutErrorMessage
{
  self.timeoutErrorMessage = timeoutErrorMessage;
  return self;
}

- (instancetype)timeout:(NSTimeInterval)timeout
{
  self.timeout = timeout;
  return self;
}

- (BOOL)spinUntilTrue:(FBRunLoopSpinnerBlock)untilTrue
{
  return [self spinUntilTrue:untilTrue error:nil];
}

- (BOOL)spinUntilTrue:(FBRunLoopSpinnerBlock)untilTrue error:(NSError **)error
{
  NSDate *messageTimeout = [NSDate dateWithTimeIntervalSinceNow:self.reminderInterval];
  NSDate *timeoutDate = [NSDate dateWithTimeIntervalSinceNow:self.timeout];
  while (!untilTrue()) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    if (timeoutDate.timeIntervalSinceNow < 0) {
      if (self.timeoutErrorMessage) {
        NSString *message = (self.timeoutErrorMessage ?: @"FBRunLoopSpinner timeout");
        if (error) {
          *error = [NSError XCTestBootstrapErrorWithDescription:message];
        } else {
          NSLog(@"%@", message);
        }
      }
      return NO;
    }
    if (self.reminderMessage && messageTimeout.timeIntervalSinceNow < 0) {
      NSLog(@"%@", self.reminderMessage);
      messageTimeout = [NSDate dateWithTimeIntervalSinceNow:self.reminderInterval];
    }
  }
  return YES;
}

@end
