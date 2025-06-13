/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBIDBEmbeddedServer.h"
#import "FBIDBCommandExecutor.h"
#import "Utility/FBIDBStorageManager.h"
#import "Utility/FBIDBLogger.h"
#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorControl.h>

@implementation FBIDBEmbeddedServer {
  FBIDBStorageManager *_storageManager;
  FBTemporaryDirectory *_temporaryDirectory;
  id<FBEventReporter> _reporter;
}

#pragma mark - Initialization

+ (nullable instancetype)embeddedServerWithTarget:(id<FBiOSTarget>)target
                                           logger:(id<FBControlCoreLogger>)logger
                                            error:(NSError **)error
{
  FBIDBEmbeddedServer *server = [[self alloc] initWithTarget:target logger:logger error:error];
  return server;
}

- (nullable instancetype)initWithTarget:(id<FBiOSTarget>)target
                                 logger:(id<FBControlCoreLogger>)logger
                                  error:(NSError **)error
{
  self = [super init];
  if (!self) {
    return nil;
  }
  
  _embeddedMode = YES;
  _target = target;
  _temporaryDirectory = [FBTemporaryDirectory temporaryDirectoryWithLogger:logger];
  _reporter = nil; // Event reporting disabled in embedded mode
  
  // Initialize storage manager
  _storageManager = [FBIDBStorageManager managerForTarget:target logger:logger error:error];
  if (!_storageManager) {
    return nil;
  }
  
  // Create command executor - using port 0 to indicate no debug server
  _commandExecutor = [FBIDBCommandExecutor commandExecutorForTarget:target
                                                    storageManager:_storageManager
                                                 temporaryDirectory:_temporaryDirectory
                                                   debugserverPort:0
                                                            logger:logger];
  
  [logger logFormat:@"Initialized FBIDBEmbeddedServer for target: %@", target.udid];
  
  return self;
}

#pragma mark - Server Control

- (BOOL)startWithError:(NSError **)error
{
  // In embedded mode, we don't bind to any ports or set up signal handlers
  // Just verify our components are ready
  if (!self.target || !self.commandExecutor) {
    if (error) {
      *error = [FBControlCoreError errorForDescription:@"Embedded server not properly initialized"];
    }
    return NO;
  }
  
  if (_reporter) {
    [_reporter report:[FBEventReporterSubject subjectForEvent:@"embedded_server_started"]];
  }
  return YES;
}

- (void)shutdown
{
  if (_reporter) {
    [_reporter report:[FBEventReporterSubject subjectForEvent:@"embedded_server_shutdown"]];
  }
  [_temporaryDirectory cleanOnExit];
  _commandExecutor = nil;
  _storageManager = nil;
}

@end