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
        light.position = [20, 10, 0]
        return light
    }()
    let ambientLight: Light = {
        var light = Lighting.buildDefaultLight()
        light.color = [1, 1, 1]
        light.intensity = 0.2
        light.type = Ambientlight
        return light
    }()
    let fillLight: Light = {
        var light = Lighting.buildDefaultLight()
        light.position = [2, 10, 0]
        light.specularColor = [0.3, 0.3, 0.3]
        light.color = [0.3, 0.3, 0.3]
        return light
    }()

    let lights: [Light]
    let count: UInt32

    init() {
        lights = [sunlight, fillLight]
        count = UInt32(lights.count)
    }

    static func buildDefaultLight() -> Light {
        var light = Light()
        light.position = [0, 0, 0]
        light.color = [1, 1, 1]
        light.specularColor = [1, 1, 1]
        light.intensity = 1.0
        light.attenuation = float3(0.2, 0, 0)
        light.type = Sunlight
        return light
    }
}
