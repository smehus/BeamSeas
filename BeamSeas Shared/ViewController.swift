//
//  ViewController.swift
//  BeamSeas
//
//  Created by Scott Mehus on 6/17/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import Foundation
import MetalKit
import Metal

class ViewController: LocalViewController {

    var renderer: Renderer!

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let mtkView = view as? MTKView else { fatalError("metal view not set up in storyboard") }
        
        let device = MTLCreateSystemDefaultDevice()!
        mtkView.device = device
        mtkView.clearColor = MTLClearColorMake(0.3, 0.3, 0.3, 1.0)
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.sampleCount = 4

        renderer = Renderer(view: mtkView, device: device)
        mtkView.delegate = renderer

        addGestureRecognizers(to: mtkView)
    }
}
