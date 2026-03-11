//
//  UranApp.swift
//  Uran
//
//  Created by Eugen Tamara on 30.01.2026.
//

import SwiftUI
import Foundation

#if canImport(FirebaseCore)
import FirebaseCore
#endif

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct UranApp: App {
    #if canImport(FirebaseCore)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { url in
#if canImport(GoogleSignIn)
                    _ = GIDSignIn.sharedInstance.handle(url)
#endif
                }
        }
    }
}

#if canImport(FirebaseCore)
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        if let app = FirebaseApp.app() {
            print("[Firebase] name=\(app.name) projectID=\(app.options.projectID ?? "nil") googleAppID=\(app.options.googleAppID) bundleID=\(app.options.bundleID)")
        } else {
            print("[Firebase] FirebaseApp.app() == nil after configure")
        }

#if DEBUG
        runPharmaDBSmokeTestOnce()
        runRxEngineSmokeTestOnce()
#endif
        return true
    }

#if DEBUG
    private func runPharmaDBSmokeTestOnce() {
        let key = "pharmadb_smoketest_v1"
        if UserDefaults.standard.bool(forKey: key) { return }
        UserDefaults.standard.set(true, forKey: key)

        DispatchQueue.global(qos: .utility).async {
            do {
                try PharmaDB.shared.open()

                let rx = PharmaPrescription(
                    inscriptio: "20-я поликлиника\nул. Дарвина, 8\nтел. 43-19-36",
                    datumISO: "1999-10-08",
                    patientName: "Иванов Н. В.",
                    patientAge: "10 лет",
                    doctorName: "Петров И. П.",
                    invocatio: "Rp.: (Recipe)",
                    subscriptio: "Misce. Da.",
                    signatura: "По 1 чайной ложке 3 раза в день",
                    doctorSignatureText: "ВРАЧ",
                    stampsText: "Личная печать врача; другие печати"
                )

                let items: [PharmaPrescriptionItem] = [
                    .init(prescriptionId: rx.id, orderNo: 1, role: .basis, substanceText: "Codeini phosphatis", amountValue: "0.06", amountUnit: "g"),
                    .init(prescriptionId: rx.id, orderNo: 2, role: .adjuvans, substanceText: "Natrii benzoatis", amountValue: "1.0", amountUnit: "g"),
                    .init(prescriptionId: rx.id, orderNo: 3, role: .corrigens, substanceText: "Sirupi simplicis", amountValue: "10", amountUnit: "ml"),
                    .init(prescriptionId: rx.id, orderNo: 4, role: .menstruum, substanceText: "Aquae purificatae", amountValue: "200", amountUnit: "ml")
                ]

                try PharmaDB.shared.createPrescription(rx, items: items)

                let (loaded, loadedItems) = try PharmaDB.shared.fetchPrescription(id: rx.id)
                print("[PharmaDB] Loaded:", loaded.id, loaded.patientName ?? "")
                print("[PharmaDB] Items:", loadedItems.count)
            } catch {
                print("[PharmaDB] DB error:", error)
            }
        }
    }

    private func runRxEngineSmokeTestOnce() {
        let key = "rxengine_smoketest_v1"
        let forceRun = ProcessInfo.processInfo.arguments.contains("-rx-smoke-force")
        if UserDefaults.standard.bool(forKey: key), !forceRun { return }
        UserDefaults.standard.set(true, forKey: key)

        DispatchQueue.global(qos: .utility).async {
            let results = RxFixtureScenarios.run()
            let failed = results.filter { !$0.passed }
            self.persistRxSmokeReport(results: results, failed: failed)

            if failed.isEmpty {
                print("[RxEngineSmoke] ✅ all scenarios passed (\(results.count))")
                return
            }

            print("[RxEngineSmoke] ❌ failed scenarios: \(failed.count)/\(results.count)")
            for item in failed {
                print("[RxEngineSmoke] - \(item.scenarioId): \(item.details.joined(separator: "; "))")
            }

            let summary = failed
                .map { "\($0.scenarioId): \($0.details.joined(separator: ", "))" }
                .joined(separator: " | ")
            DispatchQueue.main.async {
                let strictMode = ProcessInfo.processInfo.arguments.contains("-rx-smoke-strict")
                if strictMode {
                    assertionFailure("[RxEngineSmoke] Failed: \(summary)")
                } else {
                    print("[RxEngineSmoke] ⚠️ non-fatal in DEBUG. Add launch argument '-rx-smoke-strict' to fail fast.")
                }
            }
        }
    }

    private func persistRxSmokeReport(results: [RxFixtureResult], failed: [RxFixtureResult]) {
        let defaults = UserDefaults.standard
        let now = ISO8601DateFormatter().string(from: Date())

        defaults.set(now, forKey: "rxengine_smoketest_last_ran_at")
        defaults.set(results.count, forKey: "rxengine_smoketest_last_total")
        defaults.set(failed.count, forKey: "rxengine_smoketest_last_failed")
        defaults.set(failed.isEmpty, forKey: "rxengine_smoketest_last_passed")
        defaults.set(
            failed.map(\.scenarioId).joined(separator: ","),
            forKey: "rxengine_smoketest_last_failed_ids"
        )

        let report: [String: Any] = [
            "generatedAt": now,
            "total": results.count,
            "failed": failed.count,
            "passed": failed.isEmpty,
            "failedScenarios": failed.map { ["id": $0.scenarioId, "details": $0.details] }
        ]

        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]),
           let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        {
            let url = baseURL.appendingPathComponent("rx_smoke_report.json")
            try? data.write(to: url, options: .atomic)
        }

        defaults.synchronize()
    }
#endif

}
#endif
