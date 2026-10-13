import Foundation

/// Zoekt een bruikbare adb-binary.
///
/// Voorkeur voor een al geïnstalleerde adb (Android Studio / Homebrew): als wij een andere
/// adb-versie gebruiken dan de draaiende adb-server, herstart adb die server en verstoort
/// dat bijvoorbeeld Android Studio. De meegeleverde adb (Vendor/) is de laatste optie.
enum ADBLocator {
    static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory(),
        bundledPath: String? = Bundle.main.path(forResource: "adb", ofType: nil),
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        candidates(environment: environment, home: home, bundledPath: bundledPath).first(where: isExecutable)
    }

    static func candidates(environment: [String: String], home: String, bundledPath: String?) -> [String] {
        var list: [String] = []
        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let sdk = environment[key], !sdk.isEmpty {
                list.append("\(sdk)/platform-tools/adb")
            }
        }
        list += [
            "\(home)/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "\(home)/.homebrew/bin/adb",
        ]
        if let bundledPath { list.append(bundledPath) }
        return list
    }
}
