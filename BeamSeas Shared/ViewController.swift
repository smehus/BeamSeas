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

protocol GameViewProtocol: class {
    func keyDown()
    func keyUp()
}

class ViewController: LocalViewController {

    var renderer: Renderer!

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
    func keyUp() {
        renderer.deltaFactor = .normal
    }

    func keyDown() {
        renderer.deltaFactor = .forward
    }
}
