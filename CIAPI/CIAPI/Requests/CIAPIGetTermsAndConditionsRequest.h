//
//  CIAPIGetTermsAndConditionsRequest.h
//  CIAPI
//
//  Copyright 2011 Adam Wright/CityIndex. All rights reserved.
//


#import <Foundation/Foundation.h>

#import "CIAPIObjectRequest.h"


// What are the Users Terms and Conditions.
 
@interface CIAPIGetTermsAndConditionsRequest : CIAPIObjectRequest {
 NSString* clientaccount;
}

// What are the Users Terms and Conditions. 
@property (retain) NSString* clientaccount;

@end
