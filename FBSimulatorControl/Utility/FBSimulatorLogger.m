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

static const char *FBASLClientDispatchLocal = "fbsimulatorcontrol_asl_client";

/**
 Manages asl client handles.
 */
@interface FBASLClientManager : NSObject

@property (nonatomic, assign, readonly) BOOL writeToStdErr;
@property (nonatomic, assign, readonly) BOOL debugLogging;

@end

@implementation FBASLClientManager

- (instancetype)initWithWritingToStderr:(BOOL)writeToStdErr debugLogging:(BOOL)debugLogging
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _writeToStdErr = writeToStdErr;
  _debugLogging = debugLogging;

  return self;
}

- (asl_object_t)clientHandleForQueue:(dispatch_queue_t)queue
{
  asl_object_t client = dispatch_queue_get_specific(queue, FBASLClientDispatchLocal);
  if (client) {
    return client;
  }

  client = asl_open("FBSimulatorControl", "com.facebook.fbsimulatorcontrol", 0);

  if (self.writeToStdErr) {
    int filterLimit = self.debugLogging ? ASL_FILTER_MASK_UPTO(ASL_LEVEL_DEBUG) : ASL_FILTER_MASK_UPTO(ASL_LEVEL_INFO);
    asl_add_output_file(client, STDERR_FILENO, ASL_MSG_FMT_STD, ASL_TIME_FMT_LCL, filterLimit, ASL_ENCODE_SAFE);
  } else {
    asl_remove_log_file(client, STDERR_FILENO);
  }

  dispatch_queue_set_specific(queue, FBASLClientDispatchLocal, client, (void *)(void *) asl_close);
  return client;
}

@end

@interface FBSimulatorLogger_ASL : NSObject <FBSimulatorLogger>

@property (nonatomic, strong, readonly) FBASLClientManager *clientManager;
@property (nonatomic, assign, readonly) asl_object_t client;
@property (nonatomic, assign, readonly) int currentLevel;

@end

@implementation FBSimulatorLogger_ASL

- (instancetype)initWithClientManager:(FBASLClientManager *)clientManager client:(asl_object_t)client currentLevel:(int)currentLevel
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _clientManager = clientManager;
  _client = client;
  _currentLevel = currentLevel;

  return self;
}

- (id<FBSimulatorLogger>)log:(NSString *)string
{
  asl_log(self.client, NULL, self.currentLevel, "%s", string.UTF8String);
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
  return [[FBSimulatorLogger_ASL alloc] initWithClientManager:self.clientManager client:self.client currentLevel:ASL_LEVEL_INFO];
}

- (id<FBSimulatorLogger>)debug
{
  return [[FBSimulatorLogger_ASL alloc] initWithClientManager:self.clientManager client:self.client currentLevel:ASL_LEVEL_DEBUG];
}

- (id<FBSimulatorLogger>)error
{
  return [[FBSimulatorLogger_ASL alloc] initWithClientManager:self.clientManager client:self.client currentLevel:ASL_LEVEL_ERR];
}

- (id<FBSimulatorLogger>)onQueue:(dispatch_queue_t)queue
{
  asl_object_t client = [self.clientManager clientHandleForQueue:queue];
  return [[FBSimulatorLogger_ASL alloc] initWithClientManager:self.clientManager client:client currentLevel:self.currentLevel];
}

@end

@implementation FBSimulatorLogger

+ (id<FBSimulatorLogger>)aslLoggerWritingToStderrr:(BOOL)writeToStdErr withDebugLogging:(BOOL)debugLogging
{
  static dispatch_once_t onceToken;
  static FBSimulatorLogger_ASL *logger;
  dispatch_once(&onceToken, ^{
    FBASLClientManager *clientManager = [[FBASLClientManager alloc] initWithWritingToStderr:writeToStdErr debugLogging:debugLogging];
    asl_object_t client = [clientManager clientHandleForQueue:dispatch_get_main_queue()];
    logger = [[FBSimulatorLogger_ASL alloc] initWithClientManager:clientManager client:client currentLevel:ASL_LEVEL_INFO];
  });
  return logger;
}

@end
