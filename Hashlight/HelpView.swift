import SwiftUI
import WebKit

struct HelpView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        HelpWebView()
            .frame(width: 760, height: 520)
            .navigationTitle("Hashlight Help")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            // Escape closes Help too (Done answers Return).
            .background {
                Button("Close Help") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
            }
    }
}

struct HelpWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.loadHTMLString(HelpHTML.content, baseURL: nil)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
