//
//  NormalDistributionBridge.h
//  BeamSeas
//
//  Created by Scott Mehus on 9/18/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

#import <Foundation/Foundation.h>
//#import "NormalDistribution.hpp"
#import <simd/SIMD.h>
#import "ShaderTypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface NormalDistributionBridge : NSObject
- (instancetype)init;
- (float)getRandomNormal;
- (float)phillips:(float)x y:(float)y g:(float)g A:(float)A dir:(simd_float2)dir;
- (float)gausRandom;
- (vector_float2)gausNoEngine;

@end

NS_ASSUME_NONNULL_END
