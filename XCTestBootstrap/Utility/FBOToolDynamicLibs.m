/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBOToolDynamicLibs.h"

#import "FBOToolOperation.h"

@implementation FBOToolDynamicLibs

+ (FBFuture<NSArray *> *)findFullPathForSanitiserDyldInBundle:(NSString *)bundlePath onQueue:(nonnull dispatch_queue_t)queue {
    return [[FBOToolOperation listSanitiserDylibsRequiredByBundle:bundlePath onQueue:queue] onQueue:queue map:^id _Nonnull(NSArray<NSString *> * _Nonnull libsList) {

        NSString *clanLocation = [FBXcodeConfiguration.developerDirectory stringByAppendingPathComponent:@"Toolchains/XcodeDefault.xctoolchain/usr/lib/clang"];
        NSError *error = nil;
        NSArray<NSURL *> *fileList = [self filesInDirectory:[NSURL fileURLWithPath:clanLocation] error:&error];

        if ([fileList count] == 0 || error) {
            if(error == nil) return [[FBControlCoreError
                                      describeFormat:@"No clang version found in %@", clanLocation] failFuture];
            return [FBFuture futureWithError:error];
        }

        NSString *libsFolder = [NSString pathWithComponents: @[[fileList[0] path], @"lib/darwin/"]];

        NSString *bundleFrameworksFolder = [bundlePath stringByAppendingPathComponent:@"Frameworks"];
        if(![[NSFileManager defaultManager] fileExistsAtPath:bundleFrameworksFolder]) {
          bundleFrameworksFolder = [bundlePath stringByAppendingPathComponent:@"Contents/Frameworks"];
        }

        NSArray<NSURL *> *bundleLibs = [self filesInDirectory:[NSURL fileURLWithPath:bundleFrameworksFolder] error:&error];
        NSMutableSet<NSString *> *bundleLibsNames = nil;
        if (bundleLibs) {
          bundleLibsNames = [NSMutableSet setWithCapacity:bundleLibs.count];
          for(NSURL *libURL in bundleLibs) {
            NSString *libName = libURL.pathComponents.lastObject;
            if (libName) {
              [bundleLibsNames addObject:libName];
            }
          }
        }

        NSMutableArray *libraries = [[NSMutableArray alloc] init];
        for (NSString* lib in libsList) {
          NSString *libPath = nil;
          if ([bundleLibsNames member:lib]) {
            libPath = [bundleFrameworksFolder stringByAppendingPathComponent:lib];
          } else {
            libPath = [libsFolder stringByAppendingPathComponent:lib];
          }
          [libraries addObject:libPath];
        }

        return libraries;
    }];
}

+ (NSArray<NSURL *> *)filesInDirectory:(NSURL *)directory error:(NSError **)error
{
    NSError *innerError;
    NSArray<NSURL *> *filesInDirectory = [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory includingPropertiesForKeys:@[NSURLIsDirectoryKey] options:0 error:&innerError];
    if (filesInDirectory == nil) {
        *error = [[[FBControlCoreError
                    describeFormat:@"Failed to list files in directory %@", directory]
                   causedBy:innerError]
                  fail:error];
    }
    return filesInDirectory;
}

@end
