//
//  Lights.swift
//  BeamSeas
//
//  Created by Scott Mehus on 6/17/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import Foundation

struct Lighting {
    // Lights
    let sunlight: Light = {
        var light = Lighting.buildDefaultLight()
        light.position = [-500, 5500, -500]
        light.intensity = 0.3
        light.type = Sunlight
        return light
    }()
    
    let spotlight: Light = {
        var light = Lighting.buildDefaultLight()
        light.position = [0, 0, 0]
        light.color = [1, 1, 0.7]
        light.attenuation = float3(2, 0, 0)
        light.type = Spotlight
        light.coneAngle = Float(30).degreesToRadians
        light.coneDirection = [0, 90, 0]
        light.coneAttenuation = 2
        light.type = Spotlight
        return light
    }()
    
    let ambientLight: Light = {
        var light = Lighting.buildDefaultLight()
        light.position = [0, 5200, 0]
        light.color = [Float(0.0 / 255.0), Float(105.0 / 255.0), Float(148.0 / 255.0)]
        light.type = Ambientlight
        light.intensity = 0.01
        return light
    }()
    let fillLight: Light = {
        var light = Lighting.buildDefaultLight()
        light.position = [0, 5200, 0]
        light.type = Ambientlight
        return light
    }()

    var lights: [Light]
    let count: UInt32

    init() {

        lights = [fillLight, sunlight]
        count = UInt32(lights.count)
    }

    static func buildDefaultLight() -> Light {
        var light = Light()
        light.position = [0, 0, 0]
        light.color = [1, 1, 1]
        light.specularColor = [1, 1, 1]
        light.intensity = 0.7
        light.type = Sunlight
        return light
    }
}
