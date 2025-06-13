/*
 * Unit test for idb_direct error mapping
 * Validates that all NSError codes properly map to idb_error_t
 */

#import <Foundation/Foundation.h>
#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBDeviceControl/FBDeviceControl.h>
#import "idb_direct_error_mapping.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        printf("idb_direct Error Mapping Test\n");
        printf("==============================\n\n");
        
        BOOL all_tests_passed = YES;
        
        // Test 1: Validate comprehensive error mapping
        printf("Test 1: Comprehensive Error Mapping Validation\n");
        printf("-----------------------------------------------\n");
        
        if (idb_validate_error_mapping()) {
            printf("✅ All error codes properly mapped\n");
        } else {
            printf("❌ Error mapping validation failed\n");
            all_tests_passed = NO;
        }
        printf("\n");
        
        // Test 2: Test specific NSError domain mappings
        printf("Test 2: NSError Domain Mapping Tests\n");
        printf("------------------------------------\n");
        
        NSArray* test_cases = @[
            @{@"domain": FBControlCoreErrorDomain, @"code": @(-1), @"expected": @(IDB_ERROR_INVALID_PARAMETER), @"description": @"FBControlCore invalid argument"},
            @{@"domain": FBControlCoreErrorDomain, @"code": @(-2), @"expected": @(IDB_ERROR_TIMEOUT), @"description": @"FBControlCore timeout"},
            @{@"domain": NSPOSIXErrorDomain, @"code": @(ENOENT), @"expected": @(IDB_ERROR_DEVICE_NOT_FOUND), @"description": @"POSIX no such file"},
            @{@"domain": NSPOSIXErrorDomain, @"code": @(EACCES), @"expected": @(IDB_ERROR_PERMISSION_DENIED), @"description": @"POSIX permission denied"},
            @{@"domain": NSPOSIXErrorDomain, @"code": @(ENOMEM), @"expected": @(IDB_ERROR_OUT_OF_MEMORY), @"description": @"POSIX out of memory"},
            @{@"domain": NSCocoaErrorDomain, @"code": @(NSFileNoSuchFileError), @"expected": @(IDB_ERROR_DEVICE_NOT_FOUND), @"description": @"Cocoa file not found"},
            @{@"domain": NSCocoaErrorDomain, @"code": @(NSFileReadNoPermissionError), @"expected": @(IDB_ERROR_PERMISSION_DENIED), @"description": @"Cocoa permission denied"},
        ];
        
        for (NSDictionary* test_case in test_cases) {
            NSError* error = [NSError errorWithDomain:test_case[@"domain"] 
                                              code:[test_case[@"code"] integerValue]
                                          userInfo:nil];
            
            idb_error_t result = idb_map_nserror_to_idb_error(error);
            idb_error_t expected = [test_case[@"expected"] intValue];
            
            if (result == expected) {
                printf("✅ %s: %ld -> %d\n", [test_case[@"description"] UTF8String], [test_case[@"code"] integerValue], result);
            } else {
                printf("❌ %s: Expected %d, got %d\n", [test_case[@"description"] UTF8String], expected, result);
                all_tests_passed = NO;
            }
        }
        printf("\n");
        
        // Test 3: Test error string completeness
        printf("Test 3: Error String Completeness\n");
        printf("---------------------------------\n");
        
        idb_error_t all_errors[] = {
            IDB_SUCCESS,
            IDB_ERROR_NOT_INITIALIZED,
            IDB_ERROR_INVALID_PARAMETER,
            IDB_ERROR_DEVICE_NOT_FOUND,
            IDB_ERROR_SIMULATOR_NOT_RUNNING,
            IDB_ERROR_OPERATION_FAILED,
            IDB_ERROR_TIMEOUT,
            IDB_ERROR_OUT_OF_MEMORY,
            IDB_ERROR_NOT_IMPLEMENTED,
            IDB_ERROR_UNSUPPORTED,
            IDB_ERROR_PERMISSION_DENIED,
            IDB_ERROR_APP_NOT_FOUND,
            IDB_ERROR_INVALID_APP_BUNDLE,
        };
        
        size_t num_errors = sizeof(all_errors) / sizeof(all_errors[0]);
        
        for (size_t i = 0; i < num_errors; i++) {
            const char* error_string = idb_detailed_error_string(all_errors[i]);
            
            if (strcmp(error_string, "Unknown error") != 0 || all_errors[i] == IDB_SUCCESS) {
                printf("✅ Error %d: \"%s\"\n", all_errors[i], error_string);
            } else {
                printf("❌ Error %d: Missing error string\n", all_errors[i]);
                all_tests_passed = NO;
            }
        }
        printf("\n");
        
        // Test 4: Test nil error handling
        printf("Test 4: Nil Error Handling\n");
        printf("--------------------------\n");
        
        idb_error_t nil_result = idb_map_nserror_to_idb_error(nil);
        if (nil_result == IDB_SUCCESS) {
            printf("✅ Nil NSError maps to IDB_SUCCESS\n");
        } else {
            printf("❌ Nil NSError should map to IDB_SUCCESS, got %d\n", nil_result);
            all_tests_passed = NO;
        }
        printf("\n");
        
        // Test 5: Test unknown error handling
        printf("Test 5: Unknown Error Handling\n");
        printf("------------------------------\n");
        
        NSError* unknown_error = [NSError errorWithDomain:@"com.unknown.domain" code:12345 userInfo:nil];
        idb_error_t unknown_result = idb_map_nserror_to_idb_error(unknown_error);
        
        if (unknown_result == IDB_ERROR_OPERATION_FAILED) {
            printf("✅ Unknown NSError maps to IDB_ERROR_OPERATION_FAILED\n");
        } else {
            printf("❌ Unknown NSError should map to IDB_ERROR_OPERATION_FAILED, got %d\n", unknown_result);
            all_tests_passed = NO;
        }
        printf("\n");
        
        // Summary
        printf("Test Summary\n");
        printf("============\n");
        if (all_tests_passed) {
            printf("✅ All error mapping tests passed!\n");
            printf("🎯 Error mapping system is comprehensive and reliable\n");
            return 0;
        } else {
            printf("❌ Some error mapping tests failed\n");
            printf("🔍 Review error mapping implementation\n");
            return 1;
        }
    }
}