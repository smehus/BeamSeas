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
    var cameraController: CameraController!

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

//        addGestureRecognizers(to: mtkView)

        cameraController = CameraController()
        renderer.viewMatrix = cameraController.viewMatrix
    }


    #if os(iOS)
        var trackedTouch: UITouch?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            if trackedTouch == nil {
                if let newlyTrackedTouch = touches.first {
                    trackedTouch = newlyTrackedTouch
                    let point = newlyTrackedTouch.location(in: view)
                    cameraController.startedInteraction(at: point)
                }
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            if let previouslyTrackedTouch = trackedTouch {
                if touches.contains(previouslyTrackedTouch) {
                    let point = previouslyTrackedTouch.location(in: view)
                    cameraController.dragged(to: point)
                    renderer.viewMatrix = cameraController.viewMatrix
                }
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            if let previouslyTrackedTouch = trackedTouch {
                if touches.contains(previouslyTrackedTouch) {
                    self.trackedTouch = nil
                }
            }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            if let previouslyTrackedTouch = trackedTouch {
                if touches.contains(previouslyTrackedTouch) {
                    self.trackedTouch = nil
                }
            }
        }
    #elseif os(macOS)
        override func mouseDown(with event: NSEvent) {
            var point = view.convert(event.locationInWindow, from: nil)
            point.y = view.bounds.size.height - point.y
            cameraController.startedInteraction(at: point)
        }

        override func mouseDragged(with event: NSEvent) {
            var point = view.convert(event.locationInWindow, from: nil)
            point.y = view.bounds.size.height - point.y
            cameraController.dragged(to: point)
            renderer.viewMatrix = cameraController.viewMatrix
        }
    #endif
}
