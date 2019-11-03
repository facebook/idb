/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBWeakFrameworkLoader.h"

#import <FBControlCore/FBControlCore.h>

#import <objc/runtime.h>

#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"
#import "FBControlCoreGlobalConfiguration.h"
#import "FBControlCoreLogger.h"
#import "FBWeakFramework.h"

static BOOL (*originalNSBundleLoad)(NSBundle *, SEL, NSError **);
static NSString *const ignoredPathSlice = @"Library/Application Support/Developer/Shared/Xcode/Plug-ins";

/**
 Loading xcplugins can pose an issue if the xcplugin statically links a symbol that the current process has linked dynamically.
 If we bypass the loading of these plugins, we can be more confident that there won't be ambiguous symbols at runtime.
 */
static BOOL FBUserPluginBypassingBundleLoad(NSBundle *bundle, SEL selector, NSError **error)
{
  if (![bundle.bundlePath.pathExtension isEqualToString:@"xcplugin"]) {
    return originalNSBundleLoad(bundle, selector, error);
  }
  NSString *pluginPath = bundle.bundlePath.stringByDeletingLastPathComponent;
  if (![pluginPath hasSuffix:ignoredPathSlice]) {
    return originalNSBundleLoad(bundle, selector, error);
  }
  id<FBControlCoreLogger> logger = FBControlCoreGlobalConfiguration.defaultLogger;
  [logger.debug logFormat:@"Bypassing load of %@ as it is a User Plugin", bundle.bundlePath];
  return YES;
}

@implementation FBWeakFrameworkLoader

+ (void)swizzleBundleLoader
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    Method method = class_getInstanceMethod(NSBundle.class, @selector(loadAndReturnError:));
    originalNSBundleLoad = (BOOL(*)(NSBundle *, SEL, NSError **)) method_getImplementation(method);
    method_setImplementation(method, (IMP) FBUserPluginBypassingBundleLoad);
  });
}

// A Mapping of Class Names to the Frameworks that they belong to. This serves to:
// 1) Represent the Frameworks that FBControlCore is dependent on via their classes
// 2) Provide a path to the relevant Framework.
// 3) Provide a class for sanity checking the Framework load.
// 4) Provide a class that can be checked before the Framework load to avoid re-loading the same
//    Framework if others have done so before.
// 5) Provide a sanity check that any preloaded Private Frameworks match the current xcode-select version
+ (BOOL)loadPrivateFrameworks:(NSArray<FBWeakFramework *> *)weakFrameworks logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  // Swizzle the bundle loader to ensure that we don't load user plugins.
  [self swizzleBundleLoader];

  for (FBWeakFramework *framework in weakFrameworks) {
    NSError *innerError = nil;
    if (![framework loadWithLogger:logger error:&innerError]) {
      return [FBControlCoreError failBoolWithError:innerError errorOut:error];
    }
  }

  // We're done with loading Frameworks.
  [logger.debug logFormat:
    @"Loaded All Private Frameworks %@",
    [FBCollectionInformation oneLineDescriptionFromArray:[weakFrameworks valueForKeyPath:@"@unionOfObjects.name"] atKeyPath:@"lastPathComponent"]
  ];

  return YES;
}

@end
