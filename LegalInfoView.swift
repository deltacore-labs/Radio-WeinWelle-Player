//
//  LegalInfoView.swift
//  Radio-WeinWelle-Player
//

import SwiftUI

struct LegalInfoView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Impressum") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Radio Wein-Welle")
                            .font(.headline)
                        Text("Das Winzerfestradio")
                            .foregroundStyle(.secondary)
                        Text("Ein Veranstaltungsradio-Projekt der evangelischen Jugend im Dekanat Vorderer Odenwald zum Winzerfest")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }

                Section("Sendehaus") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Evangelisches Gemeindehaus")
                        Text("Pfälzer Gasse 14")
                        Text("D-64823 Groß-Umstadt (Hessen)")
                    }
                    .font(.footnote)

                    Link("Tel.: +49 (0) 6078 8638", destination: URL(string: "tel:+49607886380")!)
                        .font(.footnote)

                    Link("info@radio-wein-welle.de", destination: URL(string: "mailto:info@radio-wein-welle.de")!)
                        .font(.footnote)
                }

                Section("Vertretungsberechtigter Intendant") {
                    Text("Rainer Volkmar\nJugendreferent & Projektleiter")
                        .font(.footnote)
                }

                Section("Zuständige Aufsichtsbehörden") {
                    Text("Landesanstalt für privaten Rundfunk und neue Medien (LPR Hessen) | Kassel")
                        .font(.footnote)
                    Text("Bundesnetzagentur f. Elektrizität, Gas, Telekommunikation, Post und Eisenbahnen | Bonn")
                        .font(.footnote)
                    Text("Evangelisches Medienhaus, Zentrum für evang. Publizistik und Medienarbeit | Frankfurt")
                        .font(.footnote)
                }

                Section("Technik & Multimedia") {
                    Link("webmaster@radio-wein-welle.de", destination: URL(string: "mailto:webmaster@radio-wein-welle.de")!)
                        .font(.footnote)
                }

                Section("Entwicklung") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stefan Friedrich | DeltaCorelabs")
                            .font(.footnote)
                        Link("deltacore-labs.github.io", destination: URL(string: "https://deltacore-labs.github.io/public-website/")!)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Impressum")
        }
    }
}

#Preview {
    LegalInfoView()
}
