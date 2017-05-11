//******************************************************************************
//
// Copyright (c) 2016 Microsoft Corporation. All rights reserved.
//
// This code is licensed under the MIT License (MIT).
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
//******************************************************************************

#include <TestFramework.h>
#include <Foundation/Foundation.h>
#include <cmath>

static const NSTimeInterval c_testDownloadTimeoutInSec = 30;

typedef NS_ENUM(NSInteger, NSURLSessionAllDelegateType) {
    NSURLSessionDelegateWillPerformHTTPRedirection,
    NSURLSessionDelegateDidCompleteWithError,
    NSURLSessionDataDelegateDidReceiveResponse,
    NSURLSessionDataDelegateDidReceiveData,
    NSURLSessionDownloadDelegateDidResumeAtOffset,
    NSURLSessionDownloadDelegateDidWriteData,
    NSURLSessionDownloadDelegateDidFinishDownloadingToURL
};

//
// NSURLSessionDataTask tests
//

@interface NSURLSessionDataTaskTestHelper : NSObject <NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate> {
    dispatch_queue_t _queue;
    NSOperationQueue* _delegateQueue;
}

@property NSCondition* condition;
@property NSMutableArray* delegateCallOrder;
@property (copy) NSURLRequest* redirectionRequest;
@property (copy) NSURLResponse* response;
@property (copy) NSData* data;
@property (copy) NSError* completedWithError;

- (instancetype)init;
- (NSURLSession*)createSession;
@end

@implementation NSURLSessionDataTaskTestHelper

- (instancetype)init {
    if (self = [super init]) {
        self->_condition = [[NSCondition alloc] init];
        _queue = dispatch_queue_create("NSURLSessionDataDelegateCallOrder", NULL);
        self->_delegateCallOrder = [NSMutableArray array];
    }
    return self;
}

- (NSURLSession*)createSession {
    _delegateQueue = [[NSOperationQueue alloc] init];
    [_delegateQueue setMaxConcurrentOperationCount:5];
    return [NSURLSession sessionWithConfiguration:nil delegate:self delegateQueue:_delegateQueue];
}

//
// NSURLSessionDelegate
//
- (void)URLSession:(NSURLSession*)session didBecomeInvalidWithError:(NSError*)error {
    // TODO::
    // todo-nithishm-03312016 - Have tests for these.
}

- (void)URLSession:(NSURLSession*)session
    didReceiveChallenge:(NSURLAuthenticationChallenge*)challenge
      completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential* credential))completionHandler {
    // TODO::
    // todo-nithishm-03312016 - Have tests for these.
}

- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession*)session {
}

//
// NSURLSessionTaskDelegate
//
- (void)URLSession:(NSURLSession*)session
                          task:(NSURLSessionTask*)task
    willPerformHTTPRedirection:(NSHTTPURLResponse*)response
                    newRequest:(NSURLRequest*)request
             completionHandler:(void (^)(NSURLRequest*))completionHandler {
    [self.condition lock];
    dispatch_sync(_queue, ^{
        [self.delegateCallOrder addObject:[NSNumber numberWithInteger:NSURLSessionDelegateWillPerformHTTPRedirection]];
    });
    self.redirectionRequest = request;
    completionHandler(request);
    [self.condition signal];
    [self.condition unlock];
}

- (void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task didCompleteWithError:(NSError*)error {
    [self.condition lock];
    dispatch_sync(_queue, ^{
        [self.delegateCallOrder addObject:[NSNumber numberWithInteger:NSURLSessionDelegateDidCompleteWithError]];
    });
    self.completedWithError = error;
    [self.condition signal];
    [self.condition unlock];
}

//
// NSURLSessionDataDelegate
//
- (void)URLSession:(NSURLSession*)session
              dataTask:(NSURLSessionDataTask*)task
    didReceiveResponse:(NSURLResponse*)response
     completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    [self.condition lock];
    dispatch_sync(_queue, ^{
        [self.delegateCallOrder addObject:[NSNumber numberWithInteger:NSURLSessionDataDelegateDidReceiveResponse]];
    });
    self.response = response;
    completionHandler(NSURLSessionResponseAllow);
    [self.condition signal];
    [self.condition unlock];
}

- (void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)task didReceiveData:(NSData*)data {
    [self.condition lock];
    dispatch_sync(_queue, ^{
        [self.delegateCallOrder addObject:[NSNumber numberWithInteger:NSURLSessionDataDelegateDidReceiveData]];
    });
    self.data = data;
    [self.condition signal];
    [self.condition unlock];
}

@end

@interface NSURLSessionDownloadTaskTestHelper : NSObject <NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDownloadDelegate> {
    dispatch_queue_t _queue;
    NSOperationQueue* _delegateQueue;
    bool _didWriteDatadelegateCalled;
}

@property NSCondition* condition;
@property NSMutableArray* delegateCallOrder;
@property (copy) NSURLRequest* redirectionRequest;
@property int64_t totalBytesExpectedToWrite;
@property int64_t totalBytesWritten;
@property (copy) NSURL* downloadedLocation;
@property (copy) NSError* completedWithError;

- (instancetype)init;
- (NSURLSession*)createSession;
@end

@implementation NSURLSessionDownloadTaskTestHelper

- (instancetype)init {
    if (self = [super init]) {
        self->_condition = [[NSCondition alloc] init];
        _queue = dispatch_queue_create("NSURLSessionDataDelegateCallOrder", NULL);
        self->_delegateCallOrder = [NSMutableArray array];
    }
    return self;
}

- (NSURLSession*)createSession {
    _delegateQueue = [[NSOperationQueue alloc] init];
    [_delegateQueue setMaxConcurrentOperationCount:5];
    return [NSURLSession sessionWithConfiguration:nil delegate:self delegateQueue:_delegateQueue];
}

//
// NSURLSessionDelegate
//
- (void)URLSession:(NSURLSession*)session
                           didBecomeInvalidWithError:(NSError*)error{
                               // TODO::
                               // todo-nithishm-03312016 - Have tests for these.
                           }

                                                     - (void)
                                          URLSession:(NSURLSession*)session
                                 didReceiveChallenge:(NSURLAuthenticationChallenge*)challenge
                                   completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition,
                                                               NSURLCredential* credential))completionHandler{
                                       // TODO::
                                       // todo-nithishm-03312016 - Have tests for these.
                                   }

                                                     - (void)
    URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession*)session{}

                                                     //
                                                     // NSURLSessionTaskDelegate
                                                     //
                                                     - (void)
                                          URLSession:(NSURLSession*)session
                                                task:(NSURLSessionTask*)task
                          willPerformHTTPRedirection:(NSHTTPURLResponse*)response
                                          newRequest:(NSURLRequest*)request
                                   completionHandler:(void (^)(NSURLRequest*))completionHandler {
    [self.condition lock];
    dispatch_sync(_queue, ^{
        [self.delegateCallOrder addObject:[NSNumber numberWithInteger:NSURLSessionDelegateWillPerformHTTPRedirection]];
    });
    self.redirectionRequest = request;
    completionHandler(request);

    [self.condition signal];
    [self.condition unlock];
}

- (void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task didCompleteWithError:(NSError*)error {
    [self.condition lock];
    dispatch_sync(_queue, ^{
        [self.delegateCallOrder addObject:[NSNumber numberWithInteger:NSURLSessionDelegateDidCompleteWithError]];
    });
    self.completedWithError = error;

    [self.condition signal];
    [self.condition unlock];
}

//
// NSURLSessionDownloadDelegate
//

- (void)URLSession:(NSURLSession*)session
          downloadTask:(NSURLSessionDownloadTask*)downloadTask
     didResumeAtOffset:(int64_t)fileOffset
    expectedTotalBytes:(int64_t)expectedTotalBytes {
    [self.condition lock];
    dispatch_sync(_queue, ^{
        [self.delegateCallOrder addObject:[NSNumber numberWithInteger:NSURLSessionDownloadDelegateDidResumeAtOffset]];
    });
    [self.condition signal];
    [self.condition unlock];
}

- (void)URLSession:(NSURLSession*)session
                 downloadTask:(NSURLSessionDownloadTask*)downloadTask
                 didWriteData:(int64_t)bytesWritten
            totalBytesWritten:(int64_t)totalBytesWritten
    totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    [self.condition lock];

    // This delegate will be called periodically.
    if (!_didWriteDatadelegateCalled) {
        dispatch_sync(_queue, ^{
            [self.delegateCallOrder addObject:[NSNumber numberWithInteger:NSURLSessionDownloadDelegateDidWriteData]];
        });
        _didWriteDatadelegateCalled = true;
        [self.condition signal];
    }
    self.totalBytesExpectedToWrite = totalBytesExpectedToWrite;
    self.totalBytesWritten = totalBytesWritten;
    [self.condition unlock];
}

- (void)URLSession:(NSURLSession*)session downloadTask:(NSURLSessionDownloadTask*)downloadTask didFinishDownloadingToURL:(NSURL*)location {
    [self.condition lock];
    dispatch_sync(_queue, ^{
        [self.delegateCallOrder addObject:[NSNumber numberWithInteger:NSURLSessionDownloadDelegateDidFinishDownloadingToURL]];
    });
    self.downloadedLocation = location;
    [self.condition signal];
    [self.condition unlock];
}

@end

class NSURLSessionTests {
public:
    BEGIN_TEST_CLASS(NSURLSessionTests)
    TEST_CLASS_PROPERTY(L"UAP:AppXManifest", L"NSURL.AppxManifest.xml")
    END_TEST_CLASS()

    TEST_CLASS_SETUP(NSURLClassSetup) {
        return FunctionalTestSetupUIApplication();
    }

    TEST_CLASS_CLEANUP(NSURLCleanup) {
        return FunctionalTestCleanupUIApplication();
    }

    /**
     * Test to verify a that two tasks do not have the same identifier.
     */
    TEST_METHOD(TaskIdentifiers) {
        NSURLSessionDataTaskTestHelper* dataTaskTestHelper = [[NSURLSessionDataTaskTestHelper alloc] init];
        NSURLSession* session = [dataTaskTestHelper createSession];
        NSURL* url = [NSURL URLWithString:@"https://httpbin.org/cookies/set?Hello=World"];

        NSURLSessionTask* dataTask = [session dataTaskWithURL:url];
        NSURLSessionTask* downloadTask = [session downloadTaskWithURL:url];

        ASSERT_NE(dataTask.taskIdentifier, downloadTask.taskIdentifier);
    }

    /**
     * Test to verify a data task call can be successfully made and a valid data is received without a completion handler
     */
    TEST_METHOD(DataTaskWithURL) {
        NSURLSessionDataTaskTestHelper* dataTaskTestHelper = [[NSURLSessionDataTaskTestHelper alloc] init];
        NSURLSession* session = [dataTaskTestHelper createSession];
        NSURL* url = [NSURL URLWithString:@"https://httpbin.org/cookies/set?Hello=World"];
        LOG_INFO("Establishing data task with url %@", url);
        NSURLSessionDataTask* dataTask = [session dataTaskWithURL:url];
        [dataTask resume];

        // Wait for data.
        [dataTaskTestHelper.condition lock];
        for (int i = 0; (i < 5) && ([dataTaskTestHelper.delegateCallOrder count] != 4); i++) {
            [dataTaskTestHelper.condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:c_testTimeoutInSec]];
        }
        [dataTaskTestHelper.condition unlock];
        ASSERT_EQ_MSG(4, [dataTaskTestHelper.delegateCallOrder count], "FAILED: We should have received all four delegates call by now!");

        // Make sure willPerformHTTPRedirection delegate was first called.
        ASSERT_EQ_MSG(NSURLSessionDelegateWillPerformHTTPRedirection,
                      [(NSNumber*)[dataTaskTestHelper.delegateCallOrder objectAtIndex:0] integerValue],
                      "FAILED: willPerformHTTPRedirection should be the first delegate to be called!");

        // Make sure we received a response.
        ASSERT_EQ_MSG(NSURLSessionDataDelegateDidReceiveResponse,
                      [(NSNumber*)[dataTaskTestHelper.delegateCallOrder objectAtIndex:1] integerValue],
                      "FAILED: didReceiveResponse should be the second delegate to be called!");
        ASSERT_TRUE_MSG((dataTaskTestHelper.response != nil), "FAILED: Response cannot be empty!");
        NSURLResponse* response = dataTaskTestHelper.response;
        if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
            ASSERT_FALSE_MSG(true, "FAILED: Response should be of kind NSHTTPURLResponse class!");
        }
        NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
        LOG_INFO("Received HTTP response status: %ld", [httpResponse statusCode]);
        ASSERT_EQ_MSG(200, [httpResponse statusCode], "FAILED: HTTP status 200 expected!");
        LOG_INFO("Received HTTP response headers: %d", [httpResponse allHeaderFields]);

        // Make sure we received data.
        ASSERT_EQ_MSG(NSURLSessionDataDelegateDidReceiveData,
                      [(NSNumber*)[dataTaskTestHelper.delegateCallOrder objectAtIndex:2] integerValue],
                      "FAILED: didReceiveData should be the third delegate to be called!");
        ASSERT_TRUE_MSG((dataTaskTestHelper.data != nil), "FAILED: We should have received some data!");
        LOG_INFO("Received data: %@", [[NSString alloc] initWithData:dataTaskTestHelper.data encoding:NSUTF8StringEncoding]);

        // Make sure didCompleteWithError delegate was called last.
        ASSERT_EQ_MSG(NSURLSessionDelegateDidCompleteWithError,
                      [(NSNumber*)[dataTaskTestHelper.delegateCallOrder objectAtIndex:3] integerValue],
                      "FAILED: willPerformHTTPRedirection should be the last delegate to be called!");
        // Make sure there was no error.
        ASSERT_TRUE_MSG((dataTaskTestHelper.completedWithError == nil),
                        "FAILED: Data task returned error %@!",
                        dataTaskTestHelper.completedWithError);
    }

    /**
     * Test to verify a data task call can be successfully made without a completion handler but no data was received but a valid response
     * error code was received.
     */
    TEST_METHOD(DataTaskWithURL_Failure) {
        NSURLSessionDataTaskTestHelper* dataTaskTestHelper = [[NSURLSessionDataTaskTestHelper alloc] init];
        NSURLSession* session = [dataTaskTestHelper createSession];
        NSURL* url = [NSURL URLWithString:@"https://httpbin.org/status/500"];
        LOG_INFO("Establishing data task with url %@", url);
        NSURLSessionDataTask* dataTask = [session dataTaskWithURL:url];
        [dataTask resume];

        // Wait for data.
        [dataTaskTestHelper.condition lock];
        for (int i = 0; (i < 5) && ([dataTaskTestHelper.delegateCallOrder count] != 2); i++) {
            [dataTaskTestHelper.condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:c_testTimeoutInSec]];
        }
        [dataTaskTestHelper.condition unlock];

        ASSERT_EQ_MSG(2, [dataTaskTestHelper.delegateCallOrder count], "FAILED: We should have received all two delegates call by now!");

        // Make sure we received a response.
        ASSERT_EQ_MSG(NSURLSessionDataDelegateDidReceiveResponse,
                      [(NSNumber*)[dataTaskTestHelper.delegateCallOrder objectAtIndex:0] integerValue],
                      "FAILED: didReceiveResponse should be the second delegate to be called!");
        ASSERT_TRUE_MSG((dataTaskTestHelper.response != nil), "FAILED: Response cannot be empty!");
        NSURLResponse* response = dataTaskTestHelper.response;
        if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
            ASSERT_FALSE_MSG(true, "FAILED: Response should be of kind NSHTTPURLResponse class!");
        }
        NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
        LOG_INFO("Received HTTP response status: %ld", [httpResponse statusCode]);
        ASSERT_EQ_MSG(500, [httpResponse statusCode], "FAILED: HTTP status 500 expected!");

        // Make sure we did not receive any data.
        ASSERT_TRUE_MSG((dataTaskTestHelper.data == nil), "FAILED: We should have not received any data!");

        // Make sure didCompleteWithError delegate was called last.
        ASSERT_EQ_MSG(NSURLSessionDelegateDidCompleteWithError,
                      [(NSNumber*)[dataTaskTestHelper.delegateCallOrder objectAtIndex:1] integerValue],
                      "FAILED: willPerformHTTPRedirection should be the last delegate to be called!");
        // Make sure there was no error.
        ASSERT_TRUE_MSG((dataTaskTestHelper.completedWithError == nil),
                        "FAILED: Data task returned error %@!",
                        dataTaskTestHelper.completedWithError);
    }

    /**
     * Test to verify a data task call can be successfully made and a valid data is received with a completion handler
     */
    TEST_METHOD(DataTaskWithURL_WithCompletionHandler) {
        __block NSCondition* condition = [[NSCondition alloc] init];
        __block NSURLResponse* taskResponse;
        __block NSData* taskData;
        __block NSError* taskError;

        NSURLSessionDataTaskTestHelper* dataTaskTestHelper = [[NSURLSessionDataTaskTestHelper alloc] init];
        NSURLSession* session = [dataTaskTestHelper createSession];
        NSURL* url = [NSURL URLWithString:@"https://httpbin.org/cookies/set?You=There"];
        LOG_INFO("Establishing data task with url %@", url);
        NSURLSessionDataTask* dataTask = [session dataTaskWithURL:url
                                                completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
                                                    [condition lock];
                                                    taskResponse = response;
                                                    taskData = data;
                                                    taskError = error;
                                                    [condition signal];
                                                    [condition unlock];
                                                }];
        [dataTask resume];

        // Wait for data.
        [condition lock];
        ASSERT_TRUE_MSG((taskResponse || taskData || taskError) ||
                            [condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:c_testTimeoutInSec]],
                        "FAILED: Waiting for connection timed out!");
        [condition unlock];

        // Make sure we received a response.
        ASSERT_TRUE_MSG((taskResponse != nil), "FAILED: Response cannot be empty!");
        if (![taskResponse isKindOfClass:[NSHTTPURLResponse class]]) {
            ASSERT_FALSE_MSG(true, "FAILED: Response should be of kind NSHTTPURLResponse class!");
        }
        NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)taskResponse;
        LOG_INFO("Received HTTP response status: %ld", [httpResponse statusCode]);
        ASSERT_EQ_MSG(200, [httpResponse statusCode], "FAILED: HTTP status 200 expected!");
        LOG_INFO("Received HTTP response headers: %d", [httpResponse allHeaderFields]);

        // Make sure we received data.
        ASSERT_TRUE_MSG((taskData != nil), "FAILED: We should have received some data!");
        LOG_INFO("Received data: %@", [[NSString alloc] initWithData:taskData encoding:NSUTF8StringEncoding]);

        // Make sure there was no error.
        ASSERT_EQ_MSG(nil, taskError, "FAILED: Task returned error!");
    }

    /**
     * Test to verify a data task call can be successfully made with a completion handler but no data was received but a valid response
     * error code was received.
     */
    TEST_METHOD(DataTaskWithURL_WithCompletionHandler_Failure) {
        __block NSCondition* condition = [[NSCondition alloc] init];
        __block NSURLResponse* taskResponse;
        __block NSData* taskData;
        __block NSError* taskError;

        NSURLSessionDataTaskTestHelper* dataTaskTestHelper = [[NSURLSessionDataTaskTestHelper alloc] init];
        NSURLSession* session = [dataTaskTestHelper createSession];
        NSURL* url = [NSURL URLWithString:@"https://httpbin.org/status/403"];
        LOG_INFO("Establishing data task with url %@", url);
        NSURLSessionDataTask* dataTask = [session dataTaskWithURL:url
                                                completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
                                                    [condition lock];
                                                    taskResponse = response;
                                                    taskData = data;
                                                    taskError = error;
                                                    [condition signal];
                                                    [condition unlock];
                                                }];
        [dataTask resume];

        // Wait for data.
        [condition lock];
        ASSERT_TRUE_MSG((taskResponse || taskData || taskError) ||
                            [condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:c_testTimeoutInSec]],
                        "FAILED: Waiting for connection timed out!");
        [condition unlock];

        // Make sure we received a response.
        ASSERT_TRUE_MSG((taskResponse != nil), "FAILED: Response cannot be empty!");
        if (![taskResponse isKindOfClass:[NSHTTPURLResponse class]]) {
            ASSERT_FALSE_MSG(true, "FAILED: Response should be of kind NSHTTPURLResponse class!");
        }
        NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)taskResponse;
        LOG_INFO("Received HTTP response status: %ld", [httpResponse statusCode]);
        ASSERT_EQ_MSG(403, [httpResponse statusCode], "FAILED: HTTP status 403 expected!");

        // Make sure we did not receive any data.
        ASSERT_TRUE_MSG((taskData == nil), "FAILED: We should not have received any data!");

        // Make sure there was no error.
        ASSERT_EQ_MSG(nil, taskError, "FAILED: Connection returned error!");
    }

    //
    // NSURLSessionDownloadTask tests
    //

    /**
     * Test to verify a download task call can be successfully made without a completion handler
     */
    TEST_METHOD(DownloadTaskWithURL) {
// Disable Test on ARM as it tries to hit a real endpoint and download significant data
// and arm machines may not have a stable ethernet connection like a build server does.
#ifdef _M_ARM
        BEGIN_TEST_METHOD_PROPERTIES()
        TEST_METHOD_PROPERTY(L"ignore", L"true")
        END_TEST_METHOD_PROPERTIES()
#endif

        NSURLSessionDownloadTaskTestHelper* downloadTaskTestHelper = [[NSURLSessionDownloadTaskTestHelper alloc] init];
        NSURLSession* session = [downloadTaskTestHelper createSession];
        NSURL* url = [NSURL URLWithString:@"http://speedtest.sea01.softlayer.com/downloads/test10.zip"];
        LOG_INFO("Establishing download task with url %@", url);
        NSURLSessionDownloadTask* downloadTask = [session downloadTaskWithURL:url];
        [downloadTask resume];

        // Wait for download to complete.
        [downloadTaskTestHelper.condition lock];
        for (int i = 0; (i < 5) && ([downloadTaskTestHelper.delegateCallOrder count] != 3); i++) {
            [downloadTaskTestHelper.condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:c_testTimeoutInSec]];
        }
        [downloadTaskTestHelper.condition unlock];
        ASSERT_EQ_MSG(3,
                      [downloadTaskTestHelper.delegateCallOrder count],
                      "FAILED: We should have received all three delegates call by now!");

        // Make sure the download started.
        ASSERT_EQ_MSG(NSURLSessionDownloadDelegateDidWriteData,
                      [(NSNumber*)[downloadTaskTestHelper.delegateCallOrder objectAtIndex:0] integerValue],
                      "FAILED: didWriteData should be the first delegate to be called!");
        double fileSizeInMB = (double)downloadTaskTestHelper.totalBytesExpectedToWrite / 1024 / 1024;
        LOG_INFO("Downloaded file size is %fMB", fileSizeInMB);
        ASSERT_EQ_MSG(11, std::lround(fileSizeInMB), "FAILED: Expected download file size does not match!");

        // Make sure the didFinishDownloadingToURL got called.
        ASSERT_EQ_MSG(NSURLSessionDownloadDelegateDidFinishDownloadingToURL,
                      [(NSNumber*)[downloadTaskTestHelper.delegateCallOrder objectAtIndex:1] integerValue],
                      "FAILED: didFinishDownloadingToURL should be the second delegate to be called!");

        // Make sure didCompleteWithError delegate was called last.
        ASSERT_EQ_MSG(NSURLSessionDelegateDidCompleteWithError,
                      [(NSNumber*)[downloadTaskTestHelper.delegateCallOrder objectAtIndex:2] integerValue],
                      "FAILED: willPerformHTTPRedirection should be the last delegate to be called!");
        // Make sure there was no error.
        ASSERT_TRUE_MSG((downloadTaskTestHelper.completedWithError == nil),
                        "FAILED: Data task returned error %@!",
                        downloadTaskTestHelper.completedWithError);
    }

    /**
     * Test to verify a download task call can be made without a completion handler
     */
    TEST_METHOD(DownloadTaskWithURL_Failure) {
        NSURLSessionDownloadTaskTestHelper* downloadTaskTestHelper = [[NSURLSessionDownloadTaskTestHelper alloc] init];
        NSURLSession* session = [downloadTaskTestHelper createSession];
        NSURL* url = [NSURL URLWithString:@"https://httpbin.org/status/401"];
        LOG_INFO("Establishing download task with url %@", url);
        NSURLSessionDownloadTask* downloadTask = [session downloadTaskWithURL:url];
        [downloadTask resume];

        // Wait for download to complete.
        [downloadTaskTestHelper.condition lock];
        for (int i = 0; (i < 5) && ([downloadTaskTestHelper.delegateCallOrder count] != 2); i++) {
            [downloadTaskTestHelper.condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:c_testTimeoutInSec]];
        }
        [downloadTaskTestHelper.condition unlock];
        ASSERT_EQ_MSG(2,
                      [downloadTaskTestHelper.delegateCallOrder count],
                      "FAILED: We should have received all two delegates call by now!");

        ASSERT_EQ_MSG(0, downloadTaskTestHelper.totalBytesExpectedToWrite, "FAILED: Expected download file size to be ZERO!");

        // Make sure the didFinishDownloadingToURL got called first. We would never get didWriteData delegate called as the download URL we
        // have passed in invalid.
        ASSERT_EQ_MSG(NSURLSessionDownloadDelegateDidFinishDownloadingToURL,
                      [(NSNumber*)[downloadTaskTestHelper.delegateCallOrder objectAtIndex:0] integerValue],
                      "FAILED: didFinishDownloadingToURL should be the second delegate to be called!");

        // Make sure didCompleteWithError delegate was called last.
        ASSERT_EQ_MSG(NSURLSessionDelegateDidCompleteWithError,
                      [(NSNumber*)[downloadTaskTestHelper.delegateCallOrder objectAtIndex:1] integerValue],
                      "FAILED: willPerformHTTPRedirection should be the last delegate to be called!");
        // Make sure there was no error.
        ASSERT_TRUE_MSG((downloadTaskTestHelper.completedWithError == nil),
                        "FAILED: Download task returned error %@!",
                        downloadTaskTestHelper.completedWithError);
    }

    /**
     * Test to verify a download task call can be successfully made with a completion handler
     */
    TEST_METHOD(DownloadTaskWithURL_WithCompletionHandler) {
// Disable Test on ARM as it tries to hit a real endpoint and download significant data
// and arm machines may not have a stable ethernet connection like a build server does.
#ifdef _M_ARM
        BEGIN_TEST_METHOD_PROPERTIES()
        TEST_METHOD_PROPERTY(L"ignore", L"true")
        END_TEST_METHOD_PROPERTIES()
#endif
        __block NSCondition* condition = [[NSCondition alloc] init];
        __block NSURLResponse* downloadResponse;
        __block NSURL* downloadLocation;
        __block NSError* downloadError;

        NSURLSessionDownloadTaskTestHelper* downloadTaskTestHelper = [[NSURLSessionDownloadTaskTestHelper alloc] init];
        NSURLSession* session = [downloadTaskTestHelper createSession];
        NSURL* url = [NSURL URLWithString:@"http://speedtest.sea01.softlayer.com/downloads/test10.zip"];
        LOG_INFO("Establishing download task with url %@", url);
        NSURLSessionDownloadTask* downloadTask = [session downloadTaskWithURL:url
                                                            completionHandler:^(NSURL* location, NSURLResponse* response, NSError* error) {
                                                                [condition lock];
                                                                downloadLocation = location;
                                                                downloadResponse = response;
                                                                downloadError = error;
                                                                [condition signal];
                                                                [condition unlock];
                                                            }];
        [downloadTask resume];

        // Wait for download to complete.
        [condition lock];
        ASSERT_TRUE_MSG((downloadLocation || downloadResponse || downloadError) ||
                            [condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:c_testDownloadTimeoutInSec]],
                        "FAILED: Waiting for download timed out!");
        [condition unlock];

        // Make sure we get a download location.
        ASSERT_TRUE_MSG((downloadLocation != nil), "FAILED: Downloaded location cannot be empty!");
        LOG_INFO("File downloaded at location %@", downloadLocation);

        // Make sure there was no error.
        ASSERT_EQ_MSG(nil, downloadError, "FAILED: Download task returned error!");
    }

    inline int _GetLastDelegateCall(NSURLSessionDownloadTaskTestHelper* downloadTaskTestHelper) {
        return [(NSNumber*)[downloadTaskTestHelper.delegateCallOrder objectAtIndex:([downloadTaskTestHelper.delegateCallOrder count] - 1)]
            integerValue];
    }

    /**
     * Test to verify a download task call can be successfully made and can be cancelled/resumed at runtime.
     */
    TEST_METHOD(DownloadTaskWithURL_WithCancelResume) {
        NSURLSessionDownloadTaskTestHelper* downloadTaskTestHelper = [[NSURLSessionDownloadTaskTestHelper alloc] init];
        NSURLSession* session = [downloadTaskTestHelper createSession];
        NSURL* url = [NSURL URLWithString:@"http://speedtest.ams01.softlayer.com/downloads/test500.zip"];
        LOG_INFO("Establishing download task with url %@", url);
        NSURLSessionDownloadTask* downloadTask = [session downloadTaskWithURL:url];
        [downloadTask resume];

        // Wait for first delegate to be arrive.
        [downloadTaskTestHelper.condition lock];
        for (int i = 0; (i < 5) && ([downloadTaskTestHelper.delegateCallOrder count] != 1); i++) {
            [downloadTaskTestHelper.condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:c_testTimeoutInSec]];
        }
        [downloadTaskTestHelper.condition unlock];
        ASSERT_EQ_MSG(1, [downloadTaskTestHelper.delegateCallOrder count], "FAILED: We should have received a delegate call by now!");

        // Make sure the download started.
        ASSERT_EQ_MSG(NSURLSessionDownloadDelegateDidWriteData,
                      [(NSNumber*)[downloadTaskTestHelper.delegateCallOrder objectAtIndex:0] integerValue],
                      "FAILED: didWriteData should be the first delegate to be called!");
        double fileSizeInMB = (double)downloadTaskTestHelper.totalBytesExpectedToWrite / 1024 / 1024;
        LOG_INFO("Downloaded file size is %fMB", fileSizeInMB);
        ASSERT_EQ_MSG(500, std::lround(fileSizeInMB), "FAILED: Expected download file size does not match!");

        // Make sure download is in progress.
        ASSERT_EQ(NSURLSessionTaskStateRunning, downloadTask.state);

        // Now cancel the download
        __block NSCondition* conditionCancelled = [[NSCondition alloc] init];
        __block NSData* downloadResumeData = nil;
        LOG_INFO("Cancelling download...");
        [downloadTask cancelByProducingResumeData:^(NSData* resumeData) {
            [conditionCancelled lock];
            downloadResumeData = resumeData;
            [conditionCancelled signal];
            [conditionCancelled unlock];
            LOG_INFO("Download cancelled");
        }];

        // Wait for the task to be cancelled.
        [conditionCancelled lock];
        ASSERT_TRUE_MSG(downloadResumeData || [conditionCancelled waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:c_testTimeoutInSec]],
                        "FAILED: Waiting for download timed out!");
        [conditionCancelled unlock];

        // Make sure download has stopped.
        ASSERT_EQ(NSURLSessionTaskStateCanceling, downloadTask.state);

        // Now resume the download
        LOG_INFO("Resuming download...");
        downloadTask = [session downloadTaskWithResumeData:downloadResumeData];
        [downloadTask resume];

        // Wait for resume delegate.
        [downloadTaskTestHelper.condition lock];
        int i = 0;
        for (i = 0; (i < 5) && (NSURLSessionDownloadDelegateDidResumeAtOffset != _GetLastDelegateCall(downloadTaskTestHelper)); i++) {
            [downloadTaskTestHelper.condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:c_testTimeoutInSec]];
        }
        ASSERT_NE(i, 5);
        [downloadTaskTestHelper.condition unlock];

        LOG_INFO("Download resumed");

        // Make sure download is in progress again.
        ASSERT_EQ(NSURLSessionTaskStateRunning, downloadTask.state);
    }
};
