/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "Bridging.h"

#import <asl.h>

#import <FBSimulatorControlKit/FBSimulatorControlKit-Swift.h>

#import <sys/socket.h>

@implementation Constants

+ (int32_t)sol_socket
{
  return SOL_SOCKET;
}

+ (int32_t)so_reuseaddr
{
  return SO_REUSEADDR;
}

+ (int32_t)asl_level_info
{
  return ASL_LEVEL_INFO;
}

+ (int32_t)asl_level_debug
{
  return ASL_LEVEL_DEBUG;
}

+ (int32_t)asl_level_err
{
  return ASL_LEVEL_ERR;
}

@end

@implementation NSString (FBJSONSerializable)

- (id)jsonSerializableRepresentation
{
  return self;
}

@end

@implementation NSArray (FBJSONSerializable)

- (id)jsonSerializableRepresentation
{
  return self;
}

@end

@interface LogReporter ()

@property (nonatomic, strong, readonly, nonnull) ControlCoreLoggerBridge *bridge;
@property (nonatomic, assign, readonly) int32_t currentLevel;
@property (nonatomic, assign, readonly) int32_t maxLevel;
@property (nonatomic, assign, readonly) BOOL dispatchToMain;

@end

@implementation LogReporter

#pragma mark Initializers

- (instancetype)initWithBridge:(ControlCoreLoggerBridge *)bridge debug:(BOOL)debug
{
  return [self initWithBridge:bridge currentLevel:ASL_LEVEL_INFO maxLevel:(debug ? ASL_LEVEL_DEBUG : ASL_LEVEL_INFO) dispatchToMain:NO];
}

- (instancetype)initWithBridge:(ControlCoreLoggerBridge *)bridge currentLevel:(int32_t)currentLevel maxLevel:(int32_t)maxLevel dispatchToMain:(BOOL)dispatchToMain;
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _bridge = bridge;
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

  if (self.dispatchToMain) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self.bridge log:self.currentLevel string:string];
    });
  } else {
    [self.bridge log:self.currentLevel string:string];
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
  return [[LogReporter alloc] initWithBridge:self.bridge currentLevel:ASL_LEVEL_INFO maxLevel:self.maxLevel dispatchToMain:self.dispatchToMain];
}

- (id<FBControlCoreLogger>)debug
{
  return [[LogReporter alloc] initWithBridge:self.bridge currentLevel:ASL_LEVEL_DEBUG maxLevel:self.maxLevel dispatchToMain:self.dispatchToMain];
}

- (id<FBControlCoreLogger>)error
{
  return [[LogReporter alloc] initWithBridge:self.bridge currentLevel:ASL_LEVEL_ERR maxLevel:self.maxLevel dispatchToMain:self.dispatchToMain];
}

- (id<FBControlCoreLogger>)onQueue:(dispatch_queue_t)queue
{
  BOOL dispatchToMain = queue != dispatch_get_main_queue();
  return [[LogReporter alloc] initWithBridge:self.bridge currentLevel:ASL_LEVEL_ERR maxLevel:self.maxLevel dispatchToMain:dispatchToMain];
}

- (id<FBControlCoreLogger>)withPrefix:(NSString *)prefix
{
  // Ignore prefixing as 'subject' will be included instead.
  return self;
}

@end
