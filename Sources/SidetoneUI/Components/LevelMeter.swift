import SwiftUI

/// A labelled horizontal level bar. `level` is 0…1.
struct LevelMeter: View {
    let label: String
    /// What the bar measures, for VoiceOver.
    let source: String
    let level: Float

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Text(label)
                .font(DS.Typo.secondary)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)

            GeometryReader { geo in
                let clamped = CGFloat(max(0, min(1, level)))
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Palette.track)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(4, geo.size.width * clamped))
                        .animation(.linear(duration: 0.08), value: clamped)
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(source) level")
        .accessibilityValue("\(Int((max(0, min(1, level)) * 100).rounded())) percent")
    }
}
