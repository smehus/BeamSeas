//
//  DepthStencilStateBuilder.swift
//  BeamSeas
//
//  Created by Scott Mehus on 7/25/21.
//  Copyright © 2021 Scott Mehus. All rights reserved.
//

import MetalKit

protocol DepthStencilStateBuilder {
    static func buildDepthStencilState() -> MTLDepthStencilState
}

extension DepthStencilStateBuilder {
    static func buildDepthStencilState() -> MTLDepthStencilState {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .always
        descriptor.isDepthWriteEnabled = true

        return Renderer.device.makeDepthStencilState(descriptor: descriptor)!
    }
}


