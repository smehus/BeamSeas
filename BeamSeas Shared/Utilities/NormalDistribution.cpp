//
//  NormalDistribution.cpp
//  BeamSeas
//
//  Created by Scott Mehus on 9/18/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

#include "NormalDistribution.hpp"

float NormalDistribution::generate_normal_random()
{
    return normal_dist(engine);
}
