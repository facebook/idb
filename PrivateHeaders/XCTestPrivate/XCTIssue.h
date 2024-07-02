
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 * @enum XCTIssueType
 * Types of failures and other issues that can be reported for tests.
 */
typedef NS_ENUM(NSInteger, XCTIssueType) {
  /// Issue raised by a failed XCTAssert or related API.
  XCTIssueTypeAssertionFailure = 0,
  /// Issue raised by the test throwing an error in Swift. This could also occur if an Objective C test is implemented in the form `- (BOOL)testFoo:(NSError **)outError` and returns NO with a non-nil out error.
  XCTIssueTypeThrownError = 1,
  /// Code in the test throws and does not catch an exception, Objective C, C++, or other.
  XCTIssueTypeUncaughtException = 2,
  /// One of the XCTestCase(measure:) family of APIs detected a performance regression.
  XCTIssueTypePerformanceRegression = 3,
  /// One of the framework APIs failed internally. For example, XCUIApplication was unable to launch or terminate an app or XCUIElementQuery was unable to complete a query.
  XCTIssueTypeSystem = 4,
  /// Issue raised when XCTExpectFailure is used but no matching issue is recorded.
  XCTIssueTypeUnmatchedExpectedFailure = 5,
};

@class XCTAttachment;
@class XCTSourceCodeContext;

/*!
 * @class XCTIssue
 * Encapsulates all data concerning a test failure or other issue.
 */
@interface XCTIssue : NSObject <NSCopying, NSMutableCopying, NSSecureCoding>

- (instancetype)initWithType:(XCTIssueType)type
          compactDescription:(NSString *)compactDescription
         detailedDescription:(nullable NSString *)detailedDescription
           sourceCodeContext:(XCTSourceCodeContext *)sourceCodeContext
             associatedError:(nullable NSError *)associatedError
                 attachments:(NSArray<XCTAttachment *> *)attachments NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithType:(XCTIssueType)type compactDescription:(NSString *)compactDescription;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// The type of the issue.
@property (readonly) XCTIssueType type;

/// A concise description of the issue, expected to be free of transient data and suitable for use in test run
/// summaries and for aggregation of results across multiple test runs.
@property (readonly, copy) NSString *compactDescription;

/// A detailed description of the issue designed to help diagnose the issue. May include transient data such as
/// numbers, object identifiers, timestamps, etc.
@property (readonly, copy, nullable) NSString *detailedDescription;

/// The source code location (file and line number) and the call stack associated with the issue.
@property (readonly, strong) XCTSourceCodeContext *sourceCodeContext;

/// Error associated with the issue.
@property (readonly, strong, nullable) NSError *associatedError;

/// All attachments associated with the issue.
@property (readonly, copy) NSArray<XCTAttachment *> *attachments;

@end

/*!
 * @class XCTMutableIssue
 * Mutable variant of XCTIssue, suitable for modifying by overrides in the reporting chain.
 */
@interface XCTMutableIssue : XCTIssue

@property (readwrite) XCTIssueType type;
@property (readwrite, copy) NSString *compactDescription;
@property (readwrite, copy, nullable) NSString *detailedDescription;
@property (readwrite, strong) XCTSourceCodeContext *sourceCodeContext;
@property (readwrite, strong, nullable) NSError *associatedError;
@property (readwrite, copy) NSArray<XCTAttachment *> *attachments;

/// Add an attachment to this issue.
- (void)addAttachment:(XCTAttachment *)attachment;

@end

NS_ASSUME_NONNULL_END


#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 * @class XCTSourceCodeLocation
 * Contains a file URL and line number representing a distinct location in source code related to a run of a test.
 */
__attribute__((objc_subclassing_restricted))
@interface XCTSourceCodeLocation : NSObject <NSSecureCoding>

- (instancetype)initWithFileURL:(NSURL *)fileURL lineNumber:(NSInteger)lineNumber NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFilePath:(NSString *)filePath lineNumber:(NSInteger)lineNumber;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (readonly) NSURL *fileURL;
@property (readonly) NSInteger lineNumber;

@end

/*!
 * @class XCTSourceCodeSymbolInfo
 * Contains symbolication information for a given frame in a call stack.
 */
__attribute__((objc_subclassing_restricted))
@interface XCTSourceCodeSymbolInfo : NSObject <NSSecureCoding>

- (instancetype)initWithImageName:(NSString *)imageName
                       symbolName:(NSString *)symbolName
                         location:(nullable XCTSourceCodeLocation *)location NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (readonly, copy) NSString *imageName;
@property (readonly, copy) NSString *symbolName;
@property (readonly, nullable) XCTSourceCodeLocation *location;

@end

/*!
 * @class XCTSourceCodeFrame
 * Represents a single frame in a call stack and supports retrieval of symbol information for the address.
 */
__attribute__((objc_subclassing_restricted))
@interface XCTSourceCodeFrame : NSObject <NSSecureCoding>

- (instancetype)initWithAddress:(uint64_t)address symbolInfo:(nullable XCTSourceCodeSymbolInfo *)symbolInfo NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithAddress:(uint64_t)address;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (readonly) uint64_t address;

@property (readonly, nullable) XCTSourceCodeSymbolInfo *symbolInfo;

/// Error previously returned for symbolication attempt. This is not serialized when the frame is encoded.
@property (readonly, nullable) NSError *symbolicationError;

/*!
 * method -symbolInfoWithError:
 * Attempts to get symbol information for the address. This can fail if required symbol data is not available. Only
 * one attempt will be made and the error will be stored and returned for future requests.
 */
- (nullable XCTSourceCodeSymbolInfo *)symbolInfoWithError:(NSError **)outError;

@end

/*!
 * @class XCTSourceCodeContext
 * Call stack and optional specific location - which may or may not be also included in the call stack
 * providing context around a point of execution in a test.
 */
__attribute__((objc_subclassing_restricted))
@interface XCTSourceCodeContext : NSObject <NSSecureCoding>

- (instancetype)initWithCallStack:(NSArray<XCTSourceCodeFrame *> *)callStack
                         location:(nullable XCTSourceCodeLocation *)location NS_DESIGNATED_INITIALIZER;

/// The call stack addresses could be those from NSThread.callStackReturnAddresses,
/// NSException.callStackReturnAddresses, or another source.
- (instancetype)initWithCallStackAddresses:(NSArray<NSNumber *> *)callStackAddresses
                                  location:(nullable XCTSourceCodeLocation *)location;

/// Initializes a new instance with call stack derived from NSThread.callStackReturnAddresses and the specified location.
- (instancetype)initWithLocation:(nullable XCTSourceCodeLocation *)location;

/// Initializes a new instance with call stack derived from NSThread.callStackReturnAddresses and a nil location.
- (instancetype)init;

@property (readonly, copy) NSArray<XCTSourceCodeFrame *> *callStack;
@property (readonly, nullable) XCTSourceCodeLocation *location;

@end

NS_ASSUME_NONNULL_END


