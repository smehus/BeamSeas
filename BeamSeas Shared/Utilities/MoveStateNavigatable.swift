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
            guard player.moveStates.contains(.left) && !player.moveStates.contains(.right) else { return nil }
            guard !player.moveStates.contains(.forward) && !player.moveStates.contains(.backwards) else { return nil }
            
            print("\(player.forwardVector) fps \(fps)")
            self.rotation.z = player.rotation.y
            
            return nil
        }
    }
    
    func rightRule() -> MapRotationRule {
        return { player, fps in
            guard player.moveStates.contains(.right) && !player.moveStates.contains(.left) else { return nil }
            guard !player.moveStates.contains(.forward) && !player.moveStates.contains(.backwards) else { return nil }
            
            // use forward vector instead
            print("\(player.forwardVector) fps \(fps)")
            self.rotation.z = player.rotation.y
            
            return nil
        }
    }
    
    func forwardRule() -> MapRotationRule {
        return { player, fps in
            guard player.moveStates.contains(.forward) else { return nil }
            guard !player.moveStates.contains(.backwards) else { return nil }
            
            self.rotation.y += (fps * player.forwardVector.x)
            self.rotation.x -= (fps * player.forwardVector.z)
            
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
