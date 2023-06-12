/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBArchitectureProcessAdapter.h"

#import "FBProcessSpawnConfiguration.h"
#import "FBCollectionInformation.h"
#import "FBArchitecture.h"
#import "FBProcessBuilder.h"
#import "FBFuture.h"
#import "FBControlCoreError.h"
#import <mach-o/arch.h>
#include <sys/sysctl.h>


// https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment#Determine-Whether-Your-App-Is-Running-as-a-Translated-Binary
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
static int processIsTranslated(void)
{
   int ret = 0;
   size_t size = sizeof(ret);
   // patternlint-disable-next-line prefer-metasystemcontrol-byname
   if (sysctlbyname("sysctl.proc_translated", &ret, &size, NULL, 0) == -1)
   {
      if (errno == ENOENT)
         return 0;
      return -1;
   }
   return ret;
}
#pragma clang diagnostic pop

@implementation FBArchitectureProcessAdapter

-(FBFuture<FBProcessSpawnConfiguration *> *)adaptProcessConfiguration:(FBProcessSpawnConfiguration *)processConfiguration toAnyArchitectureIn:(NSSet<FBArchitecture> *)requestedArchitectures queue:(dispatch_queue_t)queue temporaryDirectory:(NSURL *)temporaryDirectory {
  return [self adaptProcessConfiguration:processConfiguration toAnyArchitectureIn:requestedArchitectures hostArchitectures:[FBArchitectureProcessAdapter hostMachineSupportedArchitectures] queue:queue temporaryDirectory:temporaryDirectory];
}

- (nullable FBArchitecture)selectArchitectureFrom:(NSSet<FBArchitecture> *)requestedArchitectures supportedArchitectures:(NSSet<FBArchitecture> *)supportedArchitectures
{

  if([requestedArchitectures containsObject:FBArchitectureArm64] && [supportedArchitectures containsObject:FBArchitectureArm64]) {
    return FBArchitectureArm64;
  }

  if([requestedArchitectures containsObject:FBArchitectureX86_64] && [supportedArchitectures containsObject:FBArchitectureX86_64]) {
    return FBArchitectureX86_64;
  }
  return nil;
}

-(FBFuture<FBProcessSpawnConfiguration *> *)adaptProcessConfiguration:(FBProcessSpawnConfiguration *)processConfiguration toAnyArchitectureIn:(NSSet<FBArchitecture> *)requestedArchitectures hostArchitectures:(NSSet<FBArchitecture> *)hostArchitectures queue:(dispatch_queue_t)queue temporaryDirectory:(NSURL *)temporaryDirectory {
  FBArchitecture architecture = [self selectArchitectureFrom:requestedArchitectures supportedArchitectures:hostArchitectures];
  if (!architecture) {
    return [[FBControlCoreError
             describeFormat:@"Could not select an architecture from %@ compatible with %@", [FBCollectionInformation oneLineDescriptionFromArray:requestedArchitectures.allObjects], [FBCollectionInformation oneLineDescriptionFromArray:hostArchitectures.allObjects]
            ] failFuture];
  }

  return [[[self verifyArchitectureAvailable:processConfiguration.launchPath architecture:architecture queue:queue]
           onQueue:queue fmap:^FBFuture *(NSNull * _) {
    NSString *fileName = [[[[processConfiguration.launchPath lastPathComponent] stringByAppendingString:[[NSUUID new] UUIDString]] stringByAppendingString:@"."] stringByAppendingString:architecture];
    NSURL *filePath = [temporaryDirectory URLByAppendingPathComponent:fileName isDirectory:NO];
    return [[self extractArchitecture:architecture processConfiguration:processConfiguration queue:queue outputPath:filePath] mapReplace:[filePath path]];
  }]
          onQueue:queue fmap:^FBFuture *(NSString *extractedBinary) {
    return [[self getFixedupDyldFrameworkPathFromOriginalBinary:processConfiguration.launchPath queue:queue]
            onQueue:queue map:^FBProcessSpawnConfiguration *(NSString *dyldFrameworkPath) {
      NSMutableDictionary<NSString *, NSString *> *updatedEnvironment = [processConfiguration.environment mutableCopy];
      // DYLD_FRAMEWORK_PATH adds additional search paths for required "*.framewosk"s in binary
      // DYLD_LIBRARY_PATH adds additional search paths for required "*.dyld"s in binary
      [updatedEnvironment setValue:dyldFrameworkPath forKey:@"DYLD_FRAMEWORK_PATH"];
      [updatedEnvironment setValue:dyldFrameworkPath forKey:@"DYLD_LIBRARY_PATH"];
      return [[FBProcessSpawnConfiguration alloc] initWithLaunchPath:extractedBinary arguments:processConfiguration.arguments environment:updatedEnvironment io:processConfiguration.io mode:processConfiguration.mode];
    }];
  }];
}

/// Verifies that we can extract desired architecture from binary
-(FBFuture<NSNull *> *)verifyArchitectureAvailable:(NSString *)binary architecture:(FBArchitecture)architecture queue:(dispatch_queue_t)queue {
  return [[[[[[[FBProcessBuilder
    withLaunchPath:@"/usr/bin/lipo" arguments:@[binary, @"-verify_arch", architecture]]
    withStdOutToDevNull]
    withStdErrToDevNull]
    runUntilCompletionWithAcceptableExitCodes:[NSSet setWithObject:@0]]
    rephraseFailure:@"Desired architecture %@ not found in %@ binary", architecture, binary]
    mapReplace:[NSNull null]]
    timeout:10 waitingFor:@"lipo -verify_arch"];
}

-(FBFuture<NSString *> *)extractArchitecture:(FBArchitecture)architecture processConfiguration:(FBProcessSpawnConfiguration *)processConfiguration queue:(dispatch_queue_t)queue outputPath:(NSURL *)outputPath {
  return [[[[[[[FBProcessBuilder
    withLaunchPath:@"/usr/bin/lipo" arguments:@[processConfiguration.launchPath, @"-extract", architecture, @"-output", [outputPath path]]]
    withStdOutToDevNull]
              withStdErrLineReader:^(NSString * _Nonnull line) {
    NSLog(@"LINE %@\n", line);
  }]
    runUntilCompletionWithAcceptableExitCodes:[NSSet setWithObject:@0]]
    rephraseFailure:@"Failed to thin %@ architecture out from %@ binary", architecture, processConfiguration.launchPath]
    mapReplace:[NSNull null]]
    timeout:10 waitingFor:@"lipo -extract"];
}

/// After we lipoed out arch from binary, new binary placed into temporary folder.
/// That makes all dynamic library imports become incorrect. To fix that up we
/// have to specify `DYLD_FRAMEWORK_PATH` correctly.
-(FBFuture<NSString *> *)getFixedupDyldFrameworkPathFromOriginalBinary:(NSString *)binary queue:(dispatch_queue_t)queue {
  NSString *binaryFolder = [[binary stringByResolvingSymlinksInPath] stringByDeletingLastPathComponent];
  return [[[self getOtoolInfoFromBinary:binary queue:queue]
    onQueue:queue map:^NSSet<NSString *> *(NSString *result) {
      return [self extractRpathsFromOtoolOutput:result];
    }]
    onQueue:queue map:^NSString *(NSSet<NSString *> *result) {
      NSMutableArray<NSString *> *rpaths = [NSMutableArray new];
      for (NSString *binaryRpath in result) {
        if ([binaryRpath hasPrefix:@"@executable_path"]) {
          [rpaths addObject:[binaryRpath stringByReplacingOccurrencesOfString:@"@executable_path" withString:binaryFolder]];
        }
      }
      return [rpaths componentsJoinedByString:@":"];
    }];
}

-(FBFuture<NSString *> *)getOtoolInfoFromBinary:(NSString *)binary queue:(dispatch_queue_t)queue {
    return [[[[[[[FBProcessBuilder
      withLaunchPath:@"/usr/bin/otool" arguments:@[@"-l", binary]]
      withStdOutInMemoryAsString]
      withStdErrToDevNull]
      runUntilCompletionWithAcceptableExitCodes:[NSSet setWithObject:@0]]
      rephraseFailure:@"Failed query otool -l from %@", binary]
      onQueue:queue fmap:^FBFuture<NSString *>*(FBProcess<NSNull *, NSString *, NSString *> *task) {
        if (task.stdOut) {
            return [FBFuture futureWithResult: task.stdOut];
        }
        return [[FBControlCoreError describeFormat:@"Failed to call otool -l over %@", binary] failFuture];
    }]
      timeout:10 waitingFor:@"otool -l"];
}

/// Extracts rpath from full otool output
/// Each `LC_RPATH` entry like
/// ```
/// Load command 19
///   cmd LC_RPATH
///   cmdsize 48
///    path @executable_path/../../Frameworks/ (offset 12)
/// ```
/// transforms to
/// ```
/// @executable_path/../../Frameworks/
/// ```
-(NSSet<NSString *> *)extractRpathsFromOtoolOutput:(NSString *)otoolOutput {
  NSArray<NSString *> *lines = [otoolOutput componentsSeparatedByString: @"\n"];
  NSMutableSet<NSString *> *result = [NSMutableSet new];

  // Rpath entry looks like:
  // ```
  // Load command 19
  //   cmd LC_RPATH
  //   cmdsize 48
  //    path @executable_path/../../Frameworks/ (offset 12)
  // ```
  // So if we found occurence of `cmd LC_RPATH` rpath value will be two lines below.
  NSUInteger lcRpathValueOffset = 2;

  [lines enumerateObjectsUsingBlock:^(NSString *line, NSUInteger index, BOOL *_) {
    if ([self isLcPathDefinitionLine:line] && index + lcRpathValueOffset < lines.count) {
      NSString *rpathLine = lines[index + lcRpathValueOffset];

      NSString *rpath = [self extractRpathValueFromLine:rpathLine];
      if (rpath) {
        [result addObject:rpath];
      }
    }
  }];
  return result;
}

/// Checking for `LC_RPATH` in load commands
/// - Parameter line: Single line entry for otool output
-(bool)isLcPathDefinitionLine:(NSString *)line {
  bool hasCMD = false;
  bool hasLcRpath = false;
  for (NSString *component in [line componentsSeparatedByString: @" "]) {
    if ([component isEqualToString:@"cmd"]) {
      hasCMD = true;
    } else if ([component isEqualToString:@"LC_RPATH"]) {
      hasLcRpath = true;
    }
  }
  return (hasCMD && hasLcRpath);
}

// Note: spaces in path names are not available. Currently we use adapter for binaries
// inside Xcode that has relative paths to original binary.
// And there is no spaces in paths over there.
-(nullable NSString *)extractRpathValueFromLine:(NSString *)line {
  for (NSString *component in [line componentsSeparatedByString: @" "]) {
    if ([component hasPrefix:@"@executable_path"]) {
      return component;
    }
  }
  return nil;
}

+(NSSet<FBArchitecture> *)hostMachineSupportedArchitectures {
#if TARGET_CPU_X86_64
  int isTranslated = processIsTranslated();
  if (isTranslated == 1) {
    // Companion running as x86_64 with translation (Rosetta) -> Processor supports Arm64 and x86_64
    return [NSSet setWithArray:@[FBArchitectureArm64, FBArchitectureX86_64]];
  } else {
    // Companion running as x86_64 and translation is disabled or unknown
    // Assuming processor only supports x86_64 even if translation state is unknown
    return [NSSet setWithArray:@[FBArchitectureX86_64]];
  }
#else
  return [NSSet setWithArray:@[FBArchitectureArm64, FBArchitectureX86_64]];
#endif
}

@end
