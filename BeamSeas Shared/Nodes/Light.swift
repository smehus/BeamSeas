//
//  Lights.swift
//  BeamSeas
//
//  Created by Scott Mehus on 6/17/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import Foundation

class Lights {

    static func buildDefaultLight() -> Light {
        var light = Light()
        light.position = [0, 0, 0]
        light.color = [1, 1, 1]
        light.specularColor = [0.6, 0.6, 0.6]
        light.intensity = 1
        light.attenuation = float3(1, 0, 0)
        light.type = .Sunlight
        return light
    }

    static var sunlight: Light = {
        var light = buildDefaultLight()
        light.position = [1, 2, -2]
        return light
    }()

    static var ambientLight: Light = {
        var light = buildDefaultLight()
        light.color = [0.5, 1, 0]
        light.intensity = 0.2
        light.type = .Ambientlight
        return light
    }()

    static var redLight: Light = {
        var light = buildDefaultLight()
        light.position = [-0, 0.5, -0.5]
        light.color = [1, 0, 0]
        light.attenuation = float3(1, 3, 4)
        light.type = .Pointlight
        return light
    }()
}
