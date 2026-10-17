import SwiftUI
import DesignSystem

/// The open-source notices the LGPL requires us to ship (docs/licenses.md, bundled).
struct LicensesView: View {
    /// One entry per paragraph: tvOS scrolls by moving focus, so each paragraph is focusable there.
    private let paragraphs: [AttributedString] = {
        guard let url = Bundle.main.url(forResource: "licenses", withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return markdown.components(separatedBy: "\n\n").filter { !$0.isEmpty }.map { paragraph in
            (try? AttributedString(markdown: paragraph, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(paragraph)
        }
    }()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text("This app includes mpv and FFmpeg under the GNU Lesser General Public License, in a separate, replaceable framework. The exact source code, including any modifications, is available on request from the developer and from the projects listed below.")
                    .font(.callout)
                ForEach(paragraphs.indices, id: \.self) { index in
                    Text(paragraphs[index]).font(.footnote.monospaced()).selectableText()
                        #if os(tvOS)
                        .focusable()
                        #endif
                }
            }
            .padding()
        }
        .navigationTitle(Text("Open-Source Licences"))
    }
}

extension Bundle {
    /// "0.1.0 (1)"
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
