//
//  NormalDistributionBridge.h
//  BeamSeas
//
//  Created by Scott Mehus on 9/18/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

#import <Foundation/Foundation.h>
//#import "NormalDistribution.hpp"

NS_ASSUME_NONNULL_BEGIN

@interface NormalDistributionBridge : NSObject
- (instancetype)init;
- (float)getRandomNormal;
- (float)phillips:(float)x y:(float)y;

@end

NS_ASSUME_NONNULL_END
