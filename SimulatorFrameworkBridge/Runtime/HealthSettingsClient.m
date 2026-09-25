/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "HealthSettingsClient.h"

#import <dlfcn.h>

#import "Private/HealthKitPrivate.h"

static Class (^healthClassLookup)(NSString *);

void FBHealthSetClassLookupForTesting(Class (^lookup)(NSString *))
{
  healthClassLookup = [lookup copy];
}

static Class healthClassForName(NSString *name)
{
  return healthClassLookup ? healthClassLookup(name) : NSClassFromString(name);
}

static id loadHealthStore(void)
{
  if (!dlopen("/System/Library/Frameworks/HealthKit.framework/HealthKit", RTLD_NOW)) {
    NSLog(@"[Health] Failed to load HealthKit.framework: %s", dlerror());
    return nil;
  }
  Class HKHealthStoreClass = healthClassForName(@"HKHealthStore");
  if (!HKHealthStoreClass) {
    NSLog(@"[Health] HKHealthStore class not found");
    return nil;
  }
  return [[HKHealthStoreClass alloc] init];
}

static HKAuthorizationStore *loadAuthStore(void)
{
  id store = loadHealthStore();
  if (!store) {
    return nil;
  }
  Class HKAuthStoreClass = healthClassForName(@"HKAuthorizationStore");
  if (!HKAuthStoreClass) {
    NSLog(@"[Health] HKAuthorizationStore class not found");
    return nil;
  }
  return [[HKAuthStoreClass alloc] initWithHealthStore:store];
}

static id resolveHealthKitObjectType(NSString *identifier)
{
  static NSArray<NSString *> *factoryClasses;
  static NSArray<NSString *> *factorySelectors;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    factoryClasses = @[
      @"HKQuantityType",
      @"HKCategoryType",
      @"HKCharacteristicType",
      @"HKCorrelationType",
      @"HKDocumentType",
    ];
    factorySelectors = @[
      @"quantityTypeForIdentifier:",
      @"categoryTypeForIdentifier:",
      @"characteristicTypeForIdentifier:",
      @"correlationTypeForIdentifier:",
      @"documentTypeForIdentifier:",
    ];
  });

  for (NSUInteger i = 0; i < factoryClasses.count; i++) {
    Class cls = healthClassForName(factoryClasses[i]);
    SEL sel = NSSelectorFromString(factorySelectors[i]);
    if (!cls || ![cls respondsToSelector:sel]) {
      continue;
    }
    NSMethodSignature *sig = [cls methodSignatureForSelector:sel];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.target = cls;
    inv.selector = sel;
    [inv setArgument:&identifier atIndex:2];
    [inv invoke];
    // NSInvocation writes a raw +0 pointer, not a registered weak reference.
    // patternlint-disable-next-line fb-unsafe-unretained-considered-unsafe
    __unsafe_unretained id type = nil;
    [inv getReturnValue:&type];
    if (type) {
      return type;
    }
  }
  return nil;
}

static BOOL performHealthOperation(void (^operation)(void), NSError **error)
{
  @try {
    operation();
    return YES;
  } @catch (NSException *exception) {
    NSLog(@"[Health] Command raised: %@", exception);
    if (error) {
      *error = [NSError errorWithDomain:@"FBHealthSettingsException" code:1 userInfo:@{NSLocalizedDescriptionKey : exception.reason ?: exception.name}];
    }
    return NO;
  }
}

@interface FBHealthOperationResult ()
@property (nullable, nonatomic, readonly, strong) NSError *operationError;
- (instancetype)initWithSuccess:(BOOL)success error:(nullable NSError *)error completed:(BOOL)completed;
@end

@implementation FBHealthOperationResult
- (instancetype)initWithSuccess:(BOOL)success error:(NSError *)error completed:(BOOL)completed
{
  self = [super init];
  if (self) {
    _success = success;
    _operationError = error;
    _status = completed ? FBHealthCompletionStatusCompleted : FBHealthCompletionStatusTimedOut;
  }
  return self;
}

- (BOOL)hasError
{
  return self.operationError != nil;
}

- (id)readErrorValueWithError:(NSError **)error
{
  __block id value = nil;
  if (!performHealthOperation(^{ value = self.operationError.localizedDescription ?: [NSNull null]; }, error)) {
    return nil;
  }
  return value;
}

@end

@interface FBHealthCompletion : NSObject
- (void)completeWithResult:(FBHealthOperationResult *)result;
- (nullable FBHealthOperationResult *)wait;
@end

@implementation FBHealthCompletion
{
  dispatch_semaphore_t _semaphore;
  FBHealthOperationResult *_result;
}

- (instancetype)init
{
  self = [super init];
  if (self) {
    _semaphore = dispatch_semaphore_create(0);
  }
  return self;
}

- (void)completeWithResult:(FBHealthOperationResult *)result
{
  @synchronized(self) {
    if (_result) {
      return;
    }
    _result = result;
  }
  dispatch_semaphore_signal(_semaphore);
}

- (FBHealthOperationResult *)wait
{
  if (dispatch_semaphore_wait(_semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) != 0) {
    return nil;
  }
  @synchronized(self) {
    return _result;
  }
}

@end

@implementation FBHealthAuthorizationWrite
- (instancetype)initWithOperation:(FBHealthOperationResult *)operation
{
  self = [super init];
  if (self) {
    _operation = operation;
  }
  return self;
}

@end

static id readHealthRecordValue(id record, NSString *key)
{
  if (![record respondsToSelector:NSSelectorFromString(key)]) {
    return nil;
  }
  id value = [record valueForKey:key];
  if (!value || [value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) {
    return value;
  }
  return [NSString stringWithFormat:@"%@", value];
}

@implementation FBHealthAuthorizationRecord
- (instancetype)initWithRecord:(id)record
{
  self = [super init];
  if (self) {
    _identifier = readHealthRecordValue(record, @"identifier");
    _sharingAuthorizationAllowed = readHealthRecordValue(record, @"sharingAuthorizationAllowed");
    _readingAuthorizationAllowed = readHealthRecordValue(record, @"readingAuthorizationAllowed");
  }
  return self;
}

@end

@interface FBHealthRecordsResult ()
@property (nullable, nonatomic, readonly, strong) NSArray *records;
- (instancetype)initWithRecords:(nullable NSArray *)records error:(nullable NSError *)error completed:(BOOL)completed;
@end

@implementation FBHealthRecordsResult
- (instancetype)initWithRecords:(NSArray *)records error:(NSError *)error completed:(BOOL)completed
{
  self = [super initWithSuccess:NO error:error completed:completed];
  if (self) {
    _records = records;
  }
  return self;
}

- (NSArray<FBHealthAuthorizationRecord *> *)readRecordsWithError:(NSError **)error
{
  NSMutableArray<FBHealthAuthorizationRecord *> *values = [NSMutableArray array];
  if (!performHealthOperation(^{
    for (id record in self.records) {
      [values addObject:[[FBHealthAuthorizationRecord alloc] initWithRecord:record]];
    }
  }, error)) {
    return nil;
  }
  return values;
}

@end

@interface FBHealthTypeSelection ()
@property (nonatomic, strong) NSMutableSet *types;
@end

@implementation FBHealthTypeSelection
- (instancetype)init
{
  self = [super init];
  if (self) {
    _types = [NSMutableSet set];
  }
  return self;
}

- (BOOL)isEmpty
{
  return self.types.count == 0;
}

- (NSNumber *)resolveIdentifier:(NSString *)identifier error:(NSError **)error
{
  __block BOOL resolved = NO;
  if (!performHealthOperation(^{
    id type = resolveHealthKitObjectType(identifier);
    if (type) {
      [self.types addObject:type];
      resolved = YES;
    }
  }, error)) {
    return nil;
  }
  return @(resolved);
}

@end

@implementation FBHealthSettingsClient
{
  HKAuthorizationStore *_authorizationStore;
}

+ (instancetype)liveClient
{
  __block FBHealthSettingsClient *client = nil;
  performHealthOperation(^{
    HKAuthorizationStore *store = loadAuthStore();
    if (store) {
      client = [[self alloc] initWithAuthorizationStore:store];
    }
  }, nil);
  return client;
}

- (instancetype)initWithAuthorizationStore:(HKAuthorizationStore *)store
{
  self = [super init];
  if (self) {
    _authorizationStore = store;
  }
  return self;
}

- (FBHealthOperationResult *)seedAuthorizationForBundleIdentifier:(NSString *)bundleID selection:(FBHealthTypeSelection *)selection error:(NSError **)error
{
  __block FBHealthOperationResult *result = nil;
  if (!performHealthOperation(^{
    FBHealthCompletion *completion = [FBHealthCompletion new];
    [self->_authorizationStore setRequestedAuthorizationForBundleIdentifier:bundleID
                                                                 shareTypes:selection.types
                                                                  readTypes:selection.types
                                                                 completion:^(BOOL ok, NSError *_Nullable operationError) {
                                                                   [completion completeWithResult:[[FBHealthOperationResult alloc] initWithSuccess:ok error:operationError completed:YES]];
                                                                 }];
    result = [completion wait] ?: [[FBHealthOperationResult alloc] initWithSuccess:NO error:nil completed:NO];
  }, error)) {
    return nil;
  }
  return result;
}

- (FBHealthAuthorizationWrite *)setAuthorizationForBundleIdentifier:(NSString *)bundleID selection:(FBHealthTypeSelection *)selection status:(NSUInteger)status error:(NSError **)error
{
  __block FBHealthAuthorizationWrite *write = nil;
  if (!performHealthOperation(^{
    NSMutableDictionary *statuses = [NSMutableDictionary dictionary];
    for (id type in selection.types) {
      statuses[type] = @(status);
    }
    FBHealthCompletion *pending = [FBHealthCompletion new];
    void (^completion)(BOOL, NSError *_Nullable) = ^(BOOL ok, NSError *_Nullable operationError) {
      [pending completeWithResult:[[FBHealthOperationResult alloc] initWithSuccess:ok error:operationError completed:YES]];
    };
    if ([self->_authorizationStore respondsToSelector:@selector(setAuthorizationStatuses:authorizationModes:modeInfos:forBundleIdentifier:options:completion:)]) {
      [self->_authorizationStore setAuthorizationStatuses:statuses authorizationModes:@{} modeInfos:@{} forBundleIdentifier:bundleID options:0 completion:completion];
    } else if ([self->_authorizationStore respondsToSelector:@selector(setAuthorizationStatuses:authorizationModes:forBundleIdentifier:options:completion:)]) {
      [self->_authorizationStore setAuthorizationStatuses:statuses authorizationModes:@{} forBundleIdentifier:bundleID options:0 completion:completion];
    } else {
      write = [[FBHealthAuthorizationWrite alloc] initWithOperation:nil];
      return;
    }
    FBHealthOperationResult *result = [pending wait] ?: [[FBHealthOperationResult alloc] initWithSuccess:NO error:nil completed:NO];
    write = [[FBHealthAuthorizationWrite alloc] initWithOperation:result];
  }, error)) {
    return nil;
  }
  return write;
}

- (FBHealthOperationResult *)clearAuthorizationForBundleIdentifier:(NSString *)bundleID error:(NSError **)error
{
  __block FBHealthOperationResult *result = nil;
  if (!performHealthOperation(^{
    FBHealthCompletion *completion = [FBHealthCompletion new];
    [self->_authorizationStore resetAuthorizationStatusForBundleIdentifier:bundleID
                                                                completion:^(BOOL ok, NSError *_Nullable operationError) {
                                                                  [completion completeWithResult:[[FBHealthOperationResult alloc] initWithSuccess:ok error:operationError completed:YES]];
                                                                }];
    result = [completion wait] ?: [[FBHealthOperationResult alloc] initWithSuccess:NO error:nil completed:NO];
  }, error)) {
    return nil;
  }
  return result;
}

- (FBHealthRecordsResult *)fetchRecordsForBundleIdentifier:(NSString *)bundleID error:(NSError **)error
{
  __block FBHealthRecordsResult *result = nil;
  if (!performHealthOperation(^{
    FBHealthCompletion *completion = [FBHealthCompletion new];
    [self->_authorizationStore fetchAuthorizationRecordsForBundleIdentifier:bundleID
                                                                 completion:^(NSArray *_Nullable records, NSError *_Nullable operationError) {
                                                                   [completion completeWithResult:[[FBHealthRecordsResult alloc] initWithRecords:records error:operationError completed:YES]];
                                                                 }];
    result = (FBHealthRecordsResult *)[completion wait] ?: [[FBHealthRecordsResult alloc] initWithRecords:nil error:nil completed:NO];
  }, error)) {
    return nil;
  }
  return result;
}

@end
