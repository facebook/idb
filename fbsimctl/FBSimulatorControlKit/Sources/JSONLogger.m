/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "JSONLogger.h"

#import <asl.h>

#import <FBSimulatorControlKit/FBSimulatorControlKit-Swift.h>

@interface JSONLogger ()

@property (nonatomic, strong, readonly) JSONEventReporter *reporter;
@property (nonatomic, assign, readonly) int32_t currentLevel;
@property (nonatomic, assign, readonly) int32_t maxLevel;
@property (nonatomic, assign, readonly) BOOL dispatchToMain;

@end

@implementation JSONLogger

#pragma mark Initializers

+ (instancetype)withEventReporter:(JSONEventReporter *)reporter debug:(BOOL)debug
{
  return [[self alloc] initWithEventReporter:reporter currentLevel:ASL_LEVEL_INFO maxLevel:(debug ? ASL_LEVEL_DEBUG : ASL_LEVEL_INFO) dispatchToMain:NO];
}

- (instancetype)initWithEventReporter:(JSONEventReporter *)reporter currentLevel:(int32_t)currentLevel maxLevel:(int32_t)maxLevel dispatchToMain:(BOOL)dispatchToMain;
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _reporter = reporter;
  _currentLevel = currentLevel;
  _maxLevel = maxLevel;
  _dispatchToMain = dispatchToMain;

  return self;
}

#pragma mark FBSimulatorLogger Interface

- (instancetype)log:(NSString *)string
{
  if (self.currentLevel > self.maxLevel) {
    return self;
  }

  LogEvent *event = [[LogEvent alloc] init:string level:self.currentLevel];
  if (self.dispatchToMain) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self.reporter reportLogBridge:event];
    });
  } else {
    [self.reporter reportLogBridge:event];
  }

  return self;
}

- (instancetype)logFormat:(NSString *)format, ...
{
  if (self.currentLevel > self.maxLevel) {
    return self;
  }

  va_list args;
  va_start(args, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  return [self log:string];
}

- (id<FBControlCoreLogger>)info
{
  return [[JSONLogger alloc] initWithEventReporter:self.reporter currentLevel:ASL_LEVEL_INFO maxLevel:self.maxLevel dispatchToMain:self.dispatchToMain];
}

- (id<FBControlCoreLogger>)debug
{
  return [[JSONLogger alloc] initWithEventReporter:self.reporter currentLevel:ASL_LEVEL_DEBUG maxLevel:self.maxLevel dispatchToMain:self.dispatchToMain];
}

- (id<FBControlCoreLogger>)error
{
  return [[JSONLogger alloc] initWithEventReporter:self.reporter currentLevel:ASL_LEVEL_ERR maxLevel:self.maxLevel dispatchToMain:self.dispatchToMain];
}

- (id<FBControlCoreLogger>)onQueue:(dispatch_queue_t)queue
{
  BOOL dispatchToMain = queue != dispatch_get_main_queue();
  return [[JSONLogger alloc] initWithEventReporter:self.reporter currentLevel:ASL_LEVEL_ERR maxLevel:self.maxLevel dispatchToMain:dispatchToMain];
}

- (id<FBControlCoreLogger>)withPrefix:(NSString *)prefix
{
  // Ignore prefixing as 'subject' will be included instead.
  return self;
}

@end
