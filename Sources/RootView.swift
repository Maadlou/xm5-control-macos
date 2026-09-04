import SwiftUI

struct RootView: View {
    @EnvironmentObject private var headphones: SonyHeadphonesController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "headphones")
                .font(.system(size: 40))
                .accessibilityHidden(true)
            Text(headphones.deviceName)
                .font(.largeTitle.bold())
                .accessibilityIdentifier("home.title")
            Text(headphones.statusText)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(minWidth: 520, minHeight: 340, alignment: .topLeading)
    }
}
