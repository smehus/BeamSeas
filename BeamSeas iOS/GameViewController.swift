//
//  GameViewController.swift
//  BeamSeas iOS
//
//  Created by Scott Mehus on 6/15/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import UIKit
import MetalKit

// Our iOS specific view controller
class GameViewController: UIViewController {

    var renderer: Renderer!
    var mtkView: MTKView!

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = self.view as? MTKView else {
            print("View of Gameview controller is not an MTKView")
            return
        }

        // Select the device to render with.  We choose the default device
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported")
            return
        }

        mtkView.device = defaultDevice
        mtkView.backgroundColor = UIColor.black

        guard let newRenderer = Renderer(metalKitView: mtkView) else {
            print("Renderer cannot be initialized")
            return
        }

        renderer = newRenderer

        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)

        mtkView.delegate = renderer
    }
}

extension GameViewController {
    static var previousScale: CGFloat = 1

    func addGestureRecognizers(to view: UIView) {
        let pan = UIPanGestureRecognizer(target: self,
                                         action: #selector(handlePan(gesture:)))
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self,
                                             action: #selector(handlePinch(gesture:)))
        view.addGestureRecognizer(pinch)
    }

    @objc func handlePan(gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: gesture.view)
        let delta = float2(Float(translation.x),
                           Float(-translation.y))

        renderer?.camera.rotate(delta: delta)
        gesture.setTranslation(.zero, in: gesture.view)
    }

    @objc func handlePinch(gesture: UIPinchGestureRecognizer) {
        let sensitivity: Float = 3
        let delta = Float(gesture.scale - ViewController.previousScale) * sensitivity
        renderer?.camera.zoom(delta: delta)
        ViewController.previousScale = gesture.scale
        if gesture.state == .ended {
            ViewController.previousScale = 1
        }
    }
}
