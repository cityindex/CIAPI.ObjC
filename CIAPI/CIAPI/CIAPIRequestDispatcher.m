//
//  RequestDispatcher.m
//  CIAPI
//
//  Created by Adam Wright on 19/06/2011.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "CIAPIRequestDispatcher.h"

#import "JSONKit.h"
#import "ThrottledQueue.h"

#import "CIAPIURLConnection.h"
#import "CIAPIRequestToken.h"
#import "CIAPIObjectRequest.h"
#import "CIAPIObjectResponse.h"
#import "CIAPILogging.h"

@implementation CIAPIRequestDispatcher

@synthesize maximumRequestAttempts;
@synthesize throttleSize;
@synthesize throttlePeriod;
@synthesize delegate;

- (CIAPIRequestDispatcher*)initWithMaximumRetryAttempts:(NSUInteger)_maximumRequestAttempts throttleSize:(NSUInteger)_throttleSize
                                    throttlePeriod:(NSTimeInterval)_throttlePeriod;
{
    self = [super init];
    
    if (self)
    {
        CIAPILogAbout(CIAPILogLevelNote, CIAPIDispatcherModule, self,
                      @"Creating RequestDispatcher with maxAttempt %u, throttle size %u, throttle period %d",
                      _maximumRequestAttempts, _throttleSize, _throttlePeriod);
        
        maximumRequestAttempts = _maximumRequestAttempts;
        throttleSize = _throttleSize;
        throttlePeriod = _throttlePeriod;
        
        namedQueueMap = [[NSMutableDictionary alloc] init];
        connectionToTokenMapper = [[NSMutableDictionary alloc] init];
        queueMultiplexer = [[ThrottledQueueMultiplexer alloc] init];
        
        // Create one global queue
        [namedQueueMap setObject:[ThrottledQueue throttledQueueWithLimit:throttleSize overPeriod:throttlePeriod] forKey:@"global"];
    }
    
    return self;
}

- (void)dealloc
{
    CIAPILogAbout(CIAPILogLevelNote, CIAPIDispatcherModule, self, @"Destroying RequestDispatcher");
    
    [namedQueueMap release];
    [connectionToTokenMapper release];
    [queueMultiplexer release];
    
    [super dealloc];
}

- (void)scheduleRequestToken:(CIAPIRequestToken*)token
{
    CIAPILogAbout(CIAPILogLevelNote, CIAPIDispatcherModule, token, @"Scheduling dispatch of request token %X", token);
    
    // Find the queue corresponding to the request, or create one
    ThrottledQueue *queue = nil;
    @synchronized (namedQueueMap)
    {
        queue = [namedQueueMap objectForKey:token.requestObject.throttleScope];
        
        if (queue == nil)
        {
            CIAPILogAbout(CIAPILogLevelNote, CIAPIDispatcherModule, self,
                          @"Creating a new request queue for throttle scope %@", token.requestObject.throttleScope);
            queue = [ThrottledQueue throttledQueueWithLimit:throttleSize overPeriod:throttlePeriod];
            [namedQueueMap setObject:queue forKey:token.requestObject.throttleScope];
        }
    }
    
    // Schedule it in that queue
    [queue enqueueObject:token];
}

- (BOOL)unscheduleRequestToken:(CIAPIRequestToken*)token
{
    CIAPILogAbout(CIAPILogLevelNote, CIAPIDispatcherModule, token, @"Unscheduling dispatch of request token %X", token);
    
    // Find the queue corresponding to the request
    ThrottledQueue *queue = nil;
    @synchronized (namedQueueMap)
    {
        queue = [namedQueueMap objectForKey:token.requestObject.throttleScope];
        
        NSAssert(queue != nil, @"Should not be able to reach a state where one is dequeuing an object from a non-existant queue!");
    }
    
    // De-schedule it in that queue, if we can
    BOOL didRemove = [queue removeObject:token];
    
    // TODO: Need to cancel the request if it's in-flight

    return didRemove;
}

- (void)startDispatcher
{
    CIAPILogAbout(CIAPILogLevelNote, CIAPIDispatcherModule, self, @"Starting dispatcher dispatch loop");
    
    NSAssert(dispatcherShouldRun == NO, @"Cannot start the dispatcher more than once");
    dispatcherShouldRun = YES;
    
    [NSThread detachNewThreadSelector:@selector(dispatchThread:) toTarget:self withObject:nil];
}
     
- (void)stopDispatcher
{
    CIAPILogAbout(CIAPILogLevelNote, CIAPIDispatcherModule, self, @"Stopping dispatcher dispatch loop");
    NSAssert(dispatcherShouldRun == YES, @"Cannot stop the dispatcher more than once");
    
    queueMultiplexer.stopDequeue = YES;
    dispatcherShouldRun = NO;
}

- (void)dispatchThread:(id)ignore
{
    [self retain];
    
    while (dispatcherShouldRun)
    {
        CIAPIRequestToken *requestObject = [queueMultiplexer dequeueObject];
        
        // We might have broken out of the multiplexer due to a stop request
        if (!dispatcherShouldRun)
        {
            CIAPILogAbout(CIAPILogLevelNote, CIAPIDispatcherModule, self, @"Stopping dispatch loop due to user request");
            break;
        }
        
        if (!requestObject)
        {
            // The multiplexer has quit, hopefully due to user request, so we'll spin until we're asked to do the same
            continue;
        }
        
        CIAPILogAbout(CIAPILogLevelNote, CIAPIDispatcherModule, requestObject, @"Actually dispatching token %X", requestObject);
        

        // Send the request        
        CIAPIURLConnection *urlConnection = [CIAPIURLConnection CIAPIURLConnectionForRequest:requestObject.underlyingRequest delegate:self];        
        [connectionToTokenMapper setObject:requestObject forKey:urlConnection];
        [urlConnection start];

        requestObject.attemptCount = requestObject.attemptCount++;

    }
    
    [self release];
}

/*
 * Private methods
 */

- (void)dispatchSuccessfulRequest:(CIAPIRequestToken*)token result:(id)result
{
    CIAPILogAbout(CIAPILogLevelNote, CIAPIDispatcherModule, token, @"Dispatch response SUCCEEDED for token %X", token);

    token.responseObject = result;
    
    if ([delegate respondsToSelector:@selector(willDispatchSuccessfulRequest:)])
        [delegate willReportSuccessfulRequest:token];
    
    // Dispatch onto the main thread
    [self performSelectorOnMainThread:@selector(mainThreadSuccessDispatcher:) withObject:token waitUntilDone:NO];
}

- (void)rescheduleFailedRequest:(CIAPIRequestToken*)token forLastError:(enum RequestFailureType)failureType
{
    CIAPILogAbout(CIAPILogLevelWarn, CIAPIDispatcherModule, token, @"Dispatch response FAILED for token %X", token);
    token.responseError = [NSError errorWithDomain:@"TODO" code:0 userInfo:nil];
    
    // Depending on the error, we may reschedule this request with a longer wait time
    if (token.attemptCount < maximumRequestAttempts)
        [self scheduleRequestToken:token];
    else
    {
        if ([delegate respondsToSelector:@selector(willDispatchFailedRequest:)])
            [delegate willReportFailedRequest:token];
        
        [self performSelectorOnMainThread:@selector(mainThreadFailureDispatcher:) withObject:token waitUntilDone:NO];
    }
}

- (void)mainThreadSuccessDispatcher:(CIAPIRequestToken*)token
{
    CIAPILogAbout(CIAPILogLevelWarn, CIAPIDispatcherModule, token, @"Main thread callback happening for token %X", token);
    
    if (token.callbackDelegate)
        [token.callbackBlock requestSucceeded:token result:token.responseObject];
    else if (token.callbackBlock)
        token.callbackBlock(token, token.responseObject, nil);
    else
        NSAssert(FALSE, @"Trying to dispatch a result, but was given neither delegate or block!");
    
    // TODO: Remove the token from the token mapping dictionary (the only thing keeping it alive)
}

- (void)mainThreadFailureDispatcher:(CIAPIRequestToken*)token
{
    CIAPILogAbout(CIAPILogLevelWarn, CIAPIDispatcherModule, token, @"Main thread callback happening for token %X", token);
    
    if (token.callbackDelegate)
        [token.callbackDelegate requestFailed:token error:token.responseError];
    else if (token.callbackBlock)
        token.callbackBlock(token, nil, token.responseError);
    else
        NSAssert(FALSE, @"Trying to dispatch a result, but was given neither delegate or block!");
    
    // TODO: Remove the token from the token mapping dictionary (the only thing keeping it alive)
}

/*
 * URL response delegate methods
 */

- (void)requestSucceeded:(CIAPIURLConnection*)connection request:(NSURLRequest*)request response:(NSHTTPURLResponse*)response data:(NSData*)data
{
    CIAPIRequestToken *token = [connectionToTokenMapper objectForKey:connection];
    if (!token)
        NSAssert(FALSE, @"We got a response for a request we never issued?");
    
    [connectionToTokenMapper removeObjectForKey:connection];
    
    if ([response statusCode] == 200)
    {
        // Decode the resultant object JSON into the response type
        id bodyObj = [data objectFromJSONData];
        
        CIAPIObjectResponse *responseObj = [[[token.requestObject responseClass] alloc] init];
        [responseObj setupFromDictionary:bodyObj error:nil];
        
        [self dispatchSuccessfulRequest:token result:responseObj];
        
        [responseObj release];
    }
    else
    {
        [self rescheduleFailedRequest:token forLastError:RequestUnknownError];
    }
}

- (void)requestFailed:(CIAPIURLConnection*)connection request:(NSURLRequest*)request response:(NSHTTPURLResponse*)response error:(NSError*)error
{
    CIAPIRequestToken *token = [connectionToTokenMapper objectForKey:connection];    
    if (!token)
        NSAssert(FALSE, @"We got a response for a request we never issued?");
    
    [connectionToTokenMapper removeObjectForKey:connection];
    
    [self rescheduleFailedRequest:token forLastError:RequestUnknownError];
}

@end