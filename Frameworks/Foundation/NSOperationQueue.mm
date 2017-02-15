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

#import "Starboard.h"

static long _QOSClassForNSQualityOfService(NSQualityOfService quality) {
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
static NSString* const _NSOperationQueueCurrentQueueKey = @"_NSOperationQueueCurrentQueueKey";

@implementation NSOperationQueue {
@private
    dispatch_queue_t _dispatchQueue;

    NSQualityOfService _qualityOfService;

    // Signalled when operationCount reaches 0, for waitUntilAllOperationsAreFinished
    StrongId<NSCondition> _operationCountCondition;

    // This backs the user-set value of _underlyingQueue. _dispatchQueue is changed to target this if this is set.
    dispatch_queue_t _underlyingQueue;
}

// Private helper that executes a single NSOperation on the dispatch queue and manages associated state.
void _executeOperation(NSOperationQueue* queue, NSOperation* operation) {
    dispatch_async(queue->_dispatchQueue, ^{
        // Get the currentQueue stored in the thread dictionary
        NSDictionary* threadDictionary = [[NSThread currentThread] threadDictionary];
        StrongId<NSOperationQueue> currentQueue = [threadDictionary objectForKey:_NSOperationQueueCurrentQueueKey];

        // If this queue is not the current queue, store this queue while this operation is running, and restore it once it returns.
        bool queueChanged = [queue isEqual:currentQueue];
        if (queueChanged) {
            [threadDictionary setValue:queue forKey:_NSOperationQueueCurrentQueueKey];
        }

        wil::ScopeExit([threadDictionary, currentQueue, queueChanged]() {
            if (queueChanged) {
                [threadDictionary setValue:currentQueue forKey:_NSOperationQueueCurrentQueueKey];
            }
        });

        // Run the actual operation
        [operation start];
    });
}

+ (BOOL)automaticallyNotifiesObserversOfOperationCount {
    // This class manually notifies for operationCount, as it changes at the same time as operations
    return NO;
}

/**
 @Status Interoperable
*/
+ (NSOperationQueue*)currentQueue {
    return [[[NSThread currentThread] threadDictionary] objectForKey:_NSOperationQueueCurrentQueueKey];
}

/**
 @Status Interoperable
*/
+ (NSOperationQueue*)mainQueue {
    static StrongId<NSOperationQueue> mainQueue = [[NSOperationQueue new] autorelease];
    // TODO: Need to set up some reasonable defaults
    return mainQueue;
}

/**
 @Status Interoperable
*/
- (void)addOperation:(NSOperation*)op {
    _executeOperation(self, op);
}

/**
 @Status Interoperable
*/
- (void)addOperations:(NSArray<NSOperation*>*)ops waitUntilFinished:(BOOL)wait {
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
- (NSUInteger)operationCount {
    return [_operations count];
}

/**
 @Status Interoperable
*/
- (void)cancelAllOperations {
    @synchronized(self) { // TODO: is this necessary?
        for (NSOperation* operation in _operations) {
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

        if (_underlyingQueue) {
            return; // underlyingQueue overrides qualityOfService
        }

        // Retarget the dispatch queue to a global queue with the right QOS
        dispatch_set_target_queue(_dispatchQueue, dispatch_get_global_queue(_QOSClassForNSQualityOfService(quality), 0));
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

        _underlyingQueue = queue;

        if (queue) {
            // Change targets to the new underlying queue
            dispatch_set_target_queue(_dispatchQueue, queue);
        } else {
            // Return to using qualityOfService
            dispatch_set_target_queue(_dispatchQueue, dispatch_get_global_queue(_QOSClassForNSQualityOfService(_qualityOfService), 0));
        }
    }
}

@end