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

@property (nonatomic, assign, readonly) int fileDescriptor;
@property (nonatomic, assign, readonly) BOOL debugLogging;

@end

@implementation FBASLClientManager

- (instancetype)initWithWritingToFileDescriptor:(int)fileDescriptor debugLogging:(BOOL)debugLogging
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _fileDescriptor = fileDescriptor;
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
  int filterLimit = self.debugLogging ? ASL_FILTER_MASK_UPTO(ASL_LEVEL_DEBUG) : ASL_FILTER_MASK_UPTO(ASL_LEVEL_INFO);

  if (self.fileDescriptor >= STDIN_FILENO) {
    asl_add_output_file(client, self.fileDescriptor, ASL_MSG_FMT_STD, ASL_TIME_FMT_LCL, filterLimit, ASL_ENCODE_SAFE);
  } else {
    asl_remove_log_file(client, self.fileDescriptor);
  }

  dispatch_queue_set_specific(queue, FBASLClientDispatchLocal,  client, (void *)(void *) asl_close);
  return client;
}

@end

@interface FBSimulatorLogger_ASL : NSObject <FBSimulatorLogger>

@property (nonatomic, strong, readonly) FBASLClientManager *clientManager;
@property (nonatomic, assign, readonly) asl_object_t client;
@property (nonatomic, assign, readonly) int currentLevel;
@property (nonatomic, copy, readonly) NSString *prefix;

@end

@implementation FBSimulatorLogger_ASL

- (instancetype)initWithClientManager:(FBASLClientManager *)clientManager client:(asl_object_t)client currentLevel:(int)currentLevel prefix:(NSString *)prefix
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _clientManager = clientManager;
  _client = client;
  _currentLevel = currentLevel;
  _prefix = prefix;

  return self;
}

- (id<FBSimulatorLogger>)log:(NSString *)string
{
  string = self.prefix ? [self.prefix stringByAppendingFormat:@" %@", string] : string;
  asl_log(self.client, NULL, self.currentLevel, string.UTF8String, NULL);
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
  return [[FBSimulatorLogger_ASL alloc] initWithClientManager:self.clientManager client:self.client currentLevel:ASL_LEVEL_INFO prefix:self.prefix];
}

- (id<FBSimulatorLogger>)debug
{
  return [[FBSimulatorLogger_ASL alloc] initWithClientManager:self.clientManager client:self.client currentLevel:ASL_LEVEL_DEBUG prefix:self.prefix];
}

- (id<FBSimulatorLogger>)error
{
  return [[FBSimulatorLogger_ASL alloc] initWithClientManager:self.clientManager client:self.client currentLevel:ASL_LEVEL_ERR prefix:self.prefix];
}

- (id<FBSimulatorLogger>)onQueue:(dispatch_queue_t)queue
{
  asl_object_t client = [self.clientManager clientHandleForQueue:queue];
  return [[FBSimulatorLogger_ASL alloc] initWithClientManager:self.clientManager client:client currentLevel:self.currentLevel prefix:self.prefix];
}

- (id<FBSimulatorLogger>)withPrefix:(NSString *)prefix
{
  return [[FBSimulatorLogger_ASL alloc] initWithClientManager:self.clientManager client:self.client currentLevel:self.currentLevel prefix:prefix];
}

@end

@implementation FBSimulatorLogger

+ (id<FBSimulatorLogger>)aslLoggerWritingToStderrr:(BOOL)writeToStdErr withDebugLogging:(BOOL)debugLogging
{
  int fileDescriptor = writeToStdErr ? STDERR_FILENO : 0;
  return [self aslLoggerWritingToFileDescriptor:fileDescriptor withDebugLogging:debugLogging];
}

+ (id<FBSimulatorLogger>)aslLoggerWritingToFileDescriptor:(int)fileDescriptor withDebugLogging:(BOOL)debugLogging
{
  FBASLClientManager *clientManager = [[FBASLClientManager alloc] initWithWritingToFileDescriptor:fileDescriptor debugLogging:debugLogging];
  asl_object_t client = [clientManager clientHandleForQueue:dispatch_get_main_queue()];
  FBSimulatorLogger_ASL *logger = [[FBSimulatorLogger_ASL alloc] initWithClientManager:clientManager client:client currentLevel:ASL_LEVEL_INFO prefix:nil];
  return logger;
}

@end
