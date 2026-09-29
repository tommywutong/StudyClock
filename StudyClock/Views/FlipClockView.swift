import SwiftUI

struct FlipClockView: View {
    let seconds: TimeInterval
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(display.enumerated()), id: \.offset) { index, character in
                if character == ":" {
                    Text(":")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                } else {
                    Text(String(character))
                        .font(.system(size: 58, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(minWidth: 42)
                        .padding(.vertical, 10)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        .contentTransition(.numericText(value: seconds))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(display)
    }

    private var display: String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", total / 3_600, (total / 60) % 60, total % 60)
    }
}