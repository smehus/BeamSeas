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

@end
