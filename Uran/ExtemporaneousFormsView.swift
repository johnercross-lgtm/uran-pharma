import SwiftUI

struct ExtemporaneousFormsView: View {
    @State private var showAssistant: Bool = false
    
    var body: some View {
        NavigationStack {
            ExtempFormBuilderView()
                .navigationTitle("Экстемпоральные")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Асистент") {
                            showAssistant = true
                        }
                    }
                }
                .sheet(isPresented: $showAssistant) {
                    ReferenceAssistantView()
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
        }
    }
}
