//
//  NormalDistribution.cpp
//  BeamSeas
//
//  Created by Scott Mehus on 9/18/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

#include "NormalDistribution.hpp"
#include <vector>
#include <simd/SIMD.h>


NormalDistribution::NormalDistribution() { }

float NormalDistribution::generate_normal_random()
{
    return normal_dist(engine);
}

//cOcean ocean(64, 0.0005f, svector2(0.0f,32.0f), 64, false);

float NormalDistribution::phillips(float x, float y)
{

    svector2 k = svector2(x, y);
//    float N = 64;
//    float length = 64.0f;
//    float n_prime = x;
//    float m_prime = y;
//    svector2 k(M_PI * (2 * n_prime - N) / length, M_PI * (2 * m_prime - N) / length);
    float g = 9.81;
    float A = 300.0f;
    svector2 w = svector2(22.0f, -26.0f);
    float k_length  = k.length();
    if (k_length < 0.0000000000001) return 0.0;

    float k_length2 = k_length  * k_length;
    float k_length4 = k_length2 * k_length2;

    float k_dot_w   = k.unit() * w.unit();
    float k_dot_w2  = k_dot_w * k_dot_w;

    float w_length  = w.length();
    float L         = w_length * w_length / g;
    float L2        = L * L;

    float damping   = 0.001;
    float l2        = L2 * damping * damping;

    return A * exp(-1.0f / (k_length2 * L2)) / k_length4 * k_dot_w2 * exp(-k_length2 * l2);
}


svector2::svector2() : x(0.0f), y(0.0f) { }
svector2::svector2(float x, float y) : x(x), y(y) { }

float svector2::operator*(const svector2& v) {
    return this->x*v.x + this->y*v.y;
}

svector2 svector2::operator+(const svector2& v) {
    return svector2(this->x + v.x, this->y + v.y);
}

svector2 svector2::operator-(const svector2& v) {
    return svector2(this->x - v.x, this->y - v.y);
}

svector2 svector2::operator*(const float s) {
    return svector2(this->x*s, this->y*s);
}

svector2& svector2::operator=(const svector2& v) {
    this->x = v.x; this->y = v.y;
    return *this;
}

float svector2::length() {
    return sqrt(this->x*this->x + this->y*this->y);
}

svector2 svector2::unit() {
    float l = this->length();
    return svector2(this->x/l, this->y/l);
}

float uniformRandomVariable() {
    return (float)rand()/RAND_MAX;
}

vector_float2 NormalDistribution::gaussianRandomVariable() {
    float x1, x2, w;
    do {
        x1 = 2.f * uniformRandomVariable() - 1.f;
        x2 = 2.f * uniformRandomVariable() - 1.f;
        w = x1 * x1 + x2 * x2;
    } while ( w >= 1.f );
    w = sqrt((-2.f * log(w)) / w);
    return vector2(x1 * w, x2 * w);
}
