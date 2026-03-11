import SwiftUI

struct ExtempResultSheet: View {
    let text: String

    var body: some View {
        NavigationStack {
            ScrollView {
                RxPrettyText(text: text)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .navigationTitle("Результат")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
