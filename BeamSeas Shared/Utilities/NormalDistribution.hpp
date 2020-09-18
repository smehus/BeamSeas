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

class vector3
{
  public:
    float x, y, z;
    vector3();
    vector3(float x, float y, float z);
    float operator*(const vector3& v);
    vector3 cross(const vector3& v);
    vector3 operator+(const vector3& v);
    vector3 operator-(const vector3& v);
    vector3 operator*(const float s);
    vector3& operator=(const vector3& v);
    float length();
    vector3 unit();
};

class vector2
{
  public:
    float x, y;
    vector2();
    vector2(float x, float y);
    float operator*(const vector2& v);
    vector2 operator+(const vector2& v);
    vector2 operator-(const vector2& v);
    vector2 operator*(const float s);
    vector2& operator=(const vector2& v);
    float length();
    vector2 unit();
};

class NormalDistribution
{

public:
    NormalDistribution();

public:
    std::normal_distribution<float> normal_dist{0.0f, 1.0f};
    std::default_random_engine engine;
    float phillips(float x, float y);
    float generate_normal_random();

private:
    std::string m_title;
};



#endif /* NormalDistribution_hpp */
