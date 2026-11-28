import SwiftUI

// Placeholder until the Swarm effect is ready.
struct SwarmFlight: FlightEffectRenderer {
    let duration: Double = 0.9
    func draw(_ f: FlightFrame, _ ctx: GraphicsContext) { drawSampleFlight(f, ctx) }
}
