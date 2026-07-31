/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "AccessibilityService.h"

#import <dlfcn.h>
#import <objc/runtime.h>

#import <CoreGraphics/CoreGraphics.h>

// The `XC_kAXXC*` attribute keys. These MUST match `FBRemoteAutomationAXAttribute` host-side so the
// emitted tree feeds the shared serializer (`FBRemoteAutomationPlatformElement`) unchanged.
static NSString *const kAXElementType = @"XC_kAXXCAttributeElementType";
static NSString *const kAXElementBaseType = @"XC_kAXXCAttributeElementBaseType";
static NSString *const kAXLabel = @"XC_kAXXCAttributeLabel";
static NSString *const kAXValue = @"XC_kAXXCAttributeValue";
static NSString *const kAXIdentifier = @"XC_kAXXCAttributeIdentifier";
static NSString *const kAXFrame = @"XC_kAXXCAttributeFrame";
static NSString *const kAXAutomationType = @"XC_kAXXCAttributeAutomationType";
static NSString *const kAXChildren = @"XC_kAXXCAttributeChildren";

static NSString *const kRequestVerb = @"verb";
static NSString *const kRequestPid = @"pid";
static NSString *const kRequestMaxDepth = @"maxDepth";
static NSString *const kResponseOk = @"ok";
static NSString *const kResponseTree = @"tree";
static NSString *const kResponseError = @"error";

static NSString *const kVerbDescribe = @"describe";

// The private frameworks are loaded from the booted runtime root at these paths (spike-proven via
// `simctl spawn`); they are driven through the ObjC runtime, never linked.
static NSString *const kAXRuntimePath =
@"/System/Library/PrivateFrameworks/AXRuntime.framework/AXRuntime";
static NSString *const kXCTAutomationSupportPath =
@"/Developer/Library/PrivateFrameworks/XCTAutomationSupport.framework/XCTAutomationSupport";

// A depth cap and a total-node budget guard against pathological trees.
static const int kDefaultMaxDepth = 100;
static const int kNodeBudget = 5000;

// File-local declarations of the private classes we drive. The classes are `dlopen`-loaded and
// resolved via `objc_lookUpClass`, so we never reference the class symbols at link time; these
// interfaces exist only to type the instance/class messages (avoiding raw `objc_msgSend`).
@interface XCTAccessibilityFramework : NSObject
- (instancetype)initForRemoteAccess;
- (nullable NSDictionary *)attributesForElement:(id)element
                                     attributes:(NSArray<NSString *> *)attributes
                                          error:(NSError **)error;
@end

@interface XCAccessibilityElement : NSObject
+ (nullable instancetype)elementWithProcessIdentifier:(pid_t)pid;
@end

#pragma mark - AX client setup

static XCTAccessibilityFramework *_Nullable FBAXBridgeMakeFramework(NSString *_Nullable *_Nullable error)
{
  dlopen(kAXRuntimePath.fileSystemRepresentation, RTLD_NOW);
  dlopen(kXCTAutomationSupportPath.fileSystemRepresentation, RTLD_NOW);
  Class frameworkClass = objc_lookUpClass("XCTAccessibilityFramework");
  if (!frameworkClass) {
    if (error) {
      *error = @"XCTAccessibilityFramework unavailable — is XCTAutomationSupport loaded?";
    }
    return nil;
  }
  XCTAccessibilityFramework *framework =
  [(XCTAccessibilityFramework *)[frameworkClass alloc] initForRemoteAccess];
  if (!framework) {
    if (error) {
      *error = @"initForRemoteAccess returned nil";
    }
    return nil;
  }
  return framework;
}

static NSArray<NSString *> *FBAXBridgeFetchList(void)
{
  return @[
    kAXElementType, kAXElementBaseType, kAXLabel, kAXValue, kAXIdentifier, kAXFrame, kAXAutomationType,
    kAXChildren
  ];
}

#pragma mark - JSON coercion

// The frame arrives from `attributesForElement:` as an `NSValue`-wrapped `CGRect` (or, tolerantly, an
// existing dictionary representation). Emit the CGRect dictionary representation the host consumes via
// `CGRectMakeWithDictionaryRepresentation`.
static NSDictionary *FBAXBridgeFrameDictionary(id frameValue)
{
  CGRect rect = CGRectZero;
  if ([frameValue isKindOfClass:NSDictionary.class]) {
    if (CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)frameValue, &rect)) {
      return (NSDictionary *)frameValue;
    }
  } else if ([frameValue isKindOfClass:NSValue.class]) {
    NSValue *value = (NSValue *)frameValue;
    if (strcmp(value.objCType, @encode(CGRect)) == 0) {
      [value getValue:&rect size:sizeof(rect)];
    }
  } else if (frameValue) {
    NSLog(@"[AccessibilityService] unexpected frame value class: %@", [frameValue class]);
  }
  NSDictionary *dictionary = (NSDictionary *)CFBridgingRelease(CGRectCreateDictionaryRepresentation(rect));
  return dictionary ?: @{};
}

// Coerce an attribute value to a JSON-serializable form. Strings and numbers pass through; the frame
// becomes a dictionary; anything else is stringified so the payload never fails serialization.
static id FBAXBridgeJSONSafeValue(id _Nullable value, NSString *key)
{
  if (value == nil || value == NSNull.null) {
    return NSNull.null;
  }
  if ([key isEqualToString:kAXFrame]) {
    return FBAXBridgeFrameDictionary(value);
  }
  if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) {
    return value;
  }
  return [value description];
}

#pragma mark - Tree walk

// One mach round-trip per node: read the element's attributes, coerce them to JSON, then recurse into
// its children (replacing the child `XCAccessibilityElement`s with their read dictionaries in place).
static NSDictionary *_Nullable FBAXBridgeBuildNode(XCTAccessibilityFramework *framework,
                                                   id element,
                                                   int depth,
                                                   int maxDepth,
                                                   int *budget)
{
  NSError *error = nil;
  NSDictionary *attributes = [framework attributesForElement:element
                                                  attributes:FBAXBridgeFetchList()
                                                       error:&error];
  if (![attributes isKindOfClass:NSDictionary.class]) {
    return nil;
  }

  NSMutableDictionary *node = [NSMutableDictionary dictionaryWithCapacity:attributes.count];
  for (NSString *key in attributes) {
    if ([key isEqualToString:kAXChildren]) {
      continue;
    }
    node[key] = FBAXBridgeJSONSafeValue(attributes[key], key);
  }

  NSMutableArray<NSDictionary *> *children = [NSMutableArray array];
  if (depth < maxDepth) {
    NSArray *childElements = attributes[kAXChildren];
    if ([childElements isKindOfClass:NSArray.class]) {
      for (id child in childElements) {
        if (*budget <= 0) {
          break;
        }
        (*budget)--;
        NSDictionary *childNode = FBAXBridgeBuildNode(framework, child, depth + 1, maxDepth, budget);
        if (childNode) {
          [children addObject:childNode];
        }
      }
    }
  }
  node[kAXChildren] = children;
  return node;
}

#pragma mark - Request handling

static NSDictionary *FBAXBridgeErrorResponse(NSString *message)
{
  return @{kResponseOk : @NO, kResponseError : message};
}

NSDictionary<NSString *, id> *FBAXBridgeHandleRequest(NSDictionary<NSString *, id> *request)
{
  NSString *verb = request[kRequestVerb];
  if (![verb isEqualToString:kVerbDescribe]) {
    return FBAXBridgeErrorResponse([NSString stringWithFormat:@"unsupported verb: %@", verb ?: @"(nil)"]);
  }

  NSNumber *pidNumber = request[kRequestPid];
  if (![pidNumber isKindOfClass:NSNumber.class]) {
    return FBAXBridgeErrorResponse(@"describe requires a numeric pid");
  }
  pid_t pid = pidNumber.intValue;
  int maxDepth = [request[kRequestMaxDepth] isKindOfClass:NSNumber.class]
  ? [(NSNumber *)request[kRequestMaxDepth] intValue]
  : kDefaultMaxDepth;

  NSString *setupError = nil;
  XCTAccessibilityFramework *framework = FBAXBridgeMakeFramework(&setupError);
  if (!framework) {
    return FBAXBridgeErrorResponse(setupError ?: @"accessibility setup failed");
  }

  Class elementClass = objc_lookUpClass("XCAccessibilityElement");
  if (!elementClass) {
    return FBAXBridgeErrorResponse(@"XCAccessibilityElement unavailable");
  }
  id root = [(id)elementClass elementWithProcessIdentifier:pid];
  if (!root) {
    return FBAXBridgeErrorResponse([NSString stringWithFormat:@"no application element for pid %d", pid]);
  }

  int budget = kNodeBudget;
  NSDictionary *tree = FBAXBridgeBuildNode(framework, root, 0, maxDepth, &budget);
  if (!tree) {
    return FBAXBridgeErrorResponse([NSString stringWithFormat:@"failed to read the element tree for pid %d", pid]);
  }
  return @{kResponseOk : @YES, kResponseTree : tree};
}

#pragma mark - Oneshot argv front-end

int handleAccessibilityAction(NSString *action, NSArray<NSString *> *arguments)
{
  NSMutableDictionary<NSString *, id> *request = [NSMutableDictionary dictionary];
  request[kRequestVerb] = action;
  for (NSUInteger i = 0; i + 1 < arguments.count; i += 2) {
    NSString *flag = arguments[i];
    NSString *argValue = arguments[i + 1];
    if ([flag isEqualToString:@"--pid"]) {
      request[kRequestPid] = @(argValue.intValue);
    } else if ([flag isEqualToString:@"--max-depth"]) {
      request[kRequestMaxDepth] = @(argValue.intValue);
    }
  }

  NSDictionary *response = FBAXBridgeHandleRequest(request);
  NSError *jsonError = nil;
  NSData *json = [NSJSONSerialization dataWithJSONObject:response options:0 error:&jsonError];
  if (!json) {
    NSLog(@"[AccessibilityService] failed to serialize response: %@", jsonError);
    return 1;
  }
  fwrite(json.bytes, 1, json.length, stdout);
  fputc('\n', stdout);
  return [response[kResponseOk] boolValue] ? 0 : 1;
}
