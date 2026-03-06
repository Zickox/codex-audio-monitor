import SwiftUI

enum StatusChipAppearance {
    case subtle
    case emphasis
}

struct StatusChipView: View {
    let text: String
    let color: Color
    var appearance: StatusChipAppearance = .emphasis

    var body: some View {
        Text(text)
            .subtleGlassChipStyle(
                color: color,
                emphasis: appearance == .emphasis
            )
    }
}
