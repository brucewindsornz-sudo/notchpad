// Port of drawSampleFlight in Sources/FlightEffects.swift (the Classic glide, used by placeholder renderers):
// the pad glides from `from` to `to` on a sideways bow, cross-fading the floating card into the docked pad.
export const kind = 'flight';
export const duration = 0.9;    // as the placeholder renderers in Sources/Flight*.swift (GateFlight etc.)

export function draw(f, ctx) {
  const bowScale = 1;
  const t = smoothstep(0, 1, f.t);
  const bow = Math.sin(Math.PI * t) * Math.min(100, f.distance * 0.25) * bowScale;
  const x = lerp(f.from.minX, f.to.minX, t) + bow;
  const y = lerp(f.from.minY, f.to.minY, t);
  const w = lerp(f.from.width, f.to.width, t);
  const h = lerp(f.from.height, f.to.height, t);
  const rect = new CGRect(x, y, w, h);
  f.drawFrom(ctx, rect, 1 - t);
  f.drawTo(ctx, rect, t);
}
