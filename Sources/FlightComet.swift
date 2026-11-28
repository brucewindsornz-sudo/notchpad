import SwiftUI

// Placeholder until the Comet effect is ready.
struct CometFlight: FlightEffectRenderer {
    let duration: Double = 0.9
    func draw(_ f: FlightFrame, _ ctx: GraphicsContext) { drawSampleFlight(f, ctx) }
}
