import SwiftUI
import SidetoneCore

/// The panel's one rich moment: a two-channel scope.
///
/// The desktop channel rides above the centre line (amber, "Them / L") and the mic below
/// (off-white, "You / R"), newest sample at the right edge. It is always visible — flat and quiet
/// when idle, alive while recording — so the panel never jumps when a take starts.
struct WaveformStrip: View {
    let data: WaveformData
    let active: Bool
    var micEnabled: Bool = true

    var body: some View {
        Canvas { context, size in
            let mid = size.height / 2
            let step = size.width / CGFloat(max(1, WaveformData.capacity - 1))
            let amplitude = mid - 3

            // Centre line: the stereo split, drawn as the quietest possible rule.
            var centre = Path()
            centre.move(to: CGPoint(x: 0, y: mid))
            centre.addLine(to: CGPoint(x: size.width, y: mid))
            context.stroke(centre, with: .color(DS.Palette.hairlineStrong), lineWidth: 1)

            // Faint ruler ticks make the empty state read as an instrument, not dead space.
            var ticks = Path()
            let tickStep = size.width / 8
            for index in 1..<8 {
                let x = CGFloat(index) * tickStep
                ticks.move(to: CGPoint(x: x, y: mid - 2))
                ticks.addLine(to: CGPoint(x: x, y: mid + 2))
            }
            context.stroke(ticks, with: .color(DS.Palette.hairline), lineWidth: 1)

            if !active {
                let label = DS.Typo.mono
                context.draw(Text("THEM").font(label).foregroundStyle(DS.Palette.textMuted),
                             at: CGPoint(x: 2, y: 8), anchor: .leading)
                if micEnabled {
                    context.draw(Text("YOU").font(label).foregroundStyle(DS.Palette.textMuted),
                                 at: CGPoint(x: 2, y: size.height - 8), anchor: .leading)
                }
            }

            draw(data.desktop, above: true, colour: DS.Palette.accent,
                 context: &context, size: size, mid: mid, step: step, amplitude: amplitude)
            if micEnabled {
                draw(data.mic, above: false, colour: DS.Palette.textPrimary.opacity(0.7),
                     context: &context, size: size, mid: mid, step: step, amplitude: amplitude)
            }
        }
        .frame(height: 52)
        .opacity(active || !data.isEmpty ? 1 : 0.55)
        .accessibilityHidden(true)
    }

    private func draw(
        _ samples: [Float],
        above: Bool,
        colour: Color,
        context: inout GraphicsContext,
        size: CGSize,
        mid: CGFloat,
        step: CGFloat,
        amplitude: CGFloat
    ) {
        guard samples.count > 1 else { return }

        // Anchor the newest sample at the right edge; older ones scroll left.
        let start = WaveformData.capacity - samples.count
        var line = Path()
        var area = Path()
        area.move(to: CGPoint(x: CGFloat(start) * step, y: mid))

        for (index, sample) in samples.enumerated() {
            let x = CGFloat(start + index) * step
            let level = CGFloat(max(0, min(1, sample)))
            // A gentle floor keeps quiet passages visible as a hairline rather than nothing.
            let height = max(0.5, level * amplitude)
            let y = above ? mid - height : mid + height
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                line.move(to: point)
            } else {
                line.addLine(to: point)
            }
            area.addLine(to: point)
        }

        area.addLine(to: CGPoint(x: CGFloat(start + samples.count - 1) * step, y: mid))
        area.closeSubpath()

        context.fill(area, with: .color(colour.opacity(above ? 0.16 : 0.10)))
        context.stroke(line, with: .color(colour), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }
}
