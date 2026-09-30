import SwiftUI
import SidetoneCore

/// State badge + elapsed time + the latest status message.
struct HeaderView: View {
    @Environment(SidetoneModel.self) private var model

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: model.state.symbolName)
                .foregroundStyle(model.state.tint)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.state.label)
                    .font(.headline)

                if let status = model.status {
                    Text(status.text)
                        .font(.caption)
                        .foregroundStyle(status.kind == .error ? Color.red : Color.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(status.kind == .error ? "Error: \(status.text)" : status.text)
                }
            }

            Spacer(minLength: 8)

            if model.state != .idle {
                Text(Formatting.elapsed(model.elapsed))
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(model.state == .paused ? .secondary : .primary)
                    .monospacedDigit()
                    .accessibilityLabel("Elapsed \(Formatting.elapsed(model.elapsed))")
            }
        }
        .accessibilityElement(children: .contain)
    }
}
