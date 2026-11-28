import SwiftUI

// Placeholder until the Boomerang effect is ready.
struct BoomerangFlight: FlightEffectRenderer {
    let duration: Double = 0.9
    func draw(_ f: FlightFrame, _ ctx: GraphicsContext) { drawSampleFlight(f, ctx) }
}
