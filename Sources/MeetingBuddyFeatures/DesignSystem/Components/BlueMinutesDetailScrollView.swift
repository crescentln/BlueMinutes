import SwiftUI

struct BlueMinutesDetailScrollView<Content: View>: View {
    private let contentMaxWidth: CGFloat
    private let content: Content

    init(
        contentMaxWidth: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.contentMaxWidth = contentMaxWidth
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .frame(
                    maxWidth: contentMaxWidth,
                    alignment: .leading
                )
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }
}
