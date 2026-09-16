/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "DeliveredNotificationsService.h"
#import "DeliveredNotificationsService+Testing.h"

#import <dlfcn.h>
#import <errno.h>
#import <string.h>

#import <UserNotifications/UserNotifications.h>

#import "KeyedArchivePrivate.h"
#import "UserNotificationsPrivate.h"

/**
 * A center bound to another app's bundle identifier.
 *
 * `+currentNotificationCenter` is scoped to the calling process, which is never the
 * app under test, so it would always report nothing. The private initialiser is the
 * only way to ask about another bundle, and UserNotifications answers it for any
 * bundle that has registered notification settings.
 */
static id<FBDeliveredNotificationsCenter> CenterForBundleID(NSString *bundleID)
{
  Class centerClass = NSClassFromString(@"UNUserNotificationCenter");
  if (!centerClass) {
    NSLog(@"[DeliveredNotifications] UNUserNotificationCenter class not found");
    return nil;
  }
  if (![centerClass instancesRespondToSelector:@selector(initWithBundleIdentifier:)]) {
    NSLog(@"[DeliveredNotifications] UNUserNotificationCenter has no initWithBundleIdentifier:");
    return nil;
  }
  // Declaring the selector says what its signature is if the runtime has it, not that the
  // runtime will accept this bundle: it raises for one with no registered notification
  // settings, and nothing above this has a handler, so an uncaught raise ends the guest
  // before the store fallback the caller has for exactly that case.
  UNUserNotificationCenter *center = nil;
  @try {
    center = [[centerClass alloc] initWithBundleIdentifier:bundleID];
  } @catch (NSException *exception) {
    NSLog(@"[DeliveredNotifications] initWithBundleIdentifier: raised for %@: %@", bundleID, exception);
    return nil;
  }
  if (!center) {
    NSLog(@"[DeliveredNotifications] No notification center for %@", bundleID);
    return nil;
  }
  return (id<FBDeliveredNotificationsCenter>)center;
}

/**
 * Maps one delivered notification to the JSON object printed for it.
 *
 * These keys are the ones the client's model reads, and the store below prints the same
 * set. A key only one of the two paths emits is one they can come to disagree on without
 * anything noticing, since no reader would be looking at it.
 */
static NSDictionary<NSString *, id> *NotificationJSONObject(UNNotification *notification, NSString *bundleID)
{
  UNNotificationRequest *request = notification.request;
  UNNotificationContent *content = request.content;
  NSMutableDictionary<NSString *, id> *object = [NSMutableDictionary dictionary];
  object[@"bundleID"] = bundleID ?: @"";
  object[@"identifier"] = request.identifier ?: @"";
  object[@"title"] = content.title ?: @"";
  object[@"subtitle"] = content.subtitle ?: @"";
  object[@"body"] = content.body ?: @"";
  object[@"threadIdentifier"] = content.threadIdentifier ?: @"";
  if (notification.date) {
    object[@"date"] = @([notification.date timeIntervalSince1970]);
  }
  return object;
}

/**
 * Prints one record as a line of JSON, which is the whole of what this service writes.
 *
 * Answers whether it did. A record that will not serialise is one the caller has to fail
 * on rather than pass over: the value that stops it is one the device supplied -- a
 * non-finite date is enough -- and skipping it returns a list shorter than the app's
 * without saying so.
 */
static BOOL PrintJSONLine(NSDictionary<NSString *, id> *object)
{
  // Asked before serialising rather than after, because a value NSJSONSerialization will not
  // write makes it raise rather than answer an error: an infinite date reaches it as
  // "Invalid number value (infinite) in JSON write", and nothing above here has a handler.
  if (![NSJSONSerialization isValidJSONObject:object]) {
    NSLog(
      @"[DeliveredNotifications] Notification %@ holds a value JSON cannot represent, such as a non-finite date",
      object[@"identifier"]
    );
    return NO;
  }
  NSError *error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
  if (!data) {
    NSLog(@"[DeliveredNotifications] Could not serialise notification %@: %@", object[@"identifier"], error);
    return NO;
  }
  // Written as the bytes serialisation produced rather than back through an NSString, whose
  // UTF8String printf would take as a null pointer if the conversion ever answered nil.
  //
  // The writes are checked because stdout here is a block-buffered pipe -- the guest is run
  // under `simctl spawn` -- so a record that serialised can still fail to reach the caller,
  // and an unchecked write would drop it from a list the exit code calls complete.
  if (fwrite(data.bytes, 1, data.length, stdout) != data.length || fputc('\n', stdout) == EOF) {
    NSLog(
      @"[DeliveredNotifications] Could not write notification %@ to stdout: %s",
      object[@"identifier"],
      strerror(errno)
    );
    return NO;
  }
  return YES;
}

/**
 * Pushes what was printed to the caller, answering whether it arrived.
 *
 * stdout here is a block-buffered pipe, so records sit in the buffer until the guest exits
 * and the implicit flush happens where nothing can still change the exit code. Answering 0
 * on a flush that failed would report a truncated list as a complete one.
 */
static BOOL FlushedStdout(void)
{
  if (fflush(stdout) != 0) {
    NSLog(@"[DeliveredNotifications] Could not flush stdout: %s", strerror(errno));
    return NO;
  }
  return YES;
}

/**
 * A keyed archive read as a plain property list: the `$objects` pool plus the index
 * of its root. Reading it this way rather than through `NSKeyedUnarchiver` is what
 * lets this process read an archive written by another one, whose classes it does
 * not have.
 */
typedef struct {
  NSArray *objects;
  NSUInteger rootIndex;
  BOOL valid;
  // No file at that path at all. A store that was never written and one that could
  // not be read are both invalid, and a reader has to answer them differently.
  BOOL absent;
} FBKeyedArchive;

static BOOL IsArchiveReference(id object, NSUInteger *index)
{
  static FBKeyedArchiverUIDGetTypeIDFn getTypeID;
  static FBKeyedArchiverUIDGetValueFn getValue;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    getTypeID = (FBKeyedArchiverUIDGetTypeIDFn)dlsym(RTLD_DEFAULT, "_CFKeyedArchiverUIDGetTypeID");
    getValue = (FBKeyedArchiverUIDGetValueFn)dlsym(RTLD_DEFAULT, "_CFKeyedArchiverUIDGetValue");
    if (!getTypeID || !getValue) {
      NSLog(@"[DeliveredNotifications] CoreFoundation does not export the keyed-archive UID accessors; no archive can be read");
    }
  });
  if (!object || !getTypeID || !getValue) {
    return NO;
  }
  if (CFGetTypeID((__bridge CFTypeRef)object) != getTypeID()) {
    return NO;
  }
  if (index) {
    *index = getValue((__bridge const void *)object);
  }
  return YES;
}

/** Follows `object` if it is a reference, otherwise returns it unchanged. */
static id ResolveArchiveObject(FBKeyedArchive archive, id object)
{
  NSUInteger index = 0;
  if (!IsArchiveReference(object, &index)) {
    return object;
  }
  return index < archive.objects.count ? archive.objects[index] : nil;
}

/**
 * Whether `error` says there is nothing at the path, as against something that is there and
 * would not open.
 *
 * Only the first is absent. A store denied by permissions, failing to read, or shadowed by a
 * directory is one this process cannot answer for, and reporting it as absent is the silent
 * "no notifications" the absent flag exists to prevent.
 */
static BOOL IsNoSuchFileError(NSError *error)
{
  if ([error.domain isEqualToString:NSCocoaErrorDomain]) {
    return error.code == NSFileReadNoSuchFileError;
  }
  if ([error.domain isEqualToString:NSPOSIXErrorDomain]) {
    return error.code == ENOENT;
  }
  return NO;
}

static FBKeyedArchive ReadKeyedArchive(NSString *filePath)
{
  FBKeyedArchive archive = {.objects = nil, .rootIndex = 0, .valid = NO, .absent = NO};
  NSError *readError = nil;
  NSData *data = [NSData dataWithContentsOfFile:filePath options:0 error:&readError];
  if (!data) {
    archive.absent = IsNoSuchFileError(readError);
    if (!archive.absent) {
      NSLog(@"[DeliveredNotifications] %@ could not be read: %@", filePath.lastPathComponent, readError);
    }
    return archive;
  }
  NSError *error = nil;
  id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error];
  if (![plist isKindOfClass:NSDictionary.class]) {
    NSLog(@"[DeliveredNotifications] %@ is not a property list: %@", filePath.lastPathComponent, error);
    return archive;
  }
  NSDictionary *root = plist;
  id objects = root[@"$objects"];
  id top = root[@"$top"];
  if (![objects isKindOfClass:NSArray.class] || ![top isKindOfClass:NSDictionary.class]) {
    return archive;
  }
  NSUInteger rootIndex = 0;
  if (!IsArchiveReference(((NSDictionary *)top)[@"root"], &rootIndex)) {
    return archive;
  }
  archive.objects = objects;
  archive.rootIndex = rootIndex;
  archive.valid = YES;
  return archive;
}

static id ArchiveRootObject(FBKeyedArchive archive)
{
  if (!archive.valid || archive.rootIndex >= archive.objects.count) {
    return nil;
  }
  return archive.objects[archive.rootIndex];
}

/**
 * Rebuilds an archived dictionary from its parallel `NS.keys` / `NS.objects` arrays.
 *
 * `lossy` is set when the reconstruction dropped something -- the two arrays disagreeing on
 * length, or a key that did not resolve to a string. The entries that did reconstruct are
 * still returned, but a caller cannot read a missing one as an entry the archive did not
 * hold, which is the difference between an app having received nothing and this reader
 * having failed to say what it received.
 */
static NSDictionary<NSString *, id> *ArchivedDictionary(FBKeyedArchive archive, id candidate, BOOL *lossy)
{
  if (![candidate isKindOfClass:NSDictionary.class]) {
    return nil;
  }
  NSDictionary *encoded = candidate;
  id keys = encoded[@"NS.keys"];
  id values = encoded[@"NS.objects"];
  if (![keys isKindOfClass:NSArray.class] || ![values isKindOfClass:NSArray.class]) {
    return nil;
  }
  NSArray *keyReferences = keys;
  NSArray *valueReferences = values;
  if (keyReferences.count != valueReferences.count) {
    *lossy = YES;
  }
  NSMutableDictionary<NSString *, id> *result = [NSMutableDictionary dictionary];
  for (NSUInteger index = 0; index < MIN(keyReferences.count, valueReferences.count); index++) {
    id key = ResolveArchiveObject(archive, keyReferences[index]);
    if (![key isKindOfClass:NSString.class]) {
      *lossy = YES;
      continue;
    }
    id value = ResolveArchiveObject(archive, valueReferences[index]);
    if (!value) {
      // An index outside `$objects`. The archive's own placeholder for nothing resolves to a
      // value rather than nil, so this is a reference that does not point at anything, and
      // the subscript below would drop the key without recording that it had.
      *lossy = YES;
      continue;
    }
    result[key] = value;
  }
  return result;
}

/**
 * The archive's placeholder for nothing, which is what an empty slot resolves to.
 *
 * Anything else that will not decode is a record that is there and unreadable, as against
 * one that was never written, and the two have to be answered differently.
 */
static BOOL IsArchiveNullPlaceholder(id object)
{
  return [object isKindOfClass:NSString.class] && [(NSString *)object isEqualToString:@"$null"];
}

static NSString *gDirectoryForTesting = nil;

void FBDeliveredNotificationsSetDirectoryForTesting(NSString *directory)
{
  gDirectoryForTesting = [directory copy];
}

static NSString *NotificationsDirectory(void)
{
  if (gDirectoryForTesting) {
    return gDirectoryForTesting;
  }
  NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
  NSString *library = paths.firstObject;
  return library ? [library stringByAppendingPathComponent:@"UserNotifications"] : nil;
}

/**
 * `Library.plist` maps a bundle identifier to the directory holding its store.
 *
 * Returns nil for a bundle the mapping does not name, and for a mapping that could not be
 * read or that names this bundle with something other than a string. `unreadable` is set
 * in the latter two: only a mapping that is readable and simply silent about this bundle
 * means it has had nothing delivered.
 */
static NSString *StoreDirectoryForBundleID(NSString *bundleID, BOOL *unreadable)
{
  NSString *notificationsDirectory = NotificationsDirectory();
  if (!notificationsDirectory) {
    NSLog(@"[DeliveredNotifications] No Library directory, so no notification store");
    *unreadable = YES;
    return nil;
  }
  NSString *libraryPath = [notificationsDirectory stringByAppendingPathComponent:@"Library.plist"];
  FBKeyedArchive archive = ReadKeyedArchive(libraryPath);
  if (!archive.valid) {
    // Absent is the shape of a simulator nothing has ever been delivered on.
    if (!archive.absent) {
      NSLog(@"[DeliveredNotifications] %@ could not be read as a keyed archive", libraryPath);
      *unreadable = YES;
    }
    return nil;
  }
  id mappingRoot = ArchiveRootObject(archive);
  if (IsArchiveNullPlaceholder(mappingRoot)) {
    // The same shape the per-app store takes when it holds nothing: a well-formed archive
    // whose root is the placeholder for nothing. An empty mapping names no store for this
    // bundle, which is the readable-and-silent case rather than a mapping that could not
    // be read, so it means nothing was delivered rather than that this reader failed.
    NSLog(@"[DeliveredNotifications] %@ names no store for any bundle", libraryPath);
    return nil;
  }
  BOOL mappingLossy = NO;
  NSDictionary<NSString *, id> *mapping = ArchivedDictionary(archive, mappingRoot, &mappingLossy);
  if (!mapping) {
    NSLog(@"[DeliveredNotifications] %@ holds no archived mapping", libraryPath);
    *unreadable = YES;
    return nil;
  }
  if (mappingLossy) {
    // A mapping that did not reconstruct in full cannot be read as silence about this
    // bundle: the entry that was dropped may be the one naming its store, and answering
    // "nothing delivered" on that basis would be a guess.
    NSLog(@"[DeliveredNotifications] %@ did not reconstruct in full", libraryPath);
    *unreadable = YES;
    return nil;
  }
  id directory = mapping[bundleID];
  if ([directory isKindOfClass:NSString.class]) {
    return directory;
  }
  if (directory) {
    // Named, but not by a string: the mapping is corrupt rather than silent about this
    // bundle, and answering "nothing delivered" for it would be a guess.
    NSLog(@"[DeliveredNotifications] Library.plist names a non-string store directory for %@", bundleID);
    *unreadable = YES;
    return nil;
  }
  NSLog(@"[DeliveredNotifications] Library.plist names no store directory for %@", bundleID);
  return nil;
}

/**
 * The string at `key`, or `@""` where the record carries none.
 *
 * A key the record does not hold, and one holding the archive's placeholder for nothing, are
 * both legitimately empty: a notification with no subtitle is an ordinary notification. A key
 * holding something that is not a string is format drift instead, and sets `retyped` --
 * answering `@""` for it would print a blank where the notification had a value, which is the
 * same wrong answer reported as a right one that the rest of this file refuses.
 */
static NSString *ArchivedString(NSDictionary<NSString *, id> *fields, NSString *key, BOOL *retyped)
{
  id value = fields[key];
  if (!value || IsArchiveNullPlaceholder(value)) {
    return @"";
  }
  if (![value isKindOfClass:NSString.class]) {
    *retyped = YES;
    return @"";
  }
  return value;
}

/**
 * Prints the records the store holds for `bundleID`, one JSON object per line.
 *
 * A store that could not be read answers 1 rather than 0, so that it is not reported as
 * an app having received nothing. The case that makes this matter is the private CF UID
 * accessors going unresolved: every archive then reads as invalid, and a silent 0 would
 * report every bundle as having no notifications for as long as that held.
 *
 * A record that could not be reported -- one that will not decode, or one that decodes and
 * will not serialise -- answers 1 for the same reason, after printing the ones that were:
 * a short list returned as a complete one reads as an app having received less than it did,
 * which is the same wrong answer arrived at one record at a time.
 */
static int PrintDeliveredNotificationsFromStore(NSString *bundleID)
{
  BOOL unreadable = NO;
  NSString *directory = StoreDirectoryForBundleID(bundleID, &unreadable);
  if (!directory) {
    return unreadable ? 1 : 0;
  }
  NSString *storePath = [[NotificationsDirectory()
                          stringByAppendingPathComponent:directory]
                         stringByAppendingPathComponent:@"DeliveredNotifications.plist"];
  FBKeyedArchive archive = ReadKeyedArchive(storePath);
  if (!archive.valid) {
    if (archive.absent) {
      return 0;
    }
    NSLog(@"[DeliveredNotifications] %@ could not be read as a keyed archive", storePath);
    return 1;
  }
  id root = ArchiveRootObject(archive);
  if (IsArchiveNullPlaceholder(root)) {
    // How a store that has never held a notification is written: a well-formed archive
    // whose root is the placeholder for nothing. That is an app that received nothing,
    // not a store this reader could not understand, and it is the common case -- every
    // app on a fresh simulator is in it.
    return FlushedStdout() ? 0 : 1;
  }
  if (![root isKindOfClass:NSDictionary.class]) {
    NSLog(@"[DeliveredNotifications] %@ holds no archived root dictionary", storePath);
    return 1;
  }
  id recordReferences = ((NSDictionary *)root)[@"NS.objects"];
  if (![recordReferences isKindOfClass:NSArray.class]) {
    NSLog(@"[DeliveredNotifications] Archived root in %@ has no NS.objects array", storePath);
    return 1;
  }
  NSArray *references = recordReferences;
  NSUInteger unreportedCount = 0;
  for (id reference in references) {
    id record = ResolveArchiveObject(archive, reference);
    BOOL fieldsLossy = NO;
    NSDictionary<NSString *, id> *fields = ArchivedDictionary(archive, record, &fieldsLossy);
    if (fields.count == 0) {
      if (IsArchiveNullPlaceholder(record)) {
        continue;
      }
      NSLog(
        @"[DeliveredNotifications] Could not decode a record in %@: %@",
        storePath,
        record ? NSStringFromClass([record class]) : @"a reference to nothing"
      );
      unreportedCount++;
      continue;
    }
    if (fieldsLossy) {
      NSLog(@"[DeliveredNotifications] A record in %@ did not reconstruct in full", storePath);
      unreportedCount++;
      continue;
    }
    id identifier = fields[@"AppNotificationIdentifier"];
    if (![identifier isKindOfClass:NSString.class] || IsArchiveNullPlaceholder(identifier)) {
      // Every delivered record carries one, so a record without it decoded into fields this
      // reader does not recognise -- a renamed key rather than a notification with nothing
      // in it. Printing it would answer with a blank notification and call that success.
      NSLog(@"[DeliveredNotifications] A record in %@ carries no notification identifier", storePath);
      unreportedCount++;
      continue;
    }
    BOOL retyped = NO;
    NSMutableDictionary<NSString *, id> *object = [NSMutableDictionary dictionary];
    object[@"bundleID"] = bundleID;
    object[@"identifier"] = identifier;
    object[@"title"] = ArchivedString(fields, @"AppNotificationTitle", &retyped);
    object[@"subtitle"] = ArchivedString(fields, @"AppNotificationSubtitle", &retyped);
    object[@"body"] = ArchivedString(fields, @"AppNotificationMessage", &retyped);
    object[@"threadIdentifier"] = ArchivedString(fields, @"SBSPushStoreNotificationThreadKey", &retyped);
    id date = fields[@"AppNotificationCreationDate"];
    if (date && !IsArchiveNullPlaceholder(date)) {
      id interval = [date isKindOfClass:NSDictionary.class] ? ((NSDictionary *)date)[@"NS.time"] : nil;
      if ([interval isKindOfClass:NSNumber.class]) {
        // Archived as an interval from the Apple reference date.
        object[@"date"] = @([[NSDate dateWithTimeIntervalSinceReferenceDate:[interval doubleValue]] timeIntervalSince1970]);
      } else {
        // Carried, but not in a shape this reader knows. Dropping the key would report a
        // notification that has a date as one that does not.
        retyped = YES;
      }
    }
    if (retyped) {
      NSLog(
        @"[DeliveredNotifications] A record in %@ carries a field this reader does not recognise",
        storePath
      );
      unreportedCount++;
      continue;
    }
    if (!PrintJSONLine(object)) {
      unreportedCount++;
    }
  }
  if (unreportedCount > 0) {
    NSLog(
      @"[DeliveredNotifications] %lu of %lu records in %@ could not be reported; failing rather than returning a short list",
      (unsigned long)unreportedCount,
      (unsigned long)references.count,
      storePath
    );
    return 1;
  }
  return FlushedStdout() ? 0 : 1;
}

static BOOL IsDeliveredAction(NSString *action)
{
  return [action isEqualToString:@"delivered"];
}

int handleDeliveredNotificationsAction(NSString *action, NSString *bundleID)
{
  // Empty as well as nil: an unset proto3 string arrives as the empty one, and the mapping
  // names no store for it, which the store read cannot tell from an app that received
  // nothing. Answering 0 there would report a malformed request as an empty inbox.
  if (bundleID.length == 0) {
    NSLog(@"[DeliveredNotifications] bundleID required for %@", action);
    return 1;
  }
  if (!IsDeliveredAction(action)) {
    NSLog(@"[DeliveredNotifications] Unknown action: %@. Use delivered.", action);
    return 1;
  }
  id<FBDeliveredNotificationsCenter> center = CenterForBundleID(bundleID);
  if (!center) {
    // The store holds the same records, so a guest whose UserNotifications will not
    // hand one out still answers rather than failing.
    NSLog(@"[DeliveredNotifications] No center for %@; reading the store", bundleID);
    return PrintDeliveredNotificationsFromStore(bundleID);
  }
  return handleDeliveredNotificationsActionWithCenter(action, bundleID, center);
}

static const NSTimeInterval kDeliveredNotificationsTimeout = 30;

static NSTimeInterval gTimeoutForTesting = 0;

void FBDeliveredNotificationsSetTimeoutForTesting(NSTimeInterval timeout)
{
  gTimeoutForTesting = timeout;
}

int handleDeliveredNotificationsActionWithCenter(NSString *action,
                                                 NSString *bundleID,
                                                 id<FBDeliveredNotificationsCenter> center
)
{
  if (!IsDeliveredAction(action)) {
    NSLog(@"[DeliveredNotifications] Unknown action: %@. Use delivered.", action);
    return 1;
  }

  // The completion handler runs on an internal queue, so block until it has. It is also
  // still live after a timeout gives up on it, so it writes into a container it owns a
  // reference to rather than into this frame: a late handler then fills something nobody
  // reads, and everything it holds goes when the daemon releases it.
  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
  NSMutableArray<UNNotification *> *received = [NSMutableArray array];
  @try {
    [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *notifications) {
      if (notifications.count > 0) {
        [received addObjectsFromArray:notifications];
      }
      dispatch_semaphore_signal(semaphore);
    }];
  } @catch (NSException *exception) {
    // The store holds the same records, so a runtime that refuses the send still answers.
    NSLog(@"[DeliveredNotifications] getDeliveredNotificationsWithCompletionHandler: raised for %@: %@; reading the store", bundleID, exception);
    return PrintDeliveredNotificationsFromStore(bundleID);
  }
  NSTimeInterval timeout = gTimeoutForTesting > 0 ? gTimeoutForTesting : kDeliveredNotificationsTimeout;
  if (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))) != 0) {
    // The store holds the same records, so a center that has not come back is the degraded
    // case the others here already answer from disk for rather than failing on.
    NSLog(@"[DeliveredNotifications] Timed out reading notifications for %@; reading the store", bundleID);
    return PrintDeliveredNotificationsFromStore(bundleID);
  }
  if (received.count > 0) {
    NSUInteger unreportedCount = 0;
    for (UNNotification *notification in received) {
      if (!PrintJSONLine(NotificationJSONObject(notification, bundleID))) {
        unreportedCount++;
      }
    }
    if (unreportedCount > 0) {
      // The same short list the store read refuses to return, reached from the other side.
      // Falling back to the store here would not help: it holds the same records, so a value
      // the center could not serialise is one the store cannot either.
      NSLog(
        @"[DeliveredNotifications] %lu of %lu notifications for %@ could not be reported; failing rather than returning a short list",
        (unsigned long)unreportedCount,
        (unsigned long)received.count,
        bundleID
      );
      return 1;
    }
    return FlushedStdout() ? 0 : 1;
  }

  // UserNotifications answers for the calling process's own scope in some
  // configurations, reporting nothing for another bundle even when that bundle has
  // notifications. The delivered-notification store is the same data on disk, so
  // fall back to it rather than reporting an empty list that is not true.
  NSLog(@"[DeliveredNotifications] Center reported none for %@; reading the store", bundleID);
  return PrintDeliveredNotificationsFromStore(bundleID);
}
