//
//  NormalDistribution.hpp
//  BeamSeas
//
//  Created by Scott Mehus on 9/18/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

#ifndef NormalDistribution_hpp
#define NormalDistribution_hpp

#include <stdio.h>
#define FFT_FP16 1


//#include "vector_math.h"
#include <complex>
#include <random>
#include <vector>
#include <memory>
//#include "glfft.hpp"
//#include "common.hpp"

using namespace std;

class NormalDistribution
{

public:
    NormalDistribution();
    NormalDistribution(const std::string &title);
    ~NormalDistribution();

public:
    std::normal_distribution<float> normal_dist{0.0f, 1.0f};
    std::default_random_engine engine;
    float generate_normal_random();

private:
    std::string m_title;
};


#endif /* NormalDistribution_hpp */
