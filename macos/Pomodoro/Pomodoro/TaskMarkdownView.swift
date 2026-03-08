import SwiftUI

struct TaskMarkdownView: View {
    let markdown: String

    var body: some View {
        if let rendered = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        ) {
            Text(rendered)
                .textSelection(.enabled)
        } else {
            Text(markdown)
                .textSelection(.enabled)
        }
    }
}
