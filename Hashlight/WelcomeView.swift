import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var documentManager: DocumentManager
    @ObservedObject private var dockIcon = DockIconController.shared
    @State private var showIcon = false
    @State private var showSubtitle = false
    @State private var showButton = false
    @State private var showHint = false
    @State private var showRecents = false
    @State private var iconBounce = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(nsImage: dockIcon.image)
                .resizable()
                .frame(width: 96, height: 96)
                .scaleEffect(iconBounce ? 1.0 : 0.5)
                .opacity(showIcon ? 1 : 0)
                .padding(.bottom, 16)

            Text("Markdown Viewer")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .opacity(showSubtitle ? 1 : 0)
                .offset(y: showSubtitle ? 0 : 8)

            Button(action: documentManager.openFile) {
                Label("Open File", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .opacity(showButton ? 1 : 0)
            .offset(y: showButton ? 0 : 8)
            .padding(.top, 24)

            HStack(spacing: 4) {
                Text("or press")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                Text("⌘O")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
            }
            .opacity(showHint ? 1 : 0)
            .padding(.top, 12)

            if !documentManager.recentFileURLs.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Recent Files")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Clear") {
                            withAnimation(Motion.entranceMovement) {
                                documentManager.clearRecentFiles()
                            }
                        }
                        .buttonStyle(.link)
                        .font(.subheadline)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)

                    ForEach(documentManager.recentFileURLs.prefix(5), id: \.path) { url in
                        RecentFileRow(url: url) {
                            documentManager.loadDocument(from: url)
                        }
                    }
                }
                .frame(width: 320)
                .padding(.top, 28)
                .opacity(showRecents ? 1 : 0)
                .offset(y: showRecents ? 0 : 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
        .onAppear(perform: animateEntrance)
    }

    private func animateEntrance() {
        // Under Reduce Motion, skip the stagger: one gentle grouped fade.
        if Motion.reduceMotion {
            withAnimation(Motion.entrance) {
                showIcon = true
                iconBounce = true
                showSubtitle = true
                showButton = true
                showHint = true
                showRecents = true
            }
            return
        }
        // v2.8.1 feel-checked entrance (plan 023): 60ms stagger steps, last element
        // ~630ms, icon settling with a slight, dignified overshoot. Plan 009/010's
        // faster retiming was reviewed and REJECTED — owner kept the original feel.
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            showIcon = true
            iconBounce = true
        }
        withAnimation(.easeOut(duration: 0.35).delay(0.10)) {
            showSubtitle = true
        }
        withAnimation(.easeOut(duration: 0.35).delay(0.16)) {
            showButton = true
        }
        withAnimation(.easeOut(duration: 0.35).delay(0.22)) {
            showHint = true
        }
        withAnimation(.easeOut(duration: 0.35).delay(0.28)) {
            showRecents = true
        }
    }
}

/// One recent file: a plain button whose only hover feedback is a quiet background.
private struct RecentFileRow: View {
    let url: URL
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.lastPathComponent)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(url.deletingLastPathComponent().path)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(url.path)
    }
}
