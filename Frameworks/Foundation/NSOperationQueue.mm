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

#import <Foundation/NSOperationQueue.h>

#import <Foundation/NSBlockOperation.h>
#import <Foundation/NSCondition.h>

#import "NSOperationInternal.h"
#import "Starboard.h"

#import <queue>

static inline long _QOSClassForNSQualityOfService(NSQualityOfService quality) {
    switch (quality) {
        case NSQualityOfServiceUserInteractive:
            return QOS_CLASS_USER_INTERACTIVE;
        case NSQualityOfServiceUserInitiated:
            return QOS_CLASS_USER_INITIATED;
        case NSQualityOfServiceUtility:
            return QOS_CLASS_UTILITY;
        case NSQualityOfServiceBackground:
            // currently generates a warning:
            // 'QOS_CLASS_BACKGROUND' is deprecated: QOS_CLASS_BACKGROUND is the same as DISPATCH_QUEUE_PRIORITY_LOW on WinObjC
            // should go away once libdispatch is updated
            return QOS_CLASS_BACKGROUND;
        case NSQualityOfServiceDefault:
        default:
            return QOS_CLASS_DEFAULT;
    }
}

// Used for [NSOperationQueue currentQueue] - when an NSOperation is executed through an NSOperationQueue,
// the current queue is stored in the thread dictionary using this key.
static const NSString* const _NSOperationQueueCurrentQueueKey = @"_NSOperationQueueCurrentQueueKey";

static const NSString* const _NSOperationQueue_OperationFinished = @"_NSOperationQueue_OperationFinished";
static const NSString* const _NSOperationQueue_OperationReady = @"_NSOperationQueue_OperationReady";

@interface NSOperationQueue_MainQueue : NSOperationQueue
@end

@implementation NSOperationQueue_MainQueue

- (dispatch_queue_t)underlyingQueue {
    return dispatch_get_main_queue();
}

- (void)setUnderlyingQueue:(dispatch_queue_t)queue {
}

@end

@implementation NSOperationQueue {
@private
    dispatch_queue_t _dispatchQueue;

    StrongId<NSMutableArray> _operations;
    std::deque<NSOperation*> _unstartedOperations;
    NSInteger _numExecutingOperations;

    // Signalled when operationCount reaches 0, for waitUntilAllOperationsAreFinished
    // This condition only needs to be locked in waitUntilAllOperationsAreFinished, and in functions that _decrease_ the operation count
    StrongId<NSCondition> _operationCountCondition;

    NSQualityOfService _qualityOfService;
    BOOL _suspended;

    // This backs the user-set value of _underlyingQueue. _dispatchQueue is changed to target this if this is set.
    dispatch_queue_t _underlyingQueue;
}

// Private helper that executes a single NSOperation on the dispatch queue and manages associated state.
static void _executeOperation(NSOperationQueue* queue, NSOperation* operation) {
    dispatch_async(queue->_dispatchQueue, ^{
        // Get the currentQueue stored in the thread dictionary
        NSMutableDictionary* threadDictionary = [[NSThread currentThread] threadDictionary];
        StrongId<NSOperationQueue> currentQueue = [threadDictionary objectForKey:_NSOperationQueueCurrentQueueKey];

        // // If this queue is not the current queue, store this queue while this operation is running, and restore it once it returns.
        // bool queueChanged = ![queue isEqual:currentQueue];
        // if (queueChanged) {
        //     [threadDictionary setObject:queue forKey:_NSOperationQueueCurrentQueueKey];
        // }

        // wil::ScopeExit([threadDictionary, currentQueue, queueChanged]() {
        //     if (queueChanged) {
        //         if (currentQueue) {
        //             [threadDictionary setObject:currentQueue forKey:_NSOperationQueueCurrentQueueKey];
        //         } else {
        //             [threadDictionary removeObjectForKey:_NSOperationQueueCurrentQueueKey];
        //         }
        //     }
        // });

        bool queueChanged = ![queue isEqual:currentQueue];

        if (![[NSThread currentThread] isMainThread]) {
            if (queueChanged) {
                [threadDictionary setObject:queue forKey:_NSOperationQueueCurrentQueueKey];
            }
        }

        // TODO: Need to restore at operation finish

        auto foo = wil::ScopeExit([threadDictionary, currentQueue, queueChanged]() {

            if (![[NSThread currentThread] isMainThread]) {
                if (queueChanged) {
                    if (currentQueue) {
                        [threadDictionary setObject:currentQueue forKey:_NSOperationQueueCurrentQueueKey];
                    } else {
                        [threadDictionary removeObjectForKey:_NSOperationQueueCurrentQueueKey];
                    }
                }
            }
        });

        ++queue->_numExecutingOperations;

        // Run the actual operation
        [operation start];

    });
}

void _setTargetQueueUsingQualityOfService(NSOperationQueue* queue) {
    dispatch_set_target_queue(queue->_dispatchQueue,
                              dispatch_get_global_queue(_QOSClassForNSQualityOfService(queue->_qualityOfService), 0));
}

- (instancetype)init {
    if (self = [super init]) {
        _dispatchQueue = dispatch_queue_create("com.microsoft.winobjc.NSOperationQueue_dispatchQueue", DISPATCH_QUEUE_CONCURRENT);

        _operations.attach([NSMutableArray new]);
        _operationCountCondition.attach([NSCondition new]);

        _maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount;

        _qualityOfService = NSQualityOfServiceDefault;

        if (dispatch_queue_t underlyingQueue = [self underlyingQueue]) {
            dispatch_set_target_queue(_dispatchQueue, underlyingQueue);
        } else {
            _setTargetQueueUsingQualityOfService(self);
        }
    }
    return self;
}

- (void)dealloc {
    [_name release];

    if (_dispatchQueue) {
        dispatch_release(_dispatchQueue);
    }

    if (_underlyingQueue) {
        dispatch_release(_underlyingQueue);
    }

    [super dealloc];
}

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context {
    if ((context == _NSOperationQueue_OperationFinished) && ([object isKindOfClass:[NSOperation class]])) {
        NSOperation* op = static_cast<NSOperation*>(object);
        if ([op isFinished]) {
            @synchronized(self) { // TODO: Is this the right synch
                // Minor optimization: Search indexOfObject:op instead of directly using removeObject:
                // removeObject: keeps going after finding first instance of object
                // Because of constraints in addOperation:, it is safe to assume that there is exactly one instance of op in the array,
                // making the removeObject: behavior unnecessary
                NSUInteger index = [_operations indexOfObject:op];
                if (index != NSNotFound) {
                    --_numExecutingOperations;
                    [op removeObserver:self forKeyPath:@"isFinished" context:(void*)_NSOperationQueue_OperationFinished];
                    [op removeObserver:self forKeyPath:@"isReady" context:(void*)_NSOperationQueue_OperationReady];

                    [self willChangeValueForKey:@"operations"];
                    [self willChangeValueForKey:@"operationCount"];
                    [_operations removeObjectAtIndex:index];
                    [_operationCountCondition lock];
                    if (self.operationCount == 0) {
                        [_operationCountCondition broadcast];
                    }
                    [_operationCountCondition unlock];
                    [self didChangeValueForKey:@"operationCount"];
                    [self didChangeValueForKey:@"operations"];
                }
            }

            // TODO: start more ops?
        }
    } else if ((context == _NSOperationQueue_OperationReady) && ([object isKindOfClass:[NSOperation class]])) {
        NSOperation* op = static_cast<NSOperation*>(object);
        @synchronized(self) { // TODO: Is this the right synch
            if ((!_suspended) && ([op isReady]) && (_numExecutingOperations <= _maxConcurrentOperationCount)) {
                _executeOperation(self, op);
            }
            // TODO: what if it become not-ready?
        }
    }
}

+ (BOOL)automaticallyNotifiesObserversOfOperations {
    // This class manually notifies for operations, which generates changes in addOperation/s.
    return NO;
}

+ (BOOL)automaticallyNotifiesObserversOfOperationCount {
    // This class manually notifies for operationCount, as it changes at the same time as operations
    return NO;
}

/**
 @Status Interoperable
*/
+ (NSOperationQueue*)currentQueue {
    NSThread* currentThread = [NSThread currentThread];
    if ([currentThread isMainThread]) {
        return [[self class] mainQueue];
    }

    return [[currentThread threadDictionary] objectForKey:_NSOperationQueueCurrentQueueKey];
}

/**
 @Status Interoperable
*/
+ (NSOperationQueue*)mainQueue {
    static StrongId<NSOperationQueue> mainQueue = [[NSOperationQueue_MainQueue new] autorelease];
    return mainQueue;
}

/**
 @Status Interoperable
*/
- (void)addOperation:(NSOperation*)op {
    @synchronized(op) {
        if ([op isExecuting] || [op isFinished]) {
            @throw [NSException exceptionWithName:NSInvalidArgumentException
                                           reason:@"operation is already or finished executing"
                                         userInfo:nil];
        }

        if (op._operationQueue) {
            @throw [NSException exceptionWithName:NSInvalidArgumentException
                                           reason:@"operation is already in an operation queue"
                                         userInfo:nil];
        }

        op._operationQueue = self;

        @synchronized(self) {
            [self willChangeValueForKey:@"operations"];
            [self willChangeValueForKey:@"operationCount"];
            [_operations addObject:op];
            [self didChangeValueForKey:@"operationCount"];
            [self didChangeValueForKey:@"operations"];

            [op addObserver:self forKeyPath:@"isFinished" options:0 context:(void*)_NSOperationQueue_OperationFinished];
            [op addObserver:self forKeyPath:@"isReady" options:0 context:(void*)_NSOperationQueue_OperationReady];

            if ((!_suspended) && ([op isReady]) && (_numExecutingOperations <= _maxConcurrentOperationCount)) {
                _executeOperation(self, op);
            } else {
                _unstartedOperations.push_back(op);
            }
        }
    }
}

/**
 @Status Interoperable
*/
- (void)addOperations:(NSArray<NSOperation*>*)ops waitUntilFinished:(BOOL)wait {
    for (NSOperation* operation in ops) {
        [self addOperation:operation];
    }

    if (wait) {
        for (NSOperation* operation in ops) {
            [operation waitUntilFinished];
        }
    }
}

/**
 @Status Interoperable
*/
- (void)addOperationWithBlock:(void (^)(void))block {
    [self addOperation:[NSBlockOperation blockOperationWithBlock:block]];
}

/**
 @Status Interoperable
*/
- (NSArray<__kindof NSOperation*>*)operations {
    return [_operations copy];
}

/**
 @Status Interoperable
*/
- (NSUInteger)operationCount {
    return [_operations count];
}

/**
 @Status Interoperable
*/
- (void)cancelAllOperations {
    @synchronized(self) { // TODO: is this necessary?
        for (NSOperation* operation in _operations.get()) {
            [operation cancel];
        }
        // TODO: How to deal with removals?
    }
}

/**
 @Status Interoperable
*/
- (void)waitUntilAllOperationsAreFinished {
    [_operationCountCondition lock];
    while ([self operationCount] > 0) {
        [_operationCountCondition wait];
    }
    // If the while loop has completed, all operations have finished
    [_operationCountCondition unlock];
}

/**
 @Status Interoperable
*/
- (NSQualityOfService)qualityOfService {
    @synchronized(self) {
        return _qualityOfService;
    }
}

/**
 @Status Interoperable
*/
- (void)setQualityOfService:(NSQualityOfService)quality {
    @synchronized(self) {
        if (_qualityOfService == quality) {
            return;
        }

        _qualityOfService = quality;

        if ([self underlyingQueue]) {
            return; // underlyingQueue overrides qualityOfService
        }

        // Retarget the dispatch queue to a global queue with the right QOS
        _setTargetQueueUsingQualityOfService(self);
    }
}

/**
 @Status Interoperable
*/
- (BOOL)isSuspended {
    @synchronized(self) {
        return _suspended;
    }
}

/**
 @Status Interoperable
*/
- (void)setSuspended:(BOOL)suspended {
    @synchronized(self) {
        _suspended = suspended;

        if (!_suspended) {
            size_t i = 0;
            while ((_numExecutingOperations <= _maxConcurrentOperationCount) && (i < _unstartedOperations.size())) {
                NSOperation* op = _unstartedOperations[i];
                if ([op isReady]) {
                    _executeOperation(self, op);
                    _unstartedOperations.erase(_unstartedOperations.begin() + i);
                } else {
                    ++i;
                }
            }
        }
    }
}

/**
 @Status Interoperable
*/
- (dispatch_queue_t)underlyingQueue {
    @synchronized(self) {
        return _underlyingQueue;
    }
}

/**
 @Status Interoperable
*/
- (void)setUnderlyingQueue:(dispatch_queue_t)queue {
    @synchronized(self) {
        if (queue == _underlyingQueue) {
            return;
        }

        if (self.operationCount != 0) {
            @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"operationCount is not equal to 0" userInfo:nil];
        }

        if (queue == dispatch_get_main_queue()) {
            @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"underlyingQueue must not be main queue" userInfo:nil];
        }

        // release a ref to the old underlying queue if it exists
        if (_underlyingQueue) {
            dispatch_release(_underlyingQueue);
        }

        if (queue) {
            // Change targets to the new underlying queue
            dispatch_retain(queue);
            dispatch_set_target_queue(_dispatchQueue, queue);
        } else {
            // Return to using qualityOfService
            _setTargetQueueUsingQualityOfService(self);
        }

        _underlyingQueue = queue;
    }
}

@end