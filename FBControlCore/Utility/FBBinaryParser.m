/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBBinaryParser.h"

#include <mach/machine.h>
#include <stdio.h>

#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <mach-o/swap.h>

#import "FBControlCoreError.h"

static inline NSString *ArchitectureForCPUType(cpu_type_t cpuType)
{
  NSDictionary *lookup = @{
    @(CPU_TYPE_I386) : @"i386",
    @(CPU_TYPE_X86_64) : @"x86_64",
    @(CPU_TYPE_ARM) : @"arm" ,
    @(CPU_TYPE_ARM64) : @"arm64"
  };
  return lookup[@(cpuType)];
}

static inline NSString *MagicNameForMagic(uint32_t magic)
{
  NSDictionary *lookup = @{
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

static inline NSString *ReadArch32(FILE *file, uint32_t magic)
{
  struct mach_header header;
  fread(&header, sizeof(struct mach_header), 1, file);
  if (IsSwap(magic)) {
    swap_mach_header(&header, 0);
  }
  return ArchitectureForCPUType(header.cputype);
}

static inline NSString *ReadArch64(FILE *file, uint32_t magic)
{
  struct mach_header_64 header;
  fread(&header, sizeof(struct mach_header_64), 1, file);
  if (IsSwap(magic)) {
    swap_mach_header_64(&header, 0);
  }
  return ArchitectureForCPUType(header.cputype);
}

static inline NSString *ReadArch(FILE *file, uint32_t magic)
{
  if (IsMagic32(magic)) {
    return ReadArch32(file, magic);
  }
  if (IsMagic64(magic)) {
    return ReadArch64(file, magic);
  }
  abort();
}

static inline NSArray *ReadArchsFat(FILE *file, uint32_t fatMagic)
{
  // Get the Fat Header.
  struct fat_header header;
  fread(&header, sizeof(struct fat_header), 1, file);
  if (IsSwap(fatMagic)) {
    swap_fat_header(&header, 0);
  }

  NSMutableArray *array = [NSMutableArray array];
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

static inline NSArray *ReadArchs(FILE *file, uint32_t magic)
{
  if (IsFatMagic(magic)) {
    return ReadArchsFat(file, magic);
  }
  if (IsMagic32(magic) || IsMagic64(magic)) {
    NSString *arch = IsMagic32(magic) ? ReadArch32(file, magic) : ReadArch64(file, magic);
    return arch ? @[arch] : @[];
  }
  abort();
}

@implementation FBBinaryParser

+ (NSSet *)architecturesForBinaryAtPath:(NSString *)binaryPath error:(NSError **)error
{
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
  return [NSSet setWithArray:archs];
}

@end
