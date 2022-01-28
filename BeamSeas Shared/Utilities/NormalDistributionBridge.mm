//
//  NormalDistributionBridge.m
//  BeamSeas
//
//  Created by Scott Mehus on 9/18/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

#import "NormalDistributionBridge.h"
#include "NormalDistribution.hpp"
#import <Foundation/Foundation.h>

@interface NormalDistributionBridge ()

@property NormalDistribution *dist;
@end

@implementation NormalDistributionBridge

-(instancetype)init
{
    if (self = [super init]) {
        self.dist = new NormalDistribution();
    }

    return self;
}

-(float)getRandomNormal
{
    return self.dist->generate_normal_random();
}

- (float)gausRandom
{

    return self.dist->generate_normal_random();
}

-(vector_float2)gausNoEngine
{
    return self.dist->gaussianRandomVariable();
}

//cOcean ocean(64, 0.0005f, vector2(0.0f,32.0f), 64, false);


- (float)phillips:(float)x y:(float)y g:(float)g A:(float)A dir:(simd_float2)dir
{
    return self.dist->phillips(x, y, g, A, dir);
}




@end
