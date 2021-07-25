//
//  MoveStateNavigatable.swift
//  BeamSeas
//
//  Created by Scott Mehus on 7/25/21.
//  Copyright © 2021 Scott Mehus. All rights reserved.
//

import Foundation

protocol MoveStateNavigatable {
    typealias MapRotationRule = (Model, Float) -> SIMD3<Float>?
}

extension MoveStateNavigatable where Self: Node {
    func leftRule() -> MapRotationRule {
        return { player, fps in
            let states = player.moveStates

            guard states.contains(.left) && !states.contains(.right) else { return nil }
            guard !states.contains(.forward) && !states.contains(.backwards) else { return nil }
            
            let diff = player.rotation.y - self.rotation.z
            // This speeds up??
            
            print("current \(self.rotation.x) player: \(player.rotation.y) diff: \(diff)")
            self.rotation.z = -diff
            
            return nil
        }
    }
    
    func rightRule() -> MapRotationRule {
        return { player, fps in
            let states = player.moveStates
            
            guard states.contains(.right) && !states.contains(.left) else { return nil }
            guard !states.contains(.forward) && !states.contains(.backwards) else { return nil }
            
            let diff = player.rotation.y - self.rotation.z
            // This speeds up??
            
            print("current \(self.rotation.x) player: \(player.rotation.y) diff: \(diff)")
            self.rotation.z = diff
            
            return nil
        }
    }
    
    func forwardRule() -> MapRotationRule {
        return { player, fps in
            guard player.moveStates.contains(.forward) else { return nil }
            guard !player.moveStates.contains(.backwards) else { return nil }
            
//            self.rotation.y += (fps * player.forwardVector.x)
//            self.rotation.x -= (fps * player.forwardVector.z)
            
            return nil
        }
    }
    
    func backwardRule() -> MapRotationRule {
        return { player, fps in
            guard player.moveStates.contains(.backwards) else { return nil }
            guard !player.moveStates.contains(.forward) else { return nil }
            
            self.rotation.y -= (fps * player.forwardVector.x)
            self.rotation.x += (fps * player.forwardVector.z)
            
            return nil
        }
    }

}
