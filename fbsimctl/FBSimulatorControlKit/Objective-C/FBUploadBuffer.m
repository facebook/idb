/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBUploadBuffer.h"

FBiOSTargetFutureType const FBiOSTargetFutureTypeBinaryTransfer = @"transfer";
FBiOSTargetFutureType const FBiOSTargetFutureTypeUploadedBinary = @"uploaded";

@implementation FBUploadHeader

#pragma mark Initializers

+ (instancetype)headerWithPathExtension:(NSString *)extension size:(size_t)size
{
  return [[self alloc] initWithPathExtension:extension size:size];
}

- (instancetype)initWithPathExtension:(NSString *)extension size:(size_t)size
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _extension = extension;
  _size = size;

  return self;
}

static NSString *const KeyExtension = @"extension";
static NSString *const KeySize = @"size";

#pragma mark JSON

+ (nullable instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a Dictionary<String, Any>", json]
      fail:error];
  }
  NSString *pathExtension = json[KeyExtension];
  if (![pathExtension isKindOfClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a String for %@", pathExtension, KeyExtension]
      fail:error];
  }
  NSNumber *sizeNumber = json[KeySize];
  if (![sizeNumber isKindOfClass:NSNumber.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a Number for %@", sizeNumber, KeySize]
      fail:error];
  }
  return [[FBUploadHeader alloc] initWithPathExtension:pathExtension size:sizeNumber.unsignedLongValue];
}

- (id)jsonSerializableRepresentation
{
  return @{
    KeyExtension: self.extension,
    KeySize: @(self.size),
  };
}

- (instancetype)copyWithZone:(NSZone *)zone
{
  // Is Immutable
  return self;
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return self.extension.hash ^ self.size;
}

- (BOOL)isEqual:(FBUploadHeader *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return ([self.extension isEqualToString:object.extension])
      && (self.size == object.size);
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Upload of Size %zu bytes, Extension %@",
    self.size,
    self.extension
  ];
}

#pragma mark FBiOSTargetFuture

+ (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeBinaryTransfer;
}

- (FBFuture<id<FBiOSTargetContinuation>> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBDataConsumer>)consumer reporter:(id<FBEventReporter>)reporter
{
  return [FBFuture futureWithResult:FBiOSTargetContinuationDone(self.class.futureType)];
}

@end

@implementation FBUploadedDestination

#pragma mark Initializers

+ (instancetype)destinationWithHeader:(FBUploadHeader *)header path:(NSString *)path
{
  return [[self alloc] initWithHeader:header path:path];
}

- (instancetype)initWithHeader:(FBUploadHeader *)header path:(NSString *)path
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _header = header;
  _path = path;

  return self;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
  // Is Immutable
  return self;
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return self.header.hash ^ self.path.hash;
}

- (BOOL)isEqual:(FBUploadedDestination *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return ([self.header isEqual:object.header])
      && ([self.path isEqualToString:object.path]);
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Uploaded of %@ to %@",
    self.header.description,
    self.path
  ];
}

#pragma mark Properties

- (NSData *)data
{
  return [NSData dataWithContentsOfFile:self.path];
}

#pragma mark JSON

static NSString *const KeyHeader = @"header";
static NSString *const KeyPath = @"path";

+ (nullable instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a Dictionary<String, Any>", json]
      fail:error];
  }
  NSDictionary<NSString *, id> *headerDictionary = json[KeyHeader];
  if (![FBCollectionInformation isDictionaryHeterogeneous:headerDictionary keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a Dictionary<String, Any> for %@", json, KeyHeader]
      fail:error];
  }
  FBUploadHeader *header = [FBUploadHeader inflateFromJSON:headerDictionary error:error];
  if (!header) {
    return nil;
  }
  NSString *path = json[KeyPath];
  if (![path isKindOfClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a String for %@", path, KeyPath]
      fail:error];
  }
  return [self destinationWithHeader:header path:path];
}

- (id)jsonSerializableRepresentation
{
  return @{
    KeyHeader: self.header.jsonSerializableRepresentation,
    KeyPath: self.path,
  };
}

#pragma mark FBiOSTargetFuture

+ (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeUploadedBinary;
}

- (FBFuture<id<FBiOSTargetContinuation>> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBDataConsumer>)consumer reporter:(id<FBEventReporter>)reporter
{
  return [FBFuture futureWithResult:FBiOSTargetContinuationDone(self.class.futureType)];
}

@end

@interface FBUploadBuffer ()

@property (nonatomic, copy, readonly) FBUploadHeader *header;
@property (nonatomic, copy, readonly) NSString *filePath;

@property (nonatomic, strong, readwrite, nullable) FBUploadedDestination *binary;
@property (nonatomic, assign, readwrite) size_t position;

@end

@interface FBUploadBuffer_InMemory : FBUploadBuffer

@property (nonatomic, strong, readwrite, nullable) NSMutableData *data;

@end

@interface FBUploadBuffer_ToFile : FBUploadBuffer

@property (nonatomic, strong, readwrite, nullable) id<FBDataConsumer> writer;

- (instancetype)initWithHeader:(FBUploadHeader *)header filePath:(NSString *)filePath writer:(id<FBDataConsumer>)writer;

@end

@implementation FBUploadBuffer

#pragma mark Initializers

static size_t ToFileThreshold = 2 * 1024 * 1024;

+ (NSString *)outputFilePathWithWorkingDirectory:(NSString *)workingDirectory pathExtension:(NSString *)pathExtension
{
  return [[workingDirectory stringByAppendingPathComponent:NSUUID.UUID.UUIDString] stringByAppendingPathExtension:pathExtension];
}

+ (nullable)bufferWithHeader:(FBUploadHeader *)header workingDirectory:(NSString *)workingDirectory
{
  NSString *filePath = [self outputFilePathWithWorkingDirectory:workingDirectory pathExtension:header.extension];

  if (header.size > ToFileThreshold) {
    NSError *error = nil;
    id<FBDataConsumer> writer = [FBFileWriter syncWriterForFilePath:filePath error:&error];
    NSAssert(writer, @"Could not create writer %@", error);
    return [[FBUploadBuffer_ToFile alloc] initWithHeader:header filePath:filePath writer:writer];
  }
  return [[FBUploadBuffer_InMemory alloc] initWithHeader:header filePath:filePath];
}

- (instancetype)initWithHeader:(FBUploadHeader *)header filePath:(NSString *)filePath
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _header = header;
  _filePath = filePath;
  _position = 0;

  return self;
}

#pragma mark Public

- (nullable FBUploadedDestination *)writeData:(NSData *)input remainderOut:(NSData **)remainderOut
{
  // If we're at capacity, return immediately
  if (self.binary) {
    if (remainderOut) {
      *remainderOut = input;
    }
    return self.binary;
  }
  // Work out the offsets.
  size_t remainingToConsume = self.header.size - self.position;
  size_t dataToConsume = MIN(remainingToConsume, input.length);
  NSData *toWrite = nil;
  NSData *remainder = nil;
  // Not reaching capacity, just append
  if (dataToConsume == input.length) {
    toWrite = input;
    remainder = nil;
    // Reached capacity, slice it.
  } else {
    NSRange range = NSMakeRange(0, dataToConsume);
    toWrite = [input subdataWithRange:range];
    range = NSMakeRange(dataToConsume, input.length - dataToConsume);
    remainder = [input subdataWithRange:range];
  }
  // Append the data, return the remainder.
  [self writeData:toWrite];
  self.position = self.position + dataToConsume;
  if (remainderOut) {
    *remainderOut = remainder;
  }

  // We're at the end, so return the uploaded binary.
  if (self.position == self.header.size) {
    FBUploadedDestination *binary = [self constructUploadedBinary];
    self.binary = binary;
    return binary;
  }
  return nil;
}

#pragma mark Private

- (void)writeData:(NSData *)data
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

- (FBUploadedDestination *)constructUploadedBinary
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

@end

@implementation FBUploadBuffer_InMemory

- (instancetype)initWithHeader:(FBUploadHeader *)header filePath:(NSString *)filePath
{
  self = [super initWithHeader:header filePath:filePath];
  if (!self) {
    return nil;
  }

  _data = [NSMutableData dataWithCapacity:header.size];

  return self;
}

#pragma mark Private

- (void)writeData:(NSData *)data
{
  [self.data appendData:data];
}

- (FBUploadedDestination *)constructUploadedBinary
{
  BOOL didWrite = [self.data writeToFile:self.filePath atomically:YES];
  NSAssert(didWrite, @"Could not write data to file %@", self.filePath);
  self.data = nil;
  return [FBUploadedDestination destinationWithHeader:self.header path:self.filePath];
}

@end

@implementation FBUploadBuffer_ToFile

- (instancetype)initWithHeader:(FBUploadHeader *)header filePath:(NSString *)filePath writer:(id<FBDataConsumer>)writer
{
  self = [super initWithHeader:header filePath:filePath];
  if (!self) {
    return nil;
  }

  _writer = writer;

  return self;
}

#pragma mark Private

- (void)writeData:(NSData *)data
{
  [self.writer consumeData:data];
}

- (FBUploadedDestination *)constructUploadedBinary
{
  [self.writer consumeEndOfFile];
  self.writer = nil;
  return [FBUploadedDestination destinationWithHeader:self.header path:self.filePath];
}

@end
