//
//  NormalDistributionBridge.h
//  BeamSeas
//
//  Created by Scott Mehus on 9/18/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NormalDistributionBridge : NSObject
- (instancetype)init;
- (float)getRandomNormal;
//- (void)phillips:(vector2)k;

@end

NS_ASSUME_NONNULL_END
