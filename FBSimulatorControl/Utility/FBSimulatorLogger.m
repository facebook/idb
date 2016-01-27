/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorLogger.h"

#import <asl.h>

/**
 Wraps asl_object_t in an NSObject, so that is becomes reference-counted
 */
@interface FBASLContainer : NSObject

@property (nonatomic, assign, readonly) asl_object_t asl;

@end

@implementation FBASLContainer

- (instancetype)initWithASLObject:(asl_object_t)asl
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _asl = asl;
  return self;
}

- (void)dealloc
{
  asl_close(_asl);
  _asl = NULL;
}

@end

@interface FBSimulatorLogger_ASL : NSObject <FBSimulatorLogger>

@property (nonatomic, strong, readonly) FBASLContainer *aslContainer;
@property (nonatomic, assign, readonly) int currentLevel;

@end

@implementation FBSimulatorLogger_ASL

- (instancetype)initWithASLClient:(FBASLContainer *)aslContainer currentLevel:(int)currentLevel
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _aslContainer = aslContainer;
  _currentLevel = currentLevel;

  return self;
}

- (id<FBSimulatorLogger>)log:(NSString *)string
{
  asl_log(self.aslContainer.asl, NULL, self.currentLevel, "%s", string.UTF8String);
  return self;
}

- (id<FBSimulatorLogger>)logFormat:(NSString *)format, ...
{
  va_list args;
  va_start(args, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  return [self log:string];
}

- (id<FBSimulatorLogger>)info
{
  return [[FBSimulatorLogger_ASL alloc] initWithASLClient:self.aslContainer currentLevel:ASL_LEVEL_INFO];
}

- (id<FBSimulatorLogger>)debug
{
  return [[FBSimulatorLogger_ASL alloc] initWithASLClient:self.aslContainer currentLevel:ASL_LEVEL_DEBUG];
}

- (id<FBSimulatorLogger>)error
{
  return [[FBSimulatorLogger_ASL alloc] initWithASLClient:self.aslContainer currentLevel:ASL_LEVEL_ERR];
}

- (instancetype)writingToStderrr:(BOOL)writeToStdErr withDebugLogging:(BOOL)debugLogging
{
  if (writeToStdErr) {
    int filterLimit = debugLogging ? ASL_FILTER_MASK_UPTO(ASL_LEVEL_DEBUG) : ASL_FILTER_MASK_UPTO(ASL_LEVEL_INFO);
    asl_add_output_file(self.aslContainer.asl, STDERR_FILENO, ASL_MSG_FMT_STD, ASL_TIME_FMT_LCL, filterLimit, ASL_ENCODE_SAFE);
  } else {
    asl_remove_log_file(self.aslContainer.asl, STDERR_FILENO);
  }
  return self;
}

@end

@implementation FBSimulatorLogger

+ (id<FBSimulatorLogger>)aslLoggerWritingToStderrr:(BOOL)writeToStdErr withDebugLogging:(BOOL)debugLogging
{
  static dispatch_once_t onceToken;
  static FBSimulatorLogger_ASL *logger;
  dispatch_once(&onceToken, ^{
    asl_object_t asl = asl_open("FBSimulatorControl", "com.facebook.fbsimulatorcontrol", 0);
    FBASLContainer *aslContainer = [[FBASLContainer alloc] initWithASLObject:asl];
    logger = [[[FBSimulatorLogger_ASL alloc] initWithASLClient:aslContainer currentLevel:ASL_LEVEL_INFO] writingToStderrr:writeToStdErr withDebugLogging:debugLogging];
  });
  return logger;
}

@end
