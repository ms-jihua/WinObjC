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

@implementation NSOperationQueue {
    dispatch_queue_t _queue;
}

/**
 @Status Interoperable
*/
+ (NSOperationQueue*)currentQueue {
}

/**
 @Status Interoperable
*/
+ (NSOperationQueue*)mainQueue {
}

/**
 @Status Interoperable
*/
- (void)addOperation:(NSOperation*)op {
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
}

@end