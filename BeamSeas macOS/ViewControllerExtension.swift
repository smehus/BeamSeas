//
//  GameViewController.swift
//  BeamSeas macOS
//
//  Created by Scott Mehus on 6/15/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import Cocoa
import MetalKit

enum Key: String {
    case forward = "w"
    case backwards = "s"
    case left = "a"
    case right = "d"
    
    var moveState: ModelMoveState {
        switch self {
        case .forward: return .forward
        case .backwards: return .backwards
        case .left: return .rotateLeft
        case .right: return .rotateRight
        }
    }
}

// Our macOS specific view controller

class GameView: MTKView, GameViewParent {

    weak var inputDelegate: GameViewProtocol?

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard let key = Key(rawValue: event.charactersIgnoringModifiers!) else { return }
        
        inputDelegate?.keyDown(key: key)
    }

    override func keyUp(with event: NSEvent) {
        guard let key = Key(rawValue: event.charactersIgnoringModifiers!) else { return }
        
        inputDelegate?.keyUp(key: key)
    }
}

extension ViewController {
    func addGestureRecognizers(to view: NSView) {
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(gesture:)))
        view.addGestureRecognizer(pan)
    }

    @objc func handlePan(gesture: NSPanGestureRecognizer) {
        let translation = gesture.translation(in: gesture.view)
        let delta = float2(Float(translation.x),
                           Float(translation.y))

        renderer.camera.rotate(delta: delta)
        gesture.setTranslation(.zero, in: gesture.view)
    }

    override func scrollWheel(with event: NSEvent) {
        renderer.camera.zoom(delta: Float(event.deltaY))
    }

}
