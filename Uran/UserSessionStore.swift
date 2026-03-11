import Foundation
import Combine

import UIKit

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

#if canImport(FirebaseCore)
import FirebaseCore
#endif

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@MainActor
final class UserSessionStore: ObservableObject {
    @Published var userId: String

    @Published var isLoggedIn: Bool
    @Published var provider: String
    @Published var email: String
    @Published var displayName: String
    @Published var fullName: String
    @Published var studyPlace: String
    @Published var workPlace: String
    @Published var myNotes: String
    @Published var avatarBase64: String

    @Published var authErrorMessage: String

    nonisolated static let defaultUserId = "default"

    private let defaultsKey = "user_session_stub_v1"
    private let profileDefaultsPrefix = "user_profile_v1_"
    private let lastUidDefaultsKey = "user_profile_last_uid_v1"

#if canImport(FirebaseFirestore)
    private var profileSaveWorkItem: DispatchWorkItem?
#endif

#if canImport(FirebaseAuth)
    private var authListener: AuthStateDidChangeListenerHandle?
#endif

    init(userId: String = UserSessionStore.defaultUserId) {
        self.userId = userId
        self.isLoggedIn = false
        self.provider = ""
        self.email = ""
        self.displayName = ""
        self.fullName = ""
        self.studyPlace = ""
        self.workPlace = ""
        self.myNotes = ""
        self.avatarBase64 = ""
        self.authErrorMessage = ""
        load()

#if canImport(FirebaseAuth)
        startFirebaseAuthListener()
#endif
    }

    deinit {
#if canImport(FirebaseAuth)
        if let authListener {
            Auth.auth().removeStateDidChangeListener(authListener)
        }
#endif
    }

    var effectiveUserId: String {
        let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? UserSessionStore.defaultUserId : trimmed
    }

    var avatarUIImage: UIImage? {
        let trimmed = avatarBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = Data(base64Encoded: trimmed) else { return nil }
        return UIImage(data: data)
    }

    func loginEmail(_ email: String) {
#if canImport(FirebaseAuth)
        loginEmailPassword(email: email, password: nil)
#else
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.isLoggedIn = true
        self.provider = "email"
        self.email = trimmed
        if self.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.displayName = trimmed
        }
        self.userId = trimmed
        save()
#endif
    }

    func loginGoogle() {
#if canImport(FirebaseAuth) && canImport(GoogleSignIn)
        guard let clientId = FirebaseApp.app()?.options.clientID else {
            authErrorMessage = "Firebase clientID не найден. Проверь GoogleService-Info.plist"
            return
        }

        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?.rootViewController else {
            authErrorMessage = "Не удалось получить rootViewController"
            return
        }

        let config = GIDConfiguration(clientID: clientId)
        GIDSignIn.sharedInstance.configuration = config

        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { [weak self] result, error in
            guard let self else { return }
            if let error {
                Task { @MainActor in
                    self.authErrorMessage = error.localizedDescription
                }
                return
            }

            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                Task { @MainActor in
                    self.authErrorMessage = "Google Sign-In: отсутствует токен"
                }
                return
            }

            let accessToken = user.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)

            Task {
                do {
                    _ = try await Auth.auth().signIn(with: credential)
                    await MainActor.run {
                        self.authErrorMessage = ""
                    }
                } catch {
                    await MainActor.run {
                        self.authErrorMessage = error.localizedDescription
                    }
                }
            }
        }
#else
        loginGoogleStub()
#endif
    }

    func loginEmailPassword(email: String, password: String?) {
#if canImport(FirebaseAuth)
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = (password ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.isEmpty, !p.isEmpty else { return }

        Task {
            do {
                _ = try await Auth.auth().signIn(withEmail: e, password: p)
                await MainActor.run {
                    self.authErrorMessage = ""
                }
            } catch {
                await MainActor.run {
                    self.authErrorMessage = error.localizedDescription
                }
            }
        }
#else
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.isEmpty else { return }
        self.isLoggedIn = true
        self.provider = "email"
        self.email = e
        if self.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.displayName = e
        }
        self.userId = e
        save()
#endif
    }

    func signUpEmailPassword(email: String, password: String) {
#if canImport(FirebaseAuth)
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.isEmpty, !p.isEmpty else { return }

        Task {
            do {
                _ = try await Auth.auth().createUser(withEmail: e, password: p)
                await MainActor.run {
                    self.authErrorMessage = ""
                }
            } catch {
                await MainActor.run {
                    self.authErrorMessage = error.localizedDescription
                }
            }
        }
#else
        loginEmailPassword(email: email, password: password)
#endif
    }

    func loginGoogleStub() {
#if canImport(FirebaseAuth)
        // Google Sign-In will be wired after adding GoogleSignIn + FirebaseAuth.
        // Keep stub behavior for now.
        self.isLoggedIn = true
        self.provider = "google_stub"
        if self.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.email = "user@gmail.com"
        }
        if self.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.displayName = "Google User"
        }
        self.userId = self.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if self.userId.isEmpty {
            self.userId = "google_user"
        }
        save()
#else
        self.isLoggedIn = true
        self.provider = "google"
        if self.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.email = "user@gmail.com"
        }
        if self.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.displayName = "Google User"
        }
        self.userId = self.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if self.userId.isEmpty {
            self.userId = "google_user"
        }
        save()
#endif
    }

    func logout() {
#if canImport(FirebaseAuth)
        do {
            try Auth.auth().signOut()
            authErrorMessage = ""
        } catch {
            authErrorMessage = error.localizedDescription
        }
#else
        self.isLoggedIn = false
        self.provider = ""
        self.email = ""
        self.userId = UserSessionStore.defaultUserId
        save()
#endif
    }

    func save() {
#if canImport(FirebaseAuth)
        // Persist only local profile fields; auth state comes from Firebase.
        let uid = effectiveUserId
        guard uid != UserSessionStore.defaultUserId else { return }
        let payload: [String: String] = [
            "displayName": displayName,
            "fullName": fullName,
            "studyPlace": studyPlace,
            "workPlace": workPlace,
            "myNotes": myNotes,
            "avatarBase64": avatarBase64
        ]
        UserDefaults.standard.set(payload, forKey: profileDefaultsPrefix + uid)
        UserDefaults.standard.set(uid, forKey: lastUidDefaultsKey)
#else
        let payload: [String: String] = [
            "userId": userId,
            "isLoggedIn": isLoggedIn ? "1" : "0",
            "provider": provider,
            "email": email,
            "displayName": displayName,
            "fullName": fullName,
            "studyPlace": studyPlace,
            "workPlace": workPlace,
            "myNotes": myNotes,
            "avatarBase64": avatarBase64
        ]
        UserDefaults.standard.set(payload, forKey: defaultsKey)
#endif
    }

    private func load() {
        guard let payload = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] else { return }

#if canImport(FirebaseAuth)
        // For Firebase builds, auth state comes from Firebase; profile is loaded per-uid.
        self.displayName = ""
        self.fullName = ""
#else
        self.userId = payload["userId"] ?? userId
        self.isLoggedIn = (payload["isLoggedIn"] ?? "0") == "1"
        self.provider = payload["provider"] ?? ""
        self.email = payload["email"] ?? ""
        self.displayName = payload["displayName"] ?? ""
        self.fullName = payload["fullName"] ?? ""
#endif
        self.studyPlace = payload["studyPlace"] ?? ""
        self.workPlace = payload["workPlace"] ?? ""
        self.myNotes = payload["myNotes"] ?? ""
        self.avatarBase64 = payload["avatarBase64"] ?? ""
    }

#if canImport(FirebaseAuth)
    private func resetLocalProfileFields() {
        displayName = ""
        fullName = ""
        studyPlace = ""
        workPlace = ""
        myNotes = ""
        avatarBase64 = ""
    }

    private func loadLocalProfileFromDefaultsIfAny(uid: String) {
        let key = profileDefaultsPrefix + uid
        guard let payload = UserDefaults.standard.dictionary(forKey: key) as? [String: String] else { return }
        displayName = payload["displayName"] ?? ""
        fullName = payload["fullName"] ?? ""
        studyPlace = payload["studyPlace"] ?? ""
        workPlace = payload["workPlace"] ?? ""
        myNotes = payload["myNotes"] ?? ""
        avatarBase64 = payload["avatarBase64"] ?? ""
    }
#endif

#if canImport(FirebaseFirestore)
    private func profileDocRef(for uid: String) -> DocumentReference {
        Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("profile")
            .document("main")
    }

    func scheduleProfileSaveToCloud(debounceSeconds: TimeInterval = 0.7) {
        profileSaveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task {
                await self.saveProfileToCloudIfPossible()
            }
        }
        profileSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceSeconds, execute: work)
    }

    func loadProfileFromCloudIfPossible() async {
        let uid = effectiveUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty, uid != UserSessionStore.defaultUserId else { return }
        do {
            let doc = try await profileDocRef(for: uid).getDocument()
            if doc.exists, let data = doc.data() {
                await MainActor.run {
                    if let v = data["displayName"] as? String { self.displayName = v }
                    if let v = data["fullName"] as? String { self.fullName = v }
                    if let v = data["studyPlace"] as? String { self.studyPlace = v }
                    if let v = data["workPlace"] as? String { self.workPlace = v }
                    if let v = data["myNotes"] as? String { self.myNotes = v }
                    if let v = data["avatarBase64"] as? String { self.avatarBase64 = v }
                    self.save()
                }
            } else {
                await saveProfileToCloudIfPossible()
            }
        } catch {
            print("[UserSessionStore] loadProfileFromCloudIfPossible failed: \(error)")
        }
    }

    func saveProfileToCloudIfPossible() async {
        let uid = effectiveUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty, uid != UserSessionStore.defaultUserId else { return }
        do {
            let payload: [String: Any] = [
                "displayName": displayName,
                "displayNameLower": displayName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
                "fullName": fullName,
                "studyPlace": studyPlace,
                "workPlace": workPlace,
                "myNotes": myNotes,
                "avatarBase64": avatarBase64,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            try await profileDocRef(for: uid).setData(payload, merge: true)
        } catch {
            print("[UserSessionStore] saveProfileToCloudIfPossible failed: \(error)")
        }
    }
#endif

#if canImport(FirebaseAuth)
    private func startFirebaseAuthListener() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                if let user {
                    let prevUid = UserDefaults.standard.string(forKey: self.lastUidDefaultsKey) ?? ""
                    self.isLoggedIn = true
                    self.provider = user.providerData.first?.providerID ?? "firebase"
                    self.email = user.email ?? ""
                    self.userId = user.uid

                    // Important: avoid leaking profile fields between accounts.
                    if prevUid != user.uid {
                        self.resetLocalProfileFields()
                        self.loadLocalProfileFromDefaultsIfAny(uid: user.uid)
                    }

                    if self.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.displayName = user.displayName ?? (user.email ?? "")
                    }
                    self.authErrorMessage = ""
                    self.save()
                } else {
                    self.isLoggedIn = false
                    self.provider = ""
                    self.email = ""
                    self.userId = UserSessionStore.defaultUserId

                    self.resetLocalProfileFields()
                }
            }

#if canImport(FirebaseFirestore)
            if user != nil {
                Task {
                    await self.loadProfileFromCloudIfPossible()
                }
            }
#endif
        }
    }
#endif
}
