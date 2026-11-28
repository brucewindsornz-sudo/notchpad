import SwiftUI

// Placeholder until the Stargate jump effect is ready.
struct GateFlight: FlightEffectRenderer {
    let duration: Double = 0.9
    func draw(_ f: FlightFrame, _ ctx: GraphicsContext) { drawSampleFlight(f, ctx) }
}
