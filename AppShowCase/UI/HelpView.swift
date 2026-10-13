import AppKit
import SwiftUI

/// Hulpvenster (menu Help → AppShowCase-hulp).
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                HelpSection(title: "iPhone of iPad aansluiten", systemImage: "iphone") {
                    HelpStep("Sluit het toestel aan met een USB-kabel.")
                    HelpStep("Ontgrendel het toestel en tik op **Vertrouw** als daarom gevraagd wordt.")
                    HelpStep("Sta **camera-toegang** (en eventueel microfoon) toe. macOS levert het iPhone-scherm aan als camerabron; de camera van je Mac wordt niet gebruikt en er wordt geen geluid opgenomen.")
                }

                HelpSection(title: "Android-toestel aansluiten", systemImage: "smartphone") {
                    HelpStep("Open **Instellingen → Over de telefoon** en tik 7× op **Build-nummer**.")
                    HelpStep("Open **Instellingen → Systeem → Ontwikkelaarsopties** en zet **USB-foutopsporing** aan.")
                    HelpStep("Sluit het toestel aan en tik op **Toestaan** (vink \"Altijd toestaan\" aan).")
                }

                HelpSection(title: "Sneltoetsen", systemImage: "keyboard") {
                    ShortcutRow(keys: "⇧⌘S", text: "Schermafbeelding mét toestelframe")
                    ShortcutRow(keys: "⇧⌘R", text: "Opname starten of stoppen")
                    ShortcutRow(keys: "⌘,", text: "Instellingen")
                    ShortcutRow(keys: "Rechtsklik", text: "Frame, achtergrond, venster en Android-demo op het toestel")
                }

                HelpSection(title: "Tips voor demo's", systemImage: "sparkles") {
                    HelpStep("Deel in Teams of Zoom **één venster** per toestel (de venstertitel is de toestelnaam), of deel je hele scherm om iPhone en Android naast elkaar te tonen.")
                    HelpStep("Kies achtergrond **Transparant** zodat alleen het toestel zichtbaar is; versleep het venster dan aan het toestel zelf.")
                    HelpStep("Zet **Altijd bovenop** aan zodat het toestel niet achter je presentatie verdwijnt.")
                    HelpStep("Android: zet **Scherm aan houden**, **Aanrakingen tonen** en **Schone statusbalk** aan. Na afloop wordt alles teruggezet.")
                }

                HelpSection(title: "Problemen oplossen", systemImage: "wrench.and.screwdriver") {
                    Problem(
                        question: "Mijn iPhone verschijnt niet",
                        answer: "Controleer de camera-toegang in Systeeminstellingen, ontgrendel de iPhone, tik op Vertrouw en probeer een andere kabel of poort."
                    ) {
                        Button("Open camera-instellingen") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                    Problem(
                        question: "Ik zie geen beeld van mijn iPhone",
                        answer: "Ontgrendel de iPhone. Gebruikt QuickTime Player hetzelfde toestel (Nieuwe filmopname), dan krijgt AppShowCase geen beeld: sluit QuickTime — het venster verbindt daarna vanzelf opnieuw."
                    )
                    Problem(
                        question: "Android staat op \"Tik op Toestaan\"",
                        answer: "Op het toestel staat een melding om USB-foutopsporing toe te staan. Tik op Toestaan; het beeld start dan vanzelf. Geen melding? Trek de kabel eruit en sluit hem opnieuw aan."
                    )
                    Problem(
                        question: "\"adb niet gevonden\"",
                        answer: "Installeer Android Studio (of `brew install android-platform-tools`), of draai `./scripts/fetch-deps.sh` in de projectmap en bouw de app opnieuw."
                    )
                    Problem(
                        question: "Android-beeld hapert of blijft zwart",
                        answer: "Klik op Opnieuw proberen, gebruik een andere kabel, of kies in Instellingen een lagere Android-beeldkwaliteit."
                    )
                }

                HelpSection(title: "Waar staan mijn bestanden?", systemImage: "folder") {
                    HStack {
                        Button("Schermafbeeldingen") { OutputFolders.reveal(.picturesDirectory) }
                        Button("Opnames") { OutputFolders.reveal(.moviesDirectory) }
                    }
                    Text("Afbeeldingen/AppShowCase en Films/AppShowCase in je thuismap.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: 620, alignment: .leading)
        }
        .frame(minWidth: 480, minHeight: 480)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("AppShowCase-hulp")
                    .font(.title.bold())
                Text("iPhone- en Android-schermen live op je Mac, in een toestelframe.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct HelpSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(.leading, 4)
        }
    }
}

private struct HelpStep: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ShortcutRow: View {
    let keys: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(.body, design: .rounded).weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                .frame(minWidth: 90, alignment: .leading)
            Text(text)
        }
    }
}

private struct Problem<Extra: View>: View {
    let question: String
    let answer: LocalizedStringKey
    @ViewBuilder let extra: () -> Extra

    init(question: String, answer: LocalizedStringKey, @ViewBuilder extra: @escaping () -> Extra) {
        self.question = question
        self.answer = answer
        self.extra = extra
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question).fontWeight(.semibold)
            Text(answer)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            extra()
        }
    }
}

extension Problem where Extra == EmptyView {
    init(question: String, answer: LocalizedStringKey) {
        self.init(question: question, answer: answer) { EmptyView() }
    }
}
