import SwiftUI

struct ExtempPpkSheet: View {
    let text: String

    var body: some View {
        NavigationStack {
            ScrollView {
                PpkPrettyText(text: text)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .navigationTitle("ППК")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
