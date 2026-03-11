import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: UserSessionStore

    @State private var email: String = ""
    @State private var password: String = ""

    private var isShowingAuthError: Binding<Bool> {
        Binding(
            get: { !session.authErrorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            set: { newValue in
                if !newValue { session.authErrorMessage = "" }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled(true)

                    SecureField("Пароль", text: $password)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    Button {
                        Haptics.tap()
                        session.loginEmailPassword(email: email, password: password)
                    } label: {
                        Text("Войти")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)

                    Button {
                        Haptics.tap()
                        #if canImport(FirebaseAuth) && canImport(GoogleSignIn)
                        session.loginGoogle()
                        #else
                        session.loginGoogleStub()
                        #endif
                    } label: {
                        Label("Sign in with Google", systemImage: "g.circle")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                if !session.authErrorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        Text(session.authErrorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("URAN")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Ошибка", isPresented: isShowingAuthError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(session.authErrorMessage)
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(UserSessionStore())
}
