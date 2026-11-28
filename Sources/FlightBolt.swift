import SwiftUI

// Placeholder until the Lightning arc effect is ready.
struct BoltFlight: FlightEffectRenderer {
    let duration: Double = 0.9
    func draw(_ f: FlightFrame, _ ctx: GraphicsContext) { drawSampleFlight(f, ctx) }
}
