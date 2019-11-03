/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBBundleDescriptor.h"

#import "FBBinaryDescriptor.h"
#import "FBCodesignProvider.h"
#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"
#import "FBControlCoreLogger.h"
#import "FBFileManager.h"
#import "FBTaskBuilder.h"
#import "FBXCodeConfiguration.h"

@implementation FBBundleDescriptor

#pragma mark Initializers

- (instancetype)initWithName:(NSString *)name identifier:(NSString *)identifier path:(NSString *)path binary:(nullable FBBinaryDescriptor *)binary
{
  NSParameterAssert(name);
  NSParameterAssert(path);
  NSParameterAssert(identifier);

  self = [super init];
  if (!self) {
    return nil;
  }

  _name = name;
  _identifier = identifier;
  _path = path;
  _binary = binary;

  return self;
}

+ (instancetype)bundleFromPath:(NSString *)path error:(NSError **)error
{
  return [self bundleFromPath:path fallbackIdentifier:NO error:error];
}

+ (instancetype)bundleWithFallbackIdentifierFromPath:(NSString *)path error:(NSError **)error
{
  return [self bundleFromPath:path fallbackIdentifier:YES error:error];
}

+ (instancetype)bundleFromPath:(NSString *)path fallbackIdentifier:(BOOL)fallbackIdentifier error:(NSError **)error
{
  if (!path) {
    return [[FBControlCoreError
      describe:@"Nil file path provided for bundle path"]
      fail:error];
  }
  NSBundle *bundle = [NSBundle bundleWithPath:path];
  if (!bundle) {
    return [[FBControlCoreError
      describeFormat:@"Failed to load bundle at path %@", path]
      fail:error];
  }
  NSString *bundleName = [self bundleNameForBundle:bundle];
  NSString *identifier = [bundle bundleIdentifier];
  if (!identifier) {
    if (!fallbackIdentifier) {
      return [[FBControlCoreError
        describeFormat:@"Could not obtain Bundle ID for bundle at path %@", path]
        fail:error];
    }
    identifier = bundleName;
  }
  FBBinaryDescriptor *binary = [self binaryForBundle:bundle error:error];
  if (!binary) {
    return nil;
  }
  return [[self alloc] initWithName:bundleName identifier:identifier path:path binary:binary];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  // Is immutable
  return self;
}

#pragma mark NSObject

- (BOOL)isEqual:(FBBundleDescriptor *)object
{
  if (![object isMemberOfClass:self.class]) {
    return NO;
  }
  return [object.name isEqual:self.name] &&
         [object.path isEqual:self.path] &&
         [object.identifier isEqual:self.identifier] &&
         [object.binary isEqual:self.binary];
}

- (NSUInteger)hash
{
  return self.name.hash | self.path.hash | self.identifier.hash | self.binary.hash;
}

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  return [self shortDescription];
}

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:
    @"Name: %@ | ID: %@",
    self.name,
    self.identifier
  ];
}

- (NSString *)debugDescription
{
  return [NSString stringWithFormat:
    @"%@ | Path: %@ | Binary (%@)",
    self.shortDescription,
    self.path,
    self.binary
  ];
}

#pragma mark FBJSONSerializable

- (NSDictionary *)jsonSerializableRepresentation
{
  NSMutableDictionary *result = [[NSMutableDictionary alloc] init];

  result[@"name"] = self.name;
  result[@"bundle_id"] = self.identifier;
  result[@"path"] = self.path;
  if (self.binary) {
    result[@"binary"] = self.binary.jsonSerializableRepresentation;
  }

  return result;
}

#pragma mark Public Methods

- (FBFuture<NSDictionary<NSString *, NSString *> *> *)updatePathsForRelocationWithCodesign:(id<FBCodesignProvider>)codesign logger:(id<FBControlCoreLogger>)logger queue:(dispatch_queue_t)queue
{
  return [[[self
    replacementsForBinary]
    onQueue:queue fmap:^ FBFuture * (NSDictionary<NSString *, NSString *> *replacements) {
      if (replacements.count == 0) {
        return [FBFuture futureWithResult:replacements];
      }
      NSMutableArray<NSString *> *arguments = NSMutableArray.array;
      for (NSString *key in replacements.allKeys) {
        [arguments addObject:@"-rpath"];
        [arguments addObject:key];
        [arguments addObject:replacements[key]];
      }
      [arguments addObject:self.binary.path];
      [logger logFormat:@"Updating rpaths for binary %@", [FBCollectionInformation oneLineDescriptionFromDictionary:replacements]];
      return [[[[[FBTaskBuilder
        withLaunchPath:@"/usr/bin/install_name_tool" arguments:arguments]
        withAcceptableTerminationStatusCodes:[NSSet setWithObject:@0]]
        withStdErrToLogger:logger]
        runUntilCompletion]
        mapReplace:replacements];
    }]
    onQueue:queue fmap:^(NSDictionary<NSString *, NSString *> *replacements) {
      [logger logFormat:@"Re-Codesigning after rpath update %@", self.path];
      return [[codesign signBundleAtPath:self.path] mapReplace:replacements];
    }];
}

#pragma mark Private

+ (FBBinaryDescriptor *)binaryForBundle:(NSBundle *)bundle error:(NSError **)error
{
  NSString *binaryPath = [bundle executablePath];
  if (!binaryPath) {
    return [[FBControlCoreError
      describeFormat:@"Could not obtain binary path for bundle %@", bundle.bundlePath]
      fail:error];
  }

  return [FBBinaryDescriptor binaryWithPath:binaryPath error:error];
}

+ (NSString *)bundleNameForBundle:(NSBundle *)bundle
{
  return bundle.infoDictionary[@"CFBundleName"] ?: bundle.infoDictionary[@"CFBundleExecutable"] ?: bundle.bundlePath.stringByDeletingPathExtension.lastPathComponent;
}

- (FBFuture<NSDictionary<NSString *, NSString *> *> *)replacementsForBinary
{
  NSError *error = nil;
  NSArray<NSString *> *rpaths = [self.binary rpathsWithError:&error];
  if (!rpaths) {
    return [FBFuture futureWithError:error];
  }
  return [FBFuture futureWithResult:[FBBundleDescriptor interpolateRpathReplacementsForRPaths:rpaths]];
}

+ (NSDictionary<NSString *, NSString *> *)interpolateRpathReplacementsForRPaths:(NSArray<NSString *> *)rpaths
{
  NSError *error = nil;
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(/Applications/(?:xcode|Xcode).*\\.app/Contents/Developer)(.*)" options:0 error:&error];
  NSAssert(regex, @"Regex failed to compile %@", error);
  NSMutableDictionary<NSString *, NSString *> *replacements = NSMutableDictionary.dictionary;
  for (NSString *rpath in rpaths) {
    NSTextCheckingResult *result = [regex firstMatchInString:rpath options:0 range:NSMakeRange(0, rpath.length)];
    if (!result) {
      continue;
    }
    NSString *oldXcodePath = [rpath substringWithRange:[result rangeAtIndex:1]];
    replacements[rpath] = [rpath stringByReplacingOccurrencesOfString:oldXcodePath withString:FBXcodeConfiguration.developerDirectory];
  }
  return replacements;
}

@end
