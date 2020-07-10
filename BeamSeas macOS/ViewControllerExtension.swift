//
//  GameViewController.swift
//  BeamSeas macOS
//
//  Created by Scott Mehus on 6/15/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import Cocoa
import MetalKit

// Our macOS specific view controller

extension ViewController {
    func addGestureRecognizers(to view: NSView) {
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(gesture:)))
        view.addGestureRecognizer(pan)
    }

    @objc func handlePan(gesture: NSPanGestureRecognizer) {
//        let translation = gesture.translation(in: gesture.view)
//        let delta = float2(Float(translation.x),
//                           Float(translation.y))
//
//        renderer.camera.rotate(delta: delta)
//        gesture.setTranslation(.zero, in: gesture.view)
    }

    override func scrollWheel(with event: NSEvent) {
//        renderer.camera.zoom(delta: Float(event.deltaY))
    }
}
