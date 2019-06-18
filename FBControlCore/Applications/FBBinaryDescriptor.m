/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBBinaryDescriptor.h"

#import "FBControlCoreError.h"
#import "FBCollectionInformation.h"
#import "FBControlCoreGlobalConfiguration.h"

#include <mach/machine.h>
#include <stdio.h>

#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <mach-o/swap.h>

#import "FBControlCoreError.h"

FBBinaryArchitecture const FBBinaryArchitecturei386 = @"i386";
FBBinaryArchitecture const FBBinaryArchitecturex86_64 = @"x86_64";
FBBinaryArchitecture const FBBinaryArchitectureArm = @"arm";
FBBinaryArchitecture const FBBinaryArchitectureArm64 = @"arm64";

static inline FBBinaryArchitecture ArchitectureForCPUType(cpu_type_t cpuType)
{
  NSDictionary<NSNumber *, FBBinaryArchitecture> *lookup = @{
    @(CPU_TYPE_I386) : FBBinaryArchitecturei386,
    @(CPU_TYPE_X86_64) : FBBinaryArchitecturex86_64,
    @(CPU_TYPE_ARM) : FBBinaryArchitectureArm,
    @(CPU_TYPE_ARM64) : FBBinaryArchitectureArm64,
  };
  return lookup[@(cpuType)];
}

static inline NSString *MagicNameForMagic(uint32_t magic)
{
  NSDictionary<NSNumber *, NSString *> *lookup = @{
    @(MH_MAGIC) : @"MH_MAGIC",
    @(MH_CIGAM) : @"MH_CIGAM",
    @(MH_MAGIC_64) : @"MH_MAGIC_64",
    @(MH_CIGAM_64) : @"MH_CIGAM_64",
    @(FAT_MAGIC) : @"FAT_MAGIC",
    @(FAT_CIGAM) : @"FAT_CIGAM"
  };
  return lookup[@(magic)];
}

static inline BOOL IsMagic32(uint32_t magic)
{
  return magic == MH_MAGIC || magic == MH_CIGAM;
}

static inline BOOL IsMagic64(uint32_t magic)
{
  return magic == MH_MAGIC_64 || magic == MH_CIGAM_64;
}

static inline BOOL IsFatMagic(uint32_t magic)
{
  return magic == FAT_MAGIC || magic == FAT_CIGAM;
}

static inline BOOL IsSwap(uint32_t magic)
{
  return magic == MH_CIGAM || magic == MH_CIGAM_64 || magic == FAT_CIGAM;
}

static inline BOOL IsMagic(uint32_t magic)
{
  return IsMagic32(magic) || IsMagic64(magic) || IsFatMagic(magic);
}

static inline uint32_t GetMagic(FILE *file)
{
  // Get then read from the current position.
  long position = ftell(file);
  uint32_t magic;
  fread(&magic, sizeof(uint32_t), 1, file);

  // Move back to the previous position now we know the magic.
  fseek(file, position, SEEK_SET);
  return magic;
}

static inline FBBinaryArchitecture ReadArch32(FILE *file, uint32_t magic)
{
  struct mach_header header;
  fread(&header, sizeof(struct mach_header), 1, file);
  if (IsSwap(magic)) {
    swap_mach_header(&header, 0);
  }
  return ArchitectureForCPUType(header.cputype);
}

static inline FBBinaryArchitecture ReadArch64(FILE *file, uint32_t magic)
{
  // Read the header from the start of the file.
  struct mach_header_64 header;
  fread(&header, sizeof(header), 1, file);
  if (IsSwap(magic)) {
    swap_mach_header_64(&header, 0);
  }
  return ArchitectureForCPUType(header.cputype);
}

static inline FBBinaryArchitecture ReadArch(FILE *file, uint32_t magic)
{
  if (IsMagic32(magic)) {
    return ReadArch32(file, magic);
  }
  if (IsMagic64(magic)) {
    return ReadArch64(file, magic);
  }
  return nil;
}

static inline NSArray<FBBinaryArchitecture> *ReadArchsFat(FILE *file, uint32_t fatMagic)
{
  // Get the Fat Header.
  struct fat_header header;
  fread(&header, sizeof(struct fat_header), 1, file);
  if (IsSwap(fatMagic)) {
    swap_fat_header(&header, 0);
  }

  NSMutableArray<FBBinaryArchitecture> *array = [NSMutableArray array];
  long fatArchPosition = sizeof(struct fat_header);
  for (uint32_t index = 0; index < header.nfat_arch; index++) {
    // Seek-to then get the Fat Arch info
    fseek(file, fatArchPosition, SEEK_SET);
    struct fat_arch fatArch;
    fread(&fatArch, sizeof(struct fat_arch), 1, file);
    if (IsSwap(fatMagic)) {
      swap_fat_arch(&fatArch, 1, 0);
    }

    // Seek to the start position of the arch
    fseek(file, fatArch.offset, SEEK_SET);
    uint32_t magic = GetMagic(file);
    if (!IsMagic(magic)){
      return nil;
    }

    // Get the Arch
    NSString *arch = ReadArch(file, magic);
    if (!arch) {
      return nil;
    }
    [array addObject:arch];
    fatArchPosition += sizeof(struct fat_arch);
  }

  return [array copy];
}

static inline NSArray<FBBinaryArchitecture> *ReadArchs(FILE *file, uint32_t magic)
{
  if (IsFatMagic(magic)) {
    return ReadArchsFat(file, magic);
  }
  if (IsMagic32(magic)) {
    FBBinaryArchitecture arch = ReadArch32(file, magic);
    return arch ? @[arch] : @[];
  }
  if (IsMagic64(magic)) {
    FBBinaryArchitecture arch = ReadArch64(file, magic);
    return arch ? @[arch] : @[];
  }
  return @[];
}

@implementation FBBinaryDescriptor

- (instancetype)initWithName:(NSString *)name architectures:(NSSet<FBBinaryArchitecture> *)architectures path:(NSString *)path
{
  NSParameterAssert(name);
  NSParameterAssert(architectures);
  NSParameterAssert(path);

  self = [super init];
  if (!self) {
    return nil;
  }

  _name = name;
  _architectures = architectures;
  _path = path;

  return self;
}

+ (nullable instancetype)binaryWithPath:(NSString *)binaryPath error:(NSError **)error;
{
  if (![NSFileManager.defaultManager fileExistsAtPath:binaryPath]) {
    return [[FBControlCoreError
      describeFormat:@"Binary does not exist at path %@", binaryPath]
      fail:error];
  }

  FILE *file = fopen(binaryPath.UTF8String, "rb");
  if (file == NULL) {
    return [[FBControlCoreError describeFormat:@"Could not fopen file at path %@", binaryPath] fail:error];
  }

  // Seek to and read the magic.
  rewind(file);
  uint32_t magic = GetMagic(file);

  if (!IsMagic(magic)) {
    fclose(file);
    return [[FBControlCoreError describeFormat:@"Could not interpret magic '%d' in file %@", magic, binaryPath] fail:error];
  }

  NSArray *archs = ReadArchs(file, magic);
  if (!archs) {
    fclose(file);
    return [[FBControlCoreError describeFormat:@"Could not read architechtures of magic %@ in file %@", MagicNameForMagic(magic), binaryPath] fail:error];
  }

  fclose(file);

  return [[FBBinaryDescriptor alloc]
    initWithName:[self binaryNameForBinaryPath:binaryPath]
    architectures:[NSSet setWithArray:archs]
    path:binaryPath];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  // Is immutable.
  return self;
}

#pragma mark NSObject

- (BOOL)isEqual:(FBBinaryDescriptor *)object
{
  if (![object isMemberOfClass:self.class]) {
    return NO;
  }
  return [object.name isEqual:self.name] &&
    [object.path isEqual:self.path] &&
    [object.architectures isEqual:self.architectures];
}

- (NSUInteger)hash
{
  return self.name.hash | self.path.hash | self.architectures.hash;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Name: %@ | Path: %@ | Architectures: %@",
    self.name,
    self.path,
    [FBCollectionInformation oneLineDescriptionFromArray:self.architectures.allObjects]
  ];
}

#pragma mark JSON Conversion

+ (FBBinaryDescriptor *)inflateFromJSON:(id)json error:(NSError **)error
{
  NSString *path = json[@"path"];
  if (![path isKindOfClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a valid binary path", path] fail:error];
  }
  NSError *innerError = nil;
  FBBinaryDescriptor *binary = [FBBinaryDescriptor binaryWithPath:path error:&innerError];
  if (!binary) {
    return [[[FBControlCoreError
      describeFormat:@"Could not create binary from path %@", path]
      causedBy:innerError]
      fail:error];
  }
  return binary;
}

- (NSDictionary *)jsonSerializableRepresentation
{
  return @{
    @"name" : self.name,
    @"path" : self.path,
    @"architectures" : self.architectures.allObjects,
  };
}

#pragma mark Private

+ (NSString *)binaryNameForBinaryPath:(NSString *)binaryPath
{
  return binaryPath.lastPathComponent;
}

@end
