import Foundation

/**
 Protocol for discrete distributions.
 
 Defines the `quantile()` method that must be implemented.
 */
public protocol DiscreteDistribution {
    func quantile(_ p: Double) -> Int
}

extension DiscreteDistribution {
    /**
     Single discrete random value using a user-provided random number generator
     
     - Parameters:
       - using: A random number generator
     
     - Returns:
     A random number from the distribution represented by the instance
     */
    public func random<T: RandomNumberGenerator>(using generator: inout T) -> Int {
        let x = Double.random(in: 0.0...1.0,
                              using: &generator)
        return quantile(x)
    }
    
    /**
     Single discrete random value using the system random number generator
     
     - Returns:
     A random number from the distribution represented by the instance
     */
    public func random() -> Int {
        var rng = SystemRandomNumberGenerator()
        return random(using: &rng)
    }
    
    /**
     Array of discrete random values
     - Parameter n: number of values to produce
     - Complexity: O(n)
     */
    public func random(_ n: Int) -> [Int] {
        var results: [Int] = []
        for _ in 0..<n {
            results.append(random())
        }
        return results
    }

}

/**
 Protocol for continuous distributions.
 
 Defines the `quantile()` method that must be implemented.
 */
public protocol ContinuousDistribution {
    func quantile(_ p: Double) -> Double
}

extension ContinuousDistribution {
    /**
     Single discrete random value using a user-provided random number generator
     
     - Parameters:
       - using: A random number generator
     
     - Returns:
     A random number from the distribution represented by the instance
     */
    public func random<T: RandomNumberGenerator>(using generator: inout T) -> Double {
        let x = Double.random(in: 0.0...1.0,
                              using: &generator)
        return quantile(x)
    }
    
    
    /**
     Single discrete random value using the system random number generator
     
     - Returns:
     A random number from the distribution represented by the instance
     */
    public func random() -> Double {
        var rng = SystemRandomNumberGenerator()
        return random(using: &rng)
    }
    
    
    /**
     Array of discrete random values
     - Parameter n: number of values to produce
     - Complexity: O(n)
     */
    public func random(_ n: Int) -> [Double] {
        var results: [Double] = []
        for _ in 0..<n {
            results.append(random())
        }
        return results
    }

}


public struct Distributions {
    private static let pi = Double.pi

    public class Normal: ContinuousDistribution {
        // mean and variance
        var m: Double
        var v: Double

        public init(m: Double, v: Double) {
            self.m = m
            self.v = v
        }
        
        public convenience init(mean: Double, sd: Double) {
            // This contructor takes the mean and standard deviation, which is the more
            // common parameterisation of a normal distribution.
            let variance = pow(sd, 2)
            self.init(m: mean, v: variance)
        }

        public convenience init?(data: [Double]) {
            // this calculates the mean twice, since variance()
            // uses the mean and calls mean()
            guard let v = Common.variance(data) else {
                return nil
            }
            guard let m = Common.mean(data) else {
                return nil // This shouldn't ever occur
            }
            self.init(m: m, v: v)
        }

        public func pdf(_ x: Double) -> Double {
            return (1/pow(self.v*2*pi,0.5))*exp(-pow(x-self.m,2)/(2*self.v))
        }

        public func cdf(_ x: Double) -> Double {
            return (1 + erf((x-self.m)/pow(2*self.v,0.5)))/2
        }

        public func quantile(_ p: Double) -> Double {
            return self.m + pow(self.v*2,0.5)*Common.erfinv(2*p - 1)
        }
    }
}
