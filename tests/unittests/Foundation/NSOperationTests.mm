//******************************************************************************
//
// Copyright (c) Microsoft. All rights reserved.
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

#import <TestFramework.h>
#import <Foundation/Foundation.h>

#import <thread>
#import <mutex>
#import <condition_variable>
#import <chrono>

static void (^_completionBlockPopulatingConditionAndFlag(void (^completionBlock)(), NSCondition** condition, BOOL* flag))() {
    NSCondition* cond = [[NSCondition new] autorelease];
    *condition = cond;
    return Block_copy(^{
        if (completionBlock) {
            completionBlock();
        }
        [cond lock];
        *flag = YES;
        [cond broadcast];
        [cond unlock];
    });
}

// Convenience class that wraps an NSCondition and an associated boolean, and implements the NSCondition usage pattern documented in:
// https://developer.apple.com/reference/foundation/nscondition?language=objc
// This can be replaced/re-implemented based on NSConditionLock once that has a stable implementation
@interface _NSBooleanCondition : NSObject
- (BOOL)waitUntilDate:(NSDate*)limit;
- (void)broadcast;
@property (readonly) NSCondition* condition;
@property (readonly) bool isOpen;
@end

@implementation _NSBooleanCondition
- (instancetype)init {
    if (self = [super init]) {
        _condition = [[NSCondition new] autorelease];
        _isOpen = false;
    }
    return self;
}

- (BOOL)waitUntilDate:(NSDate*)limit {
    BOOL ret = YES;
    [_condition lock];
    while (!_isOpen) {
        ret = [_condition waitUntilDate:limit];
    }
    [_condition unlock];
    return ret;
}

- (void)broadcast {
    [_condition lock];
    _isOpen = YES;
    [_condition broadcast];
    [_condition unlock];
}

@end

TEST(NSOperation, NSOperationDealloc) {
    NSOperationQueue* queue = [[NSOperationQueue alloc] init];
    ASSERT_NO_THROW([queue release]);

    NSOperation* operation = [[NSOperation alloc] init];
    ASSERT_NO_THROW([operation release]);
}

TEST(NSOperation, NSOperation) {
    NSOperationQueue* queue = [[NSOperationQueue new] autorelease];

    NSOperation* operation = [[NSOperation new] autorelease];

    NSCondition* completionCondition = nil;
    BOOL completionBlockCalled = NO;
    [operation setCompletionBlock:_completionBlockPopulatingConditionAndFlag(
                                      ^{
                                          [operation waitUntilFinished]; // Should not deadlock, but we cannot test this
                                          ASSERT_TRUE([operation isFinished]);
                                      },
                                      &completionCondition,
                                      &completionBlockCalled)];

    [completionCondition lock];

    [queue addOperation:operation];

    [operation waitUntilFinished];

    [completionCondition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]];
    [completionCondition unlock];

    ASSERT_TRUE(completionBlockCalled);
    ASSERT_TRUE([operation isFinished]);
    ASSERT_FALSE([operation isExecuting]);
}

TEST(NSOperation, CancelOutOfQueue) {
    NSOperation* operation = [[NSOperation new] autorelease];
    [operation cancel];
    EXPECT_TRUE([operation isCancelled]);
    EXPECT_FALSE([operation isExecuting]);
    EXPECT_FALSE([operation isFinished]);
}

TEST(NSOperation, NSOperationCancellation) {
    NSOperationQueue* queue = [[NSOperationQueue new] autorelease];

    NSOperation* cancelledOperation = [[NSOperation new] autorelease];

    NSCondition* completionCondition = nil;
    BOOL completionBlockCalled = NO;
    [cancelledOperation setCompletionBlock:_completionBlockPopulatingConditionAndFlag(
                                               ^{
                                                   [cancelledOperation waitUntilFinished]; // Should not deadlock, but we cannot test this
                                                   ASSERT_TRUE([cancelledOperation isFinished]);
                                               },
                                               &completionCondition,
                                               &completionBlockCalled)];

    [completionCondition lock];

    [cancelledOperation cancel];

    [queue addOperation:cancelledOperation];

    [cancelledOperation waitUntilFinished];

    [completionCondition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]];
    [completionCondition unlock];

    ASSERT_TRUE(completionBlockCalled);
    ASSERT_FALSE([cancelledOperation isExecuting]);
    ASSERT_TRUE([cancelledOperation isCancelled]);
}

TEST(NSOperation, NSOperationSuspend) {
    NSOperationQueue* queue = [[NSOperationQueue alloc] init];

    NSOperation* suspendOperation = [[NSOperation alloc] init];

    __block NSCondition* suspendCondition = [NSCondition new];
    __block bool shouldBeTrue = false;

    [suspendOperation setCompletionBlock:^{
        [suspendOperation waitUntilFinished]; // Should not deadlock, but we cannot test this
        ASSERT_TRUE([suspendOperation isFinished]);

        [suspendCondition lock];
        ASSERT_TRUE(shouldBeTrue);
        [suspendCondition unlock];
    }];

    [queue setSuspended:YES];
    [queue addOperation:suspendOperation];

    std::this_thread::sleep_for(std::chrono::milliseconds(300));
    [suspendCondition lock];
    shouldBeTrue = true;
    [suspendCondition broadcast];
    [suspendCondition unlock];

    ASSERT_TRUE([queue isSuspended]);
    ASSERT_FALSE([suspendOperation isExecuting]);

    [queue setSuspended:NO];
    ASSERT_FALSE([queue isSuspended]);

    [suspendOperation waitUntilFinished];
}

@interface TestObserver : NSObject
@property BOOL didObserveCompletionBlock;
@property BOOL didObserveDependencies;
@property BOOL didObserveReady;
@property BOOL didObserveCancelled;
@property BOOL didObserveExecuting;
@property BOOL didObserveFinished;
@end

@implementation TestObserver
- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context {
    if ([keyPath isEqualToString:@"completionBlock"]) {
        _didObserveCompletionBlock = YES;
    } else if ([keyPath isEqualToString:@"dependencies"]) {
        _didObserveDependencies = YES;
    } else if ([keyPath isEqualToString:@"isReady"]) {
        _didObserveReady = YES;
    } else if ([keyPath isEqualToString:@"isCancelled"]) {
        _didObserveCancelled = YES;
    } else if ([keyPath isEqualToString:@"isExecuting"]) {
        _didObserveExecuting = YES;
    } else if ([keyPath isEqualToString:@"isFinished"]) {
        _didObserveFinished = YES;
    }
}

@end

// On the reference platform, we cannot observe isFinished immediately.
// There appears to be a marked laziness in signalling the finished status.
// waitUntilFinished triggers before didChangeValueForKey:@"isFinished" --
// sometimes long before it -- and we can jump the gun on the observation.
// WinObjC updates these flags immediately and only releases a waitUntilFinished when
// didChangeValueForKey: has already triggered.
OSX_DISABLED_TEST(NSOperation, NSOperationKVO) {
    NSOperationQueue* queue = [[NSOperationQueue new] autorelease];
    NSOperation* operation = [[NSOperation new] autorelease];
    TestObserver* observer = [[TestObserver new] autorelease];

    [operation addObserver:observer forKeyPath:@"completionBlock" options:0 context:NULL];
    [operation addObserver:observer forKeyPath:@"isCancelled" options:0 context:NULL];
    [operation addObserver:observer forKeyPath:@"isExecuting" options:0 context:NULL];
    [operation addObserver:observer forKeyPath:@"isFinished" options:0 context:NULL];

    [operation setCompletionBlock:^{
        // nothing to do here.
    }];

    ASSERT_TRUE([observer didObserveCompletionBlock]);
    [observer setDidObserveCompletionBlock:NO];

    ASSERT_FALSE([observer didObserveCompletionBlock]);
    ASSERT_FALSE([observer didObserveCancelled]);
    ASSERT_FALSE([observer didObserveExecuting]);
    ASSERT_FALSE([observer didObserveFinished]);

    [queue addOperation:operation];
    [operation waitUntilFinished];

    ASSERT_FALSE([observer didObserveCompletionBlock]);
    ASSERT_FALSE([observer didObserveCancelled]);
    ASSERT_TRUE([observer didObserveExecuting]);
    ASSERT_TRUE([observer didObserveFinished]);

    [operation removeObserver:observer forKeyPath:@"completionBlock" context:NULL];
    [operation removeObserver:observer forKeyPath:@"isCancelled" context:NULL];
    [operation removeObserver:observer forKeyPath:@"isExecuting" context:NULL];
    [operation removeObserver:observer forKeyPath:@"isFinished" context:NULL];
}

// Test asynchronous subclass for NSOperation
@interface MyConcurrentOperation : NSOperation
@property (assign, getter=isExecuting) BOOL executing;
@property (assign, getter=isFinished, readonly) BOOL finished;
@end

@implementation MyConcurrentOperation

@synthesize executing = _executing;
@synthesize finished = _finished;

- (void)setExecuting:(BOOL)executing {
    [self willChangeValueForKey:@"isExecuting"];
    [self willChangeValueForKey:@"isFinished"];

    _executing = executing;
    _finished = !executing;

    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
}

- (BOOL)isExecuting {
    return _executing;
}

- (BOOL)isFinished {
    return _finished;
}

- (void)start {
    if (self.isCancelled) {
        return;
    }

    self.executing = YES;
    [self doSomething];
}

- (void)doSomething {
    // Do some async task.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{

        // Do another async task
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            // Do some async task.
            self.executing = NO;
        });
    });
}

@end

TEST(NSOperation, NSOperationConcurrentSubclass) {
    NSOperationQueue* queue = [[NSOperationQueue new] autorelease];

    NSOperation* operation = [MyConcurrentOperation new];

    NSCondition* completionCondition = nil;
    BOOL completionBlockCalled = NO;
    [operation setCompletionBlock:_completionBlockPopulatingConditionAndFlag(
                                      ^{
                                          [operation waitUntilFinished]; // Should not deadlock, but we cannot test this
                                          ASSERT_TRUE([operation isFinished]);
                                      },
                                      &completionCondition,
                                      &completionBlockCalled)];

    [completionCondition lock];

    [queue addOperation:operation];

    [operation waitUntilFinished];

    [completionCondition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]];
    [completionCondition unlock];

    ASSERT_TRUE(completionBlockCalled);
    ASSERT_TRUE([operation isFinished]);
    ASSERT_FALSE([operation isExecuting]);
    ASSERT_NO_THROW([operation release]);
}

// Test synchronous subclass for NSOperation
@interface MyNonconcurrentOperation : NSOperation
@property BOOL didWork;
@end

@implementation MyNonconcurrentOperation

- (void)main {
    if (self.isCancelled) {
        return;
    }

    _didWork = YES;
}

@end

TEST(NSOperation, NSOperationNonconcurrentSubclass) {
    NSOperationQueue* queue = [[NSOperationQueue new] autorelease];

    MyNonconcurrentOperation* operation = [MyNonconcurrentOperation new];

    NSCondition* completionCondition = nil;
    BOOL completionBlockCalled = NO;
    [operation setCompletionBlock:_completionBlockPopulatingConditionAndFlag(
                                      ^{
                                          [operation waitUntilFinished]; // Should not deadlock, but we cannot test this
                                          ASSERT_TRUE([operation isFinished]);
                                      },
                                      &completionCondition,
                                      &completionBlockCalled)];

    [completionCondition lock];

    [queue addOperation:operation];
    [operation waitUntilFinished];

    [completionCondition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]];
    [completionCondition unlock];

    ASSERT_TRUE(completionBlockCalled);
    ASSERT_TRUE([operation isFinished]);
    ASSERT_FALSE([operation isExecuting]);
    ASSERT_TRUE([operation didWork]);
    ASSERT_NO_THROW([operation release]);

    MyNonconcurrentOperation* operation2 = [[MyNonconcurrentOperation new] autorelease];
    [operation2 cancel];

    [queue addOperation:operation2];
    [operation2 waitUntilFinished];
    ASSERT_TRUE([operation2 isCancelled]);
    ASSERT_TRUE([operation2 isFinished]);
    ASSERT_FALSE([operation2 isExecuting]);
    ASSERT_FALSE([operation2 didWork]);
}

TEST(NSOperation, NSOperationMultipleWaiters) {
    NSOperationQueue* queue = [[NSOperationQueue new] autorelease];

    NSOperation* operation = [[NSOperation new] autorelease];

    [operation setCompletionBlock:^{
        [operation waitUntilFinished]; // Should not deadlock, but we cannot test this
        ASSERT_TRUE([operation isFinished]);
    }];

    [operation performSelectorInBackground:@selector(waitUntilFinished) withObject:nil];
    [operation performSelectorInBackground:@selector(waitUntilFinished) withObject:nil];
    // Any lingering threads will make the test hang, unfortunately we have no way around this.

    [queue addOperation:operation];

    [operation waitUntilFinished];

    ASSERT_TRUE([operation isFinished]);
}

TEST(NSOperation, NSDependencyRemove) {
    // tests that nothing happens when a dependency is removed that was never added.
    NSOperation* operation = [[NSOperation new] autorelease];
    NSOperation* dependency = [[NSOperation new] autorelease];

    ASSERT_NO_THROW([operation removeDependency:dependency]);
}

TEST(NSOperation, NSOperationWithDependenciesDoesRun) {
    NSOperationQueue* queue = [[NSOperationQueue new] autorelease];
    TestObserver* observer = [[TestObserver new] autorelease];

    NSCondition* dep1Condition = nil;
    BOOL dep1Completed = NO;
    NSOperation* dependency1 = [[NSOperation new] autorelease];
    [dependency1 setCompletionBlock:_completionBlockPopulatingConditionAndFlag(nil, &dep1Condition, &dep1Completed)];

    NSCondition* dep2Condition = nil;
    BOOL dep2Completed = NO;
    NSOperation* dependency2 = [[NSOperation new] autorelease];
    [dependency2 setCompletionBlock:_completionBlockPopulatingConditionAndFlag(nil, &dep2Condition, &dep2Completed)];

    NSOperation* operation = [[NSOperation new] autorelease];
    NSCondition* completionCondition = nil;
    BOOL completionBlockCalled = NO;
    [operation setCompletionBlock:_completionBlockPopulatingConditionAndFlag(nil, &completionCondition, &completionBlockCalled)];

    [operation addDependency:dependency1];
    [operation addDependency:dependency2];

    EXPECT_FALSE([operation isReady]);

    // Stage the operation before its dependencies.
    [queue addOperation:operation];

    [dep1Condition lock];
    [queue addOperation:dependency1];
    [dep1Condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:2.0]];
    [dep1Condition unlock];
    EXPECT_TRUE(dep1Completed);
    EXPECT_FALSE(dep2Completed);
    EXPECT_FALSE(completionBlockCalled);

    [completionCondition lock]; // dep2 will trigger operation to complete.
    [dep2Condition lock];
    [queue addOperation:dependency2];
    [dep2Condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:2.0]];
    [dep2Condition unlock];
    EXPECT_TRUE(dep2Completed);

    [completionCondition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:2.0]];
    [completionCondition unlock];
    EXPECT_TRUE(completionBlockCalled);
}

TEST(NSOperation, NSOperationWithDependenciesInDifferentPrioritiesDoesRun) {
    NSOperationQueue* queue = [[NSOperationQueue new] autorelease];
    TestObserver* observer = [[TestObserver new] autorelease];

    NSCondition* dep1Condition = nil;
    BOOL dep1Completed = NO;
    NSOperation* dependency1 = [[NSOperation new] autorelease];
    dependency1.queuePriority = NSOperationQueuePriorityVeryLow;
    [dependency1 setCompletionBlock:_completionBlockPopulatingConditionAndFlag(nil, &dep1Condition, &dep1Completed)];

    NSOperation* operation = [[NSOperation new] autorelease];
    operation.queuePriority = NSOperationQueuePriorityVeryHigh;
    NSCondition* completionCondition = nil;
    BOOL completionBlockCalled = NO;
    [operation setCompletionBlock:_completionBlockPopulatingConditionAndFlag(nil, &completionCondition, &completionBlockCalled)];

    [operation addDependency:dependency1];

    EXPECT_FALSE([operation isReady]);

    // Stage the operation before its dependencies.
    [queue addOperation:operation];

    [completionCondition lock]; // dep1 will trigger operation to complete.
    [dep1Condition lock];
    [queue addOperation:dependency1];
    [dep1Condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:2.0]];
    [dep1Condition unlock];
    EXPECT_TRUE(dep1Completed);
    EXPECT_FALSE(completionBlockCalled);

    [completionCondition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:2.0]];
    [completionCondition unlock];
    EXPECT_TRUE(completionBlockCalled);
}

// On the reference platform, we cannot observe isReady immediately.
// There appears to be a marked laziness in signalling the ready status via
// dependency completion.
// waitUntilFinished (for dependency2) triggers before didChangeValueForKey:@"isFinished" --
// sometimes long before it -- and we can jump the gun on the ready observation.
// WinObjC updates these flags immediately and only releases a waitUntilFinished when
// didChangeValueForKey: has already triggered.
OSX_DISABLED_TEST(NSOperation, NSOperationIsReady) {
    NSOperationQueue* queue = [[NSOperationQueue new] autorelease];
    TestObserver* observer = [[TestObserver new] autorelease];
    NSOperation* dependency1 = [[NSOperation new] autorelease];
    NSOperation* dependency2 = [[NSOperation new] autorelease];
    NSOperation* dependency3 = [[NSOperation new] autorelease];

    NSOperation* operation = [[NSOperation new] autorelease];
    ASSERT_TRUE([operation isReady]);
    [operation addObserver:observer forKeyPath:@"isReady" options:0 context:NULL];
    ASSERT_FALSE([observer didObserveReady]);

    [operation addDependency:dependency1];
    [operation addDependency:dependency2];

    ASSERT_TRUE([observer didObserveReady]);
    ASSERT_FALSE([operation isReady]);
    [observer setDidObserveReady:NO];

    [queue addOperation:dependency1];
    [dependency1 waitUntilFinished];
    ASSERT_FALSE([observer didObserveReady]);
    ASSERT_FALSE([operation isReady]);

    [queue addOperation:dependency2];
    [dependency2 waitUntilFinished];

    ASSERT_TRUE([observer didObserveReady]);
    ASSERT_TRUE([operation isReady]);
    [observer setDidObserveReady:NO];

    [operation addDependency:dependency3];
    ASSERT_TRUE([observer didObserveReady]);
    ASSERT_FALSE([operation isReady]);
    [observer setDidObserveReady:NO];

    [operation cancel];
    ASSERT_TRUE([observer didObserveReady]);
    ASSERT_TRUE([operation isReady]);
    [observer setDidObserveReady:NO];

    [operation removeObserver:observer forKeyPath:@"isReady" context:NULL];
}

TEST(NSOperation, RunConcurrentOperationManually) {
    NSOperation* operation = [MyConcurrentOperation new];

    NSCondition* completionCondition = nil;
    BOOL completionBlockCalled = NO;
    [operation setCompletionBlock:_completionBlockPopulatingConditionAndFlag(
                                      ^{
                                          [operation waitUntilFinished]; // Should not deadlock, but we cannot test this
                                          ASSERT_TRUE([operation isFinished]);
                                      },
                                      &completionCondition,
                                      &completionBlockCalled)];

    [completionCondition lock];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [operation start];
    });

    [operation waitUntilFinished];

    [completionCondition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]];
    [completionCondition unlock];

    ASSERT_TRUE(completionBlockCalled);
    ASSERT_TRUE([operation isFinished]);
    ASSERT_FALSE([operation isExecuting]);
    ASSERT_NO_THROW([operation release]);
}

TEST(NSOperation, RunNonconcurrentOperationManually) {
    NSOperation* operation = [MyNonconcurrentOperation new];

    NSCondition* completionCondition = nil;
    BOOL completionBlockCalled = NO;
    [operation setCompletionBlock:_completionBlockPopulatingConditionAndFlag(
                                      ^{
                                          [operation waitUntilFinished]; // Should not deadlock, but we cannot test this
                                          ASSERT_TRUE([operation isFinished]);
                                      },
                                      &completionCondition,
                                      &completionBlockCalled)];

    [completionCondition lock];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [operation start];
    });

    [operation waitUntilFinished];

    [completionCondition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]];
    [completionCondition unlock];

    ASSERT_TRUE(completionBlockCalled);
    ASSERT_TRUE([operation isFinished]);
    ASSERT_FALSE([operation isExecuting]);
    ASSERT_NO_THROW([operation release]);
}

TEST(NSOperation, NSBlockOperationInQueue) {
    NSOperationQueue* queue = [[NSOperationQueue new] autorelease];

    __block BOOL executedBlock = NO;
    NSOperation* operation = [NSBlockOperation blockOperationWithBlock:^{
        executedBlock = YES;
    }];

    NSCondition* completionCondition = nil;
    BOOL completionBlockCalled = NO;
    [operation setCompletionBlock:_completionBlockPopulatingConditionAndFlag(
                                      ^{
                                          [operation waitUntilFinished]; // Should not deadlock, but we cannot test this
                                          ASSERT_TRUE([operation isFinished]);
                                          ASSERT_TRUE(executedBlock);
                                      },
                                      &completionCondition,
                                      &completionBlockCalled)];

    [completionCondition lock];

    [queue addOperation:operation];

    [operation waitUntilFinished];

    [completionCondition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]];
    [completionCondition unlock];

    ASSERT_TRUE(completionBlockCalled);
    ASSERT_TRUE([operation isFinished]);
    ASSERT_FALSE([operation isExecuting]);
}

TEST(NSOperation, MainQueue) {
    NSOperationQueue* mainQueue = [NSOperationQueue mainQueue];

    ASSERT_OBJCNE(mainQueue, nil);

    // mainQueue has an unchangeable underlying queue
    ASSERT_NO_THROW([mainQueue setUnderlyingQueue:nil]);
    ASSERT_EQ([mainQueue underlyingQueue], dispatch_get_main_queue());
    ASSERT_NO_THROW([mainQueue setUnderlyingQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)]);
    ASSERT_EQ([mainQueue underlyingQueue], dispatch_get_main_queue());
    ASSERT_NO_THROW([mainQueue setUnderlyingQueue:dispatch_get_main_queue()]);
    ASSERT_EQ([mainQueue underlyingQueue], dispatch_get_main_queue());
}

TEST(NSOperation, CurrentQueue) {
// TODO #: WinObjC's implementation of NSThread does not consider this context the main thread - this is a bug
#if !WINOBJC
    // Check that the current queue on the main thread is the main queue
    EXPECT_OBJCEQ([NSOperationQueue mainQueue], [NSOperationQueue currentQueue]);
#endif

    // Check that the current queue is correct at each stage
    __block NSOperationQueue* currentQueue;
    __block NSOperationQueue* queue = [[NSOperationQueue new] autorelease];
    __block NSOperation* operation = [NSBlockOperation blockOperationWithBlock:^{
        currentQueue = [NSOperationQueue currentQueue];
    }];

    __block NSOperationQueue* currentQueue2;
    NSOperationQueue* queue2 = [[NSOperationQueue new] autorelease];
    NSOperation* operation2 = [NSBlockOperation blockOperationWithBlock:^{
        [queue addOperation:operation];
        [operation waitUntilFinished];
        currentQueue2 = [NSOperationQueue currentQueue];
    }];

    [queue2 addOperation:operation2];

    [operation2 waitUntilFinished];
    EXPECT_OBJCEQ(queue, currentQueue);
    EXPECT_OBJCEQ(queue2, currentQueue2);
}

@interface BlockThread : NSThread
- (instancetype)initWithBlock:(void (^)())block;
@property (copy) void (^block)();
@end

@implementation BlockThread
- (instancetype)initWithBlock:(void (^)())block {
    if (self = [super init]) {
        self.block = block;
    }
    return self;
}

- (void)main {
    self.block();
}
@end

TEST(NSOperation, AddOperations) {
    __block NSOperationQueue* queue = [[NSOperationQueue new] autorelease];
    [queue setMaxConcurrentOperationCount:5];

    __block size_t opsFinished = 0;
    __block _NSBooleanCondition* startLock = [[_NSBooleanCondition new] autorelease];
    void (^incrementOpsFinished)() = ^void() {
        ASSERT_TRUE_MSG([startLock waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]], "Operation was not allowed to start in time.");
        ++opsFinished;
    };

    __block NSArray<NSOperation*>* ops = @[
        [NSBlockOperation blockOperationWithBlock:Block_copy(incrementOpsFinished)],
        [NSBlockOperation blockOperationWithBlock:Block_copy(incrementOpsFinished)],
        [NSBlockOperation blockOperationWithBlock:Block_copy(incrementOpsFinished)]
    ];

    NSThread* addOperationsThread = [[[BlockThread alloc] initWithBlock:^void() {
        [queue addOperations:ops waitUntilFinished:YES];
    }] autorelease];
    [addOperationsThread start];

    // TODO: Do this better
    while (queue.operationCount < 3) {
    }

    ASSERT_OBJCEQ(ops, [queue operations]);
    ASSERT_EQ([ops count], [queue operationCount]);
    ASSERT_TRUE([addOperationsThread isExecuting]);
    ASSERT_FALSE([addOperationsThread isFinished]);
    ASSERT_EQ(0, opsFinished);

    __block _NSBooleanCondition* startLock2 = [[_NSBooleanCondition new] autorelease];
    void (^incrementOpsFinished2)() = ^void() {
        ASSERT_TRUE_MSG([startLock2 waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]], "Operation was not allowed to start in time.");
        ++opsFinished;
    };

    __block NSArray<NSOperation*>* ops2 = @[
        [NSBlockOperation blockOperationWithBlock:Block_copy(incrementOpsFinished2)],
        [NSBlockOperation blockOperationWithBlock:Block_copy(incrementOpsFinished2)],
    ];
    NSThread* addOperationsThread2 = [[[BlockThread alloc] initWithBlock:^void() {
        [queue addOperations:ops2 waitUntilFinished:NO];
    }] autorelease];
    [addOperationsThread2 start];

    // TODO: Do this better
    while (queue.operationCount < 5) {
    }

    ASSERT_EQ(5, [queue operationCount]);
    ASSERT_EQ(0, opsFinished);

    [startLock broadcast];

    for (NSOperation* op in ops) {
        [op waitUntilFinished];
    }

    // TODO: Do this better
    while (![addOperationsThread isFinished]) {
    }

    ASSERT_EQ(3, opsFinished);

    [startLock2 broadcast];

    for (NSOperation* op in ops2) {
        [op waitUntilFinished];
    }
    ASSERT_EQ(5, opsFinished);
}

TEST(NSOperation, AddOperation_AndValidateState) {
    __block NSOperationQueue* queue = [[NSOperationQueue new] autorelease];
    [queue setSuspended:YES];

    __block _NSBooleanCondition* startedCondition = [[_NSBooleanCondition new] autorelease];
    __block _NSBooleanCondition* finishCondition = [[_NSBooleanCondition new] autorelease];
    NSOperation* operation = [NSBlockOperation blockOperationWithBlock:^void() {
        [startedCondition broadcast];
        ASSERT_TRUE_MSG([finishCondition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]],
                        "Operation was not allowed to finish in time.");
    }];

    // Validate the initial state of the queue and operation
    ASSERT_EQ(0, queue.operationCount);
    ASSERT_OBJCEQ(@[], queue.operations);
    ASSERT_FALSE(operation.isExecuting);
    ASSERT_FALSE(operation.isFinished);

    // Add the operation to the queue. The operations/count should reflect the add, but the operation should not have started.
    [queue addOperation:operation];
    ASSERT_EQ(1, queue.operationCount);
    ASSERT_OBJCEQ(@[ operation ], queue.operations);
    ASSERT_FALSE(operation.isExecuting);
    ASSERT_FALSE(operation.isFinished);

    // Unsuspend the queue. The operation should start shortly.
    [queue setSuspended:NO];
    ASSERT_TRUE_MSG([startedCondition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]], "Operation did not start in time.");
    ASSERT_EQ(1, queue.operationCount);
    ASSERT_OBJCEQ(@[ operation ], queue.operations);
    ASSERT_TRUE(operation.isExecuting);
    ASSERT_FALSE(operation.isFinished);

    // Allow the operation to run. The operation should finish shortly.
    [finishCondition broadcast];
    [queue waitUntilAllOperationsAreFinished];
    ASSERT_EQ(0, queue.operationCount);
    ASSERT_OBJCEQ(@[], queue.operations);
    ASSERT_FALSE(operation.isExecuting);
    ASSERT_TRUE(operation.isFinished);
}

TEST(NSOperation, AddOperationWithBlock) {
    NSOperationQueue* queue = [[NSOperationQueue new] autorelease];
    __block bool flag = false;
    [queue addOperationWithBlock:^void() {
        flag = true;
    }];
    [queue waitUntilAllOperationsAreFinished];
    ASSERT_TRUE(flag);
}