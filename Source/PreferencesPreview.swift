#if DEBUG && canImport(SwiftUI)
import SwiftUI

// Edit makePreferencesContent() in main.swift to change both Canvas and the app.
// The coordinator keeps AppKit's weak table delegate/data source alive.
private struct PreferencesCanvas: NSViewRepresentable {
    let page: Int

    func makeCoordinator() -> AppDelegate { AppDelegate() }

    func makeNSView(context: Context) -> NSView {
        let controller = context.coordinator
        controller.loadBindings()
        controller.selectedPage = page
        return controller.makePreferencesContent()
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.selectPage(page)
    }
}

// Canvas cannot display an NSWindow's native title bar or toolbar. This shell
// represents that chrome; the content below remains the app's actual AppKit UI.
private struct PreferencesWindowPreview: View {
    let page: Int

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Preferences")
                    .font(.system(size: 16, weight: .semibold))
                HStack(spacing: 8) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill([Color.red, Color.yellow, Color.green][index])
                            .frame(width: 12, height: 12)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
            }
            .frame(height: 34)
            HStack(spacing: 12) {
                ForEach(AppDelegate.preferenceTabs.indices, id: \.self) { index in
                    let tab = AppDelegate.preferenceTabs[index]
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 25, weight: .regular))
                            .frame(height: 29)
                        Text(tab.title).font(.system(size: 13))
                    }
                    .foregroundColor(index == page ? .accentColor : .primary)
                    .frame(width: 80, height: 64)
                    .background(index == page ? Color.primary.opacity(0.06) : Color.clear)
                    .cornerRadius(8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
            PreferencesCanvas(page: page)
                .frame(width: AppDelegate.preferenceSize.width, height: AppDelegate.preferenceSize.height)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct PreferencesPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            PreferencesWindowPreview(page: 0).previewDisplayName("General")
            PreferencesWindowPreview(page: 1).previewDisplayName("App List")
            PreferencesWindowPreview(page: 2).previewDisplayName("Folders")
            PreferencesWindowPreview(page: 3).previewDisplayName("About")
        }
        .frame(width: AppDelegate.preferenceSize.width, height: AppDelegate.preferenceSize.height + 106)
        .background(Color(nsColor: .windowBackgroundColor))
        .allowsHitTesting(false)
        .previewLayout(.fixed(width: AppDelegate.preferenceSize.width, height: AppDelegate.preferenceSize.height + 106))
    }
}
#endif
