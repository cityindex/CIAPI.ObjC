//
//  LSSession+Internals.h
//  iStreamLight v. 1.0.6
//
//  Created by Gianluca Bertani on 08/07/08.
//  Copyright 2008-2010 Flying Dolphin Studio. All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without 
//  modification, are permitted provided that the following conditions 
//  are met:
//
//  * Redistributions of source code must retain the above copyright notice, 
//    this list of conditions and the following disclaimer.
//  * Redistributions in binary form must reproduce the above copyright notice, 
//    this list of conditions and the following disclaimer in the documentation 
//    and/or other materials provided with the distribution.
//  * Neither the name of Gianluca Bertani nor the names of its contributors 
//    may be used to endorse or promote products derived from this software 
//    without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" 
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
//  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE 
//  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
//  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
//  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
//  POSSIBILITY OF SUCH DAMAGE.
//

/*!
 @header		LSSession+Internals
 @abstract		LSSession implementation internals
 @discussion	Not to be used directly
*/

#import "LSSession.h"


@interface LSSession (Internals)

- (id) init;

- (void) create:(LSClient *)client host:(NSString *)host port:(NSInteger)port secure:(BOOL)secure user:(NSString *)user password:(NSString *)password adapterSet:(NSString *)adapterSet listener:(id<LSListener>)listener options:(LSSessionOptions *)options autorebind:(BOOL)autorebind;
- (void) bind:(NSString *)host port:(NSInteger)port secure:(BOOL)secure options:(LSSessionOptions *)options;

- (void) connectAndReceive;
- (void) disconnect;
- (void) stream:(NSStream *)stream handleEvent:(NSStreamEvent)streamEvent;
- (void) handleStreamError:(LSException *)exception;
- (void) handleStreamClose;

- (void) parseHttpResponse:(NSString *)response;
- (void) parseCreateResponse:(NSString *)response;
- (void) parseBindResponse:(NSString *)response;
- (void) parseUpdate:(NSString *)update;

- (void) control:(NSString *)path query:(NSString *)query;

+ (NSString *) unescapeUnicodeString:(NSString *)escapedString;

@end