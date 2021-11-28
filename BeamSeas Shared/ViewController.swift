//
//  ViewController.swift
//  BeamSeas
//
//  Created by Scott Mehus on 6/17/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import Foundation
import MetalKit

protocol GameViewParent {
    var inputDelegate: GameViewProtocol? { get set }
}

protocol GameViewProtocol: AnyObject {
    var keys: Set<Key> { get set }
    func keyDown(key: Key)
    func keyUp(key: Key)
}

class ViewController: LocalViewController {

    var renderer: Renderer!
    var keys: Set<Key> = []

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let metalView = view as? MTKView else { fatalError("metal view not set up in storyboard") }
        
        renderer = Renderer(metalView: metalView)
        addGestureRecognizers(to: metalView)

        if var gameView = metalView as? GameViewParent {
            gameView.inputDelegate = self
        }
    }
}

extension ViewController: GameViewProtocol {
    func keyDown(key: Key) {
        
        keys.add(key: key)
        renderer.didUpdate(keys: keys)
        
        switch key {
            
            // Camera \\
        case .i:
//            (renderer.camera as! ThirdPersonCamera).focusDistance -= 1
            renderer.camera.rotation.x = Float(Float(renderer.camera.rotation.x).radiansToDegrees - 2).degreesToRadians
        case .p:
//            (renderer.camera as! ThirdPersonCamera).focusDistance += 1
            renderer.camera.rotation.x = Float(Float(renderer.camera.rotation.x).radiansToDegrees + 2).degreesToRadians
        case .j:
//            (renderer.camera as! ThirdPersonCamera).focusHeight -= 1
            renderer.camera.position.y -= 2
        break
        case .l:
//            (renderer.camera as! ThirdPersonCamera).focusHeight += 1
            renderer.camera.position.y += 2
        default: break
        }
    }

    func keyUp(key: Key) {
        keys.remove(key)

        renderer.player.moveStates = keys
    }
}

extension Set where Element == Key {
    mutating func add(key: Element) {
        switch key {
        case .forward:
            if contains(.backwards) {
                remove(.backwards)
            }
            
            insert(key)
        case .backwards:
            remove(.forward)
            insert(.backwards)
        case .right:
            remove(.left)
            insert(.right)
        case .left:
            remove(.right)
            insert(.left)
        default:
            insert(key)
        }
    }
}
