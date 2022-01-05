/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceDebugSymbolsCommands.h"

#import "FBDevice.h"
#import "FBAMDServiceConnection.h"
#import "FBDeviceControlError.h"

@interface FBDeviceDebugSymbolsCommands ()

@property (nonatomic, weak, readonly) FBDevice *device;
@property (nonatomic, copy, nullable, readwrite) NSArray<NSString *> *cachedFileListing;

@end

@implementation FBDeviceDebugSymbolsCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(FBDevice *)target
{
  return [[self alloc] initWithDevice:target];
}

- (instancetype)initWithDevice:(FBDevice *)device
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;

  return self;
}

#pragma mark FBDeviceActivationCommands Implementation

static const uint32_t ListFilesPlistCommand = 0x30303030;
static const uint32_t ListFilesPlistAck = ListFilesPlistCommand;
static const uint32_t GetFileCommand = 1;
static const uint32_t GetFileAck = GetFileCommand;

- (FBFuture<NSArray<NSString *> *> *)listSymbols
{
  return [self fetchRemoteSymbolListing];
}

- (FBFuture<NSString *> *)pullSymbolFile:(NSString *)fileName toDestinationPath:(NSString *)destinationPath
{
  return [[self
    symbolServiceConnection]
    onQueue:self.device.asyncQueue pop:^(FBAMDServiceConnection *connection) {
      NSError *error = nil;
      NSArray<NSString *> *files = [FBDeviceDebugSymbolsCommands obtainFileListingFromService:connection error:&error];
      if (!files) {
        return [FBFuture futureWithError:error];
      }
      NSUInteger index = [files indexOfObject:fileName];
      if (index == NSNotFound) {
        return [[FBDeviceControlError
          describeFormat:@"Could not find %@ within %@", fileName, [FBCollectionInformation oneLineDescriptionFromArray:files]]
          failFuture];
      }
      if (![FBDeviceDebugSymbolsCommands getFileWithIndex:(uint32_t)index toDestinationPath:destinationPath onConnection:connection error:&error]) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:destinationPath];
    }];
}

#pragma mark Private

- (FBFutureContext<FBAMDServiceConnection *> *)symbolServiceConnection
{
  return [[self.device
    ensureDeveloperDiskImageIsMounted]
    onQueue:self.device.workQueue pushTeardown:^(FBDeveloperDiskImage *image) {
      return [self.device startService:@"com.apple.dt.fetchsymbols"];
    }];
}

- (FBFuture<NSArray<NSString *> *> *)fetchRemoteSymbolListing
{
  return [[self
    symbolServiceConnection]
    onQueue:self.device.asyncQueue pop:^(FBAMDServiceConnection *connection) {
      NSError *error = nil;
      NSArray<NSString *> *files = [FBDeviceDebugSymbolsCommands obtainFileListingFromService:connection error:&error];
      if (!files) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:files];
    }];
}

+ (NSArray<NSString *> *)obtainFileListingFromService:(FBAMDServiceConnection *)connection error:(NSError **)error
{
  NSError *innerError = nil;
  if (![FBDeviceDebugSymbolsCommands sendCommand:ListFilesPlistCommand withAck:ListFilesPlistAck commandName:@"ListFilesPlist" onConnection:connection error:&innerError]) {
    if (error) {
      *error = innerError;
    }
    return nil;
  }
  NSDictionary<NSString *, id> *message = [connection receiveMessageWithError:&innerError];
  if (!message) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to recieve ListFiles plist message %@", innerError]
      fail:error];
  }
  NSArray<NSString *> *files = message[@"files"];
  if (![FBCollectionInformation isArrayHeterogeneous:files withClass:NSString.class]) {
    return [[FBDeviceControlError
      describeFormat:@"ListFilesPlist expected Array<String> for 'files' but got %@", [FBCollectionInformation oneLineDescriptionFromArray:files]]
      fail:error];
  }
  return files;
}

+ (BOOL)sendCommand:(uint32_t)command withAck:(uint32_t)ack commandName:(NSString *)commandName onConnection:(FBAMDServiceConnection *)connection error:(NSError **)error
{
  NSError *innerError = nil;
  BOOL success = [connection sendUnsignedInt32:command error:&innerError];
  if (!success) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to send %@ command to symbol service %@", commandName, innerError]
      failBool:error];
  }
  uint32_t response = 1;
  success = [connection receiveUnsignedInt32:&response error:&innerError];
  if (!success) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to recieve %@ command to symbol service %@", commandName, innerError]
      failBool:error];
  }
  if (response != ack) {
    return [[FBDeviceControlError
      describeFormat:@"Incorrect %@ ack from symbol service got %d expected %d", commandName, response, ListFilesPlistAck]
      failBool:error];
  }
  return YES;
}

+ (BOOL)getFileWithIndex:(uint32_t)index toDestinationPath:(NSString *)destinationPath onConnection:(FBAMDServiceConnection *)connection error:(NSError **)error
{
  // Send the command that we want to get a file
  if (![FBDeviceDebugSymbolsCommands sendCommand:GetFileCommand withAck:GetFileAck commandName:@"GetFiles" onConnection:connection error:error]) {
    return NO;
  }
  // Send the index of the file to pull back
  NSError *innerError = nil;
  if (![connection sendUnsignedInt32:(uint32_t) index error:&innerError]) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to recieve GetFiles plist message %@", innerError]
      failBool:error];
  }
  uint64_t recieveLength = 0;
  if (![connection receiveUnsignedInt64:&recieveLength error:&innerError]) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to get file length %@", innerError]
      failBool:error];
  }
  if (recieveLength == 0) {
    return [[FBDeviceControlError
      describe:@"Failed to get file length, recieveLength not returned"]
      failBool:error];
  }
  NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:destinationPath];
  if (!fileHandle) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to open file for reading at %@", destinationPath]
      failBool:error];
  }
  if (![connection receive:recieveLength toFile:fileHandle error:error]) {
    return NO;
  }
  return YES;
}
  
@end
