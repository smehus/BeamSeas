//
//  NormalDistribution.cpp
//  BeamSeas
//
//  Created by Scott Mehus on 9/18/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

#include "NormalDistribution.hpp"
#include <vector>


NormalDistribution::NormalDistribution() { }

float NormalDistribution::generate_normal_random()
{
    return normal_dist(engine);
}

//cOcean ocean(64, 0.0005f, vector2(0.0f,32.0f), 64, false);

float NormalDistribution::phillips(float x, float y)
{

    vector2 k = vector2(x, y);
//    float N = 64;
//    float length = 64.0f;
//    float n_prime = x;
//    float m_prime = y;
//    vector2 k(M_PI * (2 * n_prime - N) / length, M_PI * (2 * m_prime - N) / length);
    float g = 9.81;
    float A = 0.0005f;
    vector2 w = vector2(0.0f,32.0f);
    float k_length  = k.length();
    if (k_length < 0.000001) return 0.0;

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


vector3::vector3() : x(0.0f), y(0.0f), z(0.0f) { }
vector3::vector3(float x, float y, float z) : x(x), y(y), z(z) { }

float vector3::operator*(const vector3& v) {
    return this->x*v.x + this->y*v.y + this->z*v.z;
}

vector3 vector3::cross(const vector3& v) {
    return vector3(this->y*v.z - this->z*v.y, this->z*v.x - this->x*v.z, this->x*v.y - this->y*v.z);
}

vector3 vector3::operator+(const vector3& v) {
    return vector3(this->x + v.x, this->y + v.y, this->z + v.z);
}

vector3 vector3::operator-(const vector3& v) {
    return vector3(this->x - v.x, this->y - v.y, this->z - v.z);
}

vector3 vector3::operator*(const float s) {
    return vector3(this->x*s, this->y*s, this->z*s);
}

vector3& vector3::operator=(const vector3& v) {
    this->x = v.x; this->y = v.y; this->z = v.z;
    return *this;
}

float vector3::length() {
    return sqrt(this->x*this->x + this->y*this->y + this->z*this->z);
}

vector3 vector3::unit() {
    float l = this->length();
    return vector3(this->x/l, this->y/l, this->z/l);
}



vector2::vector2() : x(0.0f), y(0.0f) { }
vector2::vector2(float x, float y) : x(x), y(y) { }

float vector2::operator*(const vector2& v) {
    return this->x*v.x + this->y*v.y;
}

vector2 vector2::operator+(const vector2& v) {
    return vector2(this->x + v.x, this->y + v.y);
}

vector2 vector2::operator-(const vector2& v) {
    return vector2(this->x - v.x, this->y - v.y);
}

vector2 vector2::operator*(const float s) {
    return vector2(this->x*s, this->y*s);
}

vector2& vector2::operator=(const vector2& v) {
    this->x = v.x; this->y = v.y;
    return *this;
}

float vector2::length() {
    return sqrt(this->x*this->x + this->y*this->y);
}

vector2 vector2::unit() {
    float l = this->length();
    return vector2(this->x/l, this->y/l);
}
