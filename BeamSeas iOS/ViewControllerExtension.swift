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
extension ViewController {
    static var previousScale: CGFloat = 1

    func addGestureRecognizers(to view: UIView) {
        let pan = UIPanGestureRecognizer(target: self,
                                         action: #selector(handlePan(gesture:)))
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self,
                                             action: #selector(handlePinch(gesture:)))
        view.addGestureRecognizer(pinch)
        
        let hold = UILongPressGestureRecognizer(target: self,
                                                action: #selector(handleHold(gesture:)))
        view.addGestureRecognizer(hold)
    }

    @objc func handleHold(gesture: UILongPressGestureRecognizer) {
        renderer?.player.moveState = .forward
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
