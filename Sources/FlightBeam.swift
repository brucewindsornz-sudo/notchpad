import SwiftUI

// Placeholder until the Transporter beam effect is ready.
struct BeamFlight: FlightEffectRenderer {
    let duration: Double = 0.9
    func draw(_ f: FlightFrame, _ ctx: GraphicsContext) { drawSampleFlight(f, ctx) }
}
