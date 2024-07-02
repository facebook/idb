/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceDebugSymbolsCommands.h"

#import <dlfcn.h>

#import "FBDevice.h"
#import "FBAMDServiceConnection.h"
#import "FBDeviceControlError.h"

// This signature for this function is shown in the OSS release of dyld (ex: https://opensource.apple.com/source/dyld/dyld-433.5/launch-cache/dsc_extractor.cpp.auto.html)
typedef int (*SharedCacheExtractor)(const char *sharedCachePath, const char *extractionRootDirectory, void (^progressCallback)(int current, int total));

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
static const uint32_t GetFileCommand = 0x01000000;
static const uint32_t GetFileAck = GetFileCommand;

- (FBFuture<NSArray<NSString *> *> *)listSymbols
{
  return [self fetchRemoteSymbolListing];
}

- (FBFuture<NSString *> *)pullSymbolFile:(NSString *)fileName toDestinationPath:(NSString *)destinationPath
{
  return [[self
    indexOfSymbolFile:fileName]
    onQueue:self.device.asyncQueue fmap:^(NSNumber *indexNumber) {
      uint32_t index = indexNumber.unsignedIntValue;
      return [self writeSymbolFileWithIndex:index toFileAtPath:destinationPath];
    }];
}

- (FBFuture<NSString *> *)pullAndExtractSymbolsToDestinationDirectory:(NSString *)destinationDirectory
{
  NSError *error = nil;
  if (![NSFileManager.defaultManager createDirectoryAtPath:destinationDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to create destination directory for symbol extraction: %@", error]
      failFuture];
  }
  id<FBControlCoreLogger> logger = self.device.logger;
  return [[[self
    indicesAndRemotePathsOfSharedCache]
    onQueue:self.device.asyncQueue fmap:^(NSDictionary<NSNumber *, NSString *> *indicesToRemotePaths) {
      NSMutableDictionary<NSNumber *, NSString *> *indicesToLocalPaths = NSMutableDictionary.dictionary;
      for (NSNumber *fileIndex in indicesToRemotePaths.allKeys) {
        NSString *localFileName = indicesToRemotePaths[fileIndex].lastPathComponent;
        indicesToLocalPaths[fileIndex] = [destinationDirectory stringByAppendingPathComponent:localFileName];
      }
      [logger logFormat:@"Extracting remote symbols %@", [FBCollectionInformation oneLineDescriptionFromArray:indicesToRemotePaths.allValues]];
      return [self extractSymbolFilesWithIndicesMap:indicesToLocalPaths extractedPaths:@[]];
    }]
    onQueue:self.device.asyncQueue fmap:^(NSArray<NSString *> *extractedSymbolFiles) {
      NSError *innerError = nil;
      NSString *sharedCachePath = [FBDeviceDebugSymbolsCommands extractSharedCachePathFromPaths:extractedSymbolFiles error:&innerError];
      if (!sharedCachePath) {
        return [FBFuture futureWithError:innerError];
      }
      if (![FBDeviceDebugSymbolsCommands extractSharedCacheFile:sharedCachePath toDestinationDirectory:destinationDirectory logger:self.device.logger error:&innerError]) {
        return [FBFuture futureWithError:innerError];
      }
      for (NSString *extractedSymbolFile in extractedSymbolFiles) {
        [NSFileManager.defaultManager removeItemAtPath:extractedSymbolFile error:nil];
      }
      return [FBFuture futureWithResult:destinationDirectory];
    }];
}

#pragma mark Private

- (FBFuture<NSArray<NSString *> *> *)extractSymbolFilesWithIndicesMap:(NSDictionary<NSNumber *, NSString *> *)indicesToName extractedPaths:(NSArray<NSString *> *)extractedPaths
{
  if (indicesToName.count == 0) {
    return [FBFuture futureWithResult:extractedPaths];
  }
  NSNumber *nextIndexNumber = [indicesToName.allKeys firstObject];
  NSString *nextPath = indicesToName[nextIndexNumber];
  NSMutableDictionary<NSNumber *, NSString *> *nextIndicesToName = [indicesToName mutableCopy];
  [nextIndicesToName removeObjectForKey:nextIndexNumber];
  uint32_t nextIndex = nextIndexNumber.unsignedIntValue;
  return [[self
    writeSymbolFileWithIndex:nextIndex toFileAtPath:nextPath]
    onQueue:self.device.asyncQueue fmap:^(NSString *extractedPath) {
      NSMutableArray<NSString *> *nextExtractedPaths = [extractedPaths mutableCopy];
      [nextExtractedPaths addObject:extractedPath];
      return [self extractSymbolFilesWithIndicesMap:nextIndicesToName extractedPaths:nextExtractedPaths];
    }];
}

- (FBFuture<NSDictionary<NSNumber *, NSString *> *> *)indicesAndRemotePathsOfSharedCache
{
  return [[self
    symbolServiceConnection]
    onQueue:self.device.asyncQueue pop:^(FBAMDServiceConnection *connection) {
      NSError *error = nil;
      NSArray<NSString *> *files = [FBDeviceDebugSymbolsCommands obtainFileListingFromService:connection error:&error];
      if (!files) {
        return [FBFuture futureWithError:error];
      }
      NSArray<NSString *> *matchingFiles = [FBDeviceDebugSymbolsCommands matchingPathsOfSharedCache:files];
      NSDictionary<NSNumber *, NSString *> *indicesToFile = [FBDeviceDebugSymbolsCommands matchFiles:matchingFiles againstFileIndices:files error:&error];
      if (!indicesToFile) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:indicesToFile];
    }];
}

- (FBFuture<NSNumber *> *)indexOfSymbolFile:(NSString *)fileName
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
      return [FBFuture futureWithResult:@(index)];
    }];
}

- (FBFuture<NSString *> *)writeSymbolFileWithIndex:(uint32_t)index toFileAtPath:(NSString *)destinationPath
{
  return [[self
    symbolServiceConnection]
    onQueue:self.device.asyncQueue pop:^(FBAMDServiceConnection *connection) {
      NSError *error = nil;
      if(![FBDeviceDebugSymbolsCommands getFileWithIndex:index toDestinationPath:destinationPath onConnection:connection error:&error]) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:destinationPath];
    }];
}

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
  if (![FBDeviceDebugSymbolsCommands sendCommand:ListFilesPlistCommand withAck:ListFilesPlistAck commandName:@"ListFilesPlist" onConnection:connection error:error]) {
    return nil;
  }
  NSError *innerError = nil;
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
      describeFormat:@"Failed to send '%@' command to symbol service %@", commandName, innerError]
      failBool:error];
  }
  uint32_t response = 0;
  success = [connection receiveUnsignedInt32:&response error:&innerError];
  if (!success) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to recieve '%@' response from %@", commandName, innerError]
      failBool:error];
  }
  if (response != ack) {
    return [[FBDeviceControlError
      describeFormat:@"Incorrect '%@' ack from symbol service; got %u expected %u", commandName, response, ack]
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
  uint32_t indexWire = OSSwapHostToBigInt32(index);
  if (![connection sendUnsignedInt32:indexWire error:&innerError]) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to send GetFile file index %u packet %@", index, innerError]
      failBool:error];
  }
  uint64_t recieveLengthWire = 0;
  if (![connection receiveUnsignedInt64:&recieveLengthWire error:&innerError]) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to recieve GetFile file length %@", innerError]
      failBool:error];
  }
  if (recieveLengthWire == 0) {
    return [[FBDeviceControlError
      describe:@"Failed to get file length, recieveLength not returned or is zero."]
      failBool:error];
  }
  uint64_t recieveLength = OSSwapBigToHostInt64(recieveLengthWire);
  if (![NSFileManager.defaultManager createFileAtPath:destinationPath contents:nil attributes:nil]) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to create destination file at path %@", destinationPath]
      failBool:error];
  }
  NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:destinationPath];
  if (!fileHandle) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to open file for writing at %@", destinationPath]
      failBool:error];
  }
  if (![connection receive:recieveLength toFile:fileHandle error:error]) {
    return NO;
  }
  return YES;
}

+ (BOOL)extractSharedCacheFile:(NSString *)sharedCacheFile toDestinationDirectory:(NSString *)destinationDirectory logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  SharedCacheExtractor extractor = [self getSharedCacheExtractorWithError:error];
  if (!extractor) {
    return NO;
  }
  [logger logFormat:@"Extracting shared cache at %@ to directory at %@", sharedCacheFile, destinationDirectory];
  int status = extractor(sharedCacheFile.UTF8String, destinationDirectory.UTF8String, ^(int completed, int total){
    [logger logFormat:@"Completed %d Total %d", completed, total];
  });
  if (status != 0) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to get extract shared cache directory %@ to %@ with status %d", sharedCacheFile, destinationDirectory, status]
      failBool:error];
  }
  [logger logFormat:@"Shared cache extracted to %@", destinationDirectory];
  return YES;
}

+ (SharedCacheExtractor)getSharedCacheExtractorWithError:(NSError **)error
{
  NSString *path = [self pathForSharedCacheExtractor:error];
  if (!path) {
    return NULL;
  }
  void *handle = dlopen(path.UTF8String, RTLD_LAZY);
  if (!handle) {
    return [[FBControlCoreError
      describeFormat:@"Failed to dlopen() %@", path]
      failPointer:error];
  }
  return FBGetSymbolFromHandle(handle, "dyld_shared_cache_extract_dylibs_progress");
}

+ (NSString *)pathForSharedCacheExtractor:(NSError **)error
{
  NSString *path = [FBXcodeConfiguration.developerDirectory stringByAppendingPathComponent:@"Platforms/iPhoneOS.platform/usr/lib/dsc_extractor.bundle"];
  if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
    return [[FBDeviceControlError
      describeFormat:@"Expected dyld_shared_cache extractor library was not found at path %@", path]
      fail:error];
  }
  return path;
}

+ (NSArray<NSString *> *)matchingPathsOfSharedCache:(NSArray<NSString *> *)files
{
  NSMutableArray<NSString *> *matchingFiles = NSMutableArray.array;
  for (NSString *file in files) {
    if (![file hasPrefix:@"/System/Library"]) {
      continue;
    }
    if (![file containsString:@"shared_cache"]) {
      continue;
    }
    [matchingFiles addObject:file];
  }
  return matchingFiles;
}

+ (NSDictionary<NSNumber *, NSString *> *)matchFiles:(NSArray<NSString *> *)files againstFileIndices:(NSArray<NSString *> *)fileIndices error:(NSError **)error
{
  NSMutableDictionary<NSNumber *, NSString *> *indexToFileName = NSMutableDictionary.dictionary;
  for (NSString *file in files) {
    NSUInteger index = [fileIndices indexOfObject:file];
    if (index == NSNotFound) {
      return [[FBDeviceControlError
        describeFormat:@"Could not find %@ within %@", file, [FBCollectionInformation oneLineDescriptionFromArray:fileIndices]]
        fail:error];
    }
    indexToFileName[@(index)] = file;
  }
  return indexToFileName;
}

+ (NSString *)extractSharedCachePathFromPaths:(NSArray<NSString *> *)paths error:(NSError **)error
{
  for (NSString *path in paths) {
    if ([path.pathExtension isEqualToString:@""]) {
      return path;
    }
  }
  return [[FBDeviceControlError
    describeFormat:@"Could not find the shared cache file within %@", [FBCollectionInformation oneLineDescriptionFromArray:paths]]
    fail:error];
}
  
@end
