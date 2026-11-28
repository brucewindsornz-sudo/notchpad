import SwiftUI

// Placeholder until the Warp jump effect is ready.
struct WarpFlight: FlightEffectRenderer {
    let duration: Double = 0.9
    func draw(_ f: FlightFrame, _ ctx: GraphicsContext) { drawSampleFlight(f, ctx) }
}
