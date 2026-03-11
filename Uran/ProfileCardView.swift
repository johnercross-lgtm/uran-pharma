import SwiftUI
import UIKit

struct ProfileCardView: View {
    let displayName: String
    let workPlace: String
    let studyPlace: String
    let email: String
    let avatarImage: UIImage?
    let stats: [(value: String, label: String)]
    let actionButtons: AnyView

    init(
        displayName: String,
        workPlace: String,
        studyPlace: String,
        email: String,
        avatarImage: UIImage?,
        stats: [(value: String, label: String)],
        @ViewBuilder actionButtons: () -> some View
    ) {
        self.displayName = displayName
        self.workPlace = workPlace
        self.studyPlace = studyPlace
        self.email = email
        self.avatarImage = avatarImage
        self.stats = stats
        self.actionButtons = AnyView(actionButtons())
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background Image
            GeometryReader { proxy in
                if let img = avatarImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(red: 0.12, green: 0.12, blue: 0.18))
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 80))
                                .foregroundStyle(.white.opacity(0.1))
                        }
                }
            }

            // Gradient Overlay
            LinearGradient(
                colors: [
                    .black.opacity(0.0),
                    .black.opacity(0.2),
                    .black.opacity(0.8)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Content
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    // Badge
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(SolarizedTheme.accentColor)
                        .background(Circle().fill(.white).padding(2))
                }
                .padding(.top, 16)
                .padding(.trailing, 16)
                
                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName.isEmpty ? "Пользователь" : displayName)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)

                    if !workPlace.isEmpty {
                        Text(workPlace)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    if !studyPlace.isEmpty {
                        Text(studyPlace)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.9))
                    } else if !email.isEmpty {
                         Text(email)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                // Stats Row
                HStack(spacing: 24) {
                    ForEach(stats, id: \.label) { stat in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stat.value)
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text(stat.label)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                .padding(.top, 8)

                // Action Buttons
                actionButtons
                    .padding(.top, 8)
            }
            .padding(24)
        }
        .frame(height: 460)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
    }
}
