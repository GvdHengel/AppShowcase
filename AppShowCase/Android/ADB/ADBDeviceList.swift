import Foundation

/// Eén regel uit `adb devices -l`.
struct ADBDeviceEntry: Equatable {
    let serial: String
    /// "device", "unauthorized", "offline", "authorizing", "no permissions", …
    let state: String
    let model: String?
    let product: String?

    var displayName: String {
        model?.replacingOccurrences(of: "_", with: " ") ?? serial
    }

    var isReady: Bool { state == "device" }

    /// Uitleg voor de gebruiker als het toestel (nog) niet bruikbaar is.
    var statusMessage: String? {
        switch state {
        case "device":
            return nil
        case "unauthorized":
            return "Tik op 'Toestaan' in de melding op het toestel om USB-foutopsporing toe te staan."
        case "authorizing":
            return "Wachten op toestemming op het toestel…"
        case "offline":
            return "Het toestel is offline. Ontkoppel de kabel en sluit hem opnieuw aan."
        default:
            return "Toestel niet bruikbaar (status: \(state))."
        }
    }

    var deviceInfo: DeviceInfo {
        DeviceInfo(
            id: DeviceID(platform: .android, rawID: serial),
            name: displayName,
            model: model?.replacingOccurrences(of: "_", with: " "),
            statusMessage: statusMessage
        )
    }
}

enum ADBDeviceListParser {
    /// Leest de uitvoer van `adb devices -l`.
    static func parse(_ output: String) -> [ADBDeviceEntry] {
        output.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty,
                  !line.hasPrefix("List of devices"),
                  !line.hasPrefix("*"),
                  !line.hasPrefix("adb server")
            else { return nil }

            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 2 else { return nil }

            var state = parts[1]
            var restStart = 2
            if state == "no", parts.count > 2, parts[2] == "permissions" {
                state = "no permissions"
                restStart = 3
            }

            var properties: [String: String] = [:]
            for part in parts.dropFirst(restStart) {
                let pair = part.split(separator: ":", maxSplits: 1).map(String.init)
                if pair.count == 2 { properties[pair[0]] = pair[1] }
            }

            return ADBDeviceEntry(
                serial: parts[0],
                state: state,
                model: properties["model"],
                product: properties["product"]
            )
        }
    }
}
