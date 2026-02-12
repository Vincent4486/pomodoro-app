import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var permissionsManager: PermissionsManager

    var body: some View {
        SettingsPermissionsView(permissionsManager: permissionsManager)
    }
}

#Preview {
    MainActor.assumeIsolated {
        SettingsView(permissionsManager: .shared)
            .environmentObject(AuthViewModel.shared)
    }
}
