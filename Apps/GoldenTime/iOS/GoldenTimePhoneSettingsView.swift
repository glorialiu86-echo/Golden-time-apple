import CoreLocation
import GoldenTimeCore
import StoreKit
import SwiftUI

/// iPhone settings sheet: language preference, location, twilight display (synced with Watch), App Store restore.
struct GoldenTimePhoneSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @ObservedObject var model: GoldenTimePhoneViewModel

    @AppStorage(GTAppLanguage.storageKey, store: GTAppGroup.shared) private var langPreferenceRaw: String =
        GTAppLanguage.followSystemStorageValue
    @AppStorage(GTTwilightDisplayMode.storageKey, store: GTAppGroup.shared) private var twilightModeRaw: String =
        GTTwilightDisplayMode.clockTimes.rawValue

    @State private var restoreMessage: String?
    @State private var restoreFailed = false
    @State private var restoreInFlight = false

    private var lang: GTAppLanguage {
        let _ = locale.identifier
        return GTAppLanguage.phoneDisplayLanguage(preferenceRaw: langPreferenceRaw)
    }

    private var languagePreferencePickerSelection: Binding<String> {
        Binding(
            get: {
                let r = langPreferenceRaw
                if r == GTAppLanguage.chinese.rawValue || r == GTAppLanguage.english.rawValue
                    || r == GTAppLanguage.followSystemStorageValue
                {
                    return r
                }
                return GTAppLanguage.followSystemStorageValue
            },
            set: { langPreferenceRaw = $0 }
        )
    }

    private var skin: GTPhaseSkin {
        GTPhaseSkin(phase: model.phase)
    }

    private var locationStatusWord: String {
        switch model.locationAuthorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return GTCopy.settingsLocationAuthorized(lang)
        case .denied:
            return GTCopy.settingsLocationDenied(lang)
        case .notDetermined:
            return GTCopy.settingsLocationNotDetermined(lang)
        case .restricted:
            return GTCopy.settingsLocationRestricted(lang)
        @unknown default:
            return GTCopy.settingsLocationNotDetermined(lang)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(GTCopy.settingsLanguageSectionTitle(lang), selection: languagePreferencePickerSelection) {
                        Text(GTCopy.settingsLanguageOptionFollowSystem(lang)).tag(GTAppLanguage.followSystemStorageValue)
                        Text(GTCopy.settingsLanguageOptionChinese(lang)).tag(GTAppLanguage.chinese.rawValue)
                        Text(GTCopy.settingsLanguageOptionEnglish(lang)).tag(GTAppLanguage.english.rawValue)
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Text("\(GTCopy.settingsStatusPrefix(lang))：\(locationStatusWord)")
                        .font(.subheadline)
                        .foregroundStyle(skin.muted)

                    switch model.locationAuthorizationStatus {
                    case .notDetermined:
                        Button(GTCopy.settingsAllowLocation(lang)) {
                            model.refreshGPS()
                        }
                    case .denied, .restricted:
                        Button(GTCopy.settingsOpenSystemSettings(lang)) {
                            model.openSystemSettings()
                        }
                    default:
                        EmptyView()
                    }

                    Button(GTCopy.settingsRefreshLocation(lang)) {
                        model.refreshGPS()
                    }
                } header: {
                    Text(GTCopy.settingsLocation(lang))
                }

                Section {
                    Picker(GTCopy.settingsTwilightDisplay(lang), selection: $twilightModeRaw) {
                        Text(GTCopy.settingsTwilightClockTimes(lang)).tag(GTTwilightDisplayMode.clockTimes.rawValue)
                        Text(GTCopy.settingsTwilightCountdown(lang)).tag(GTTwilightDisplayMode.countdown.rawValue)
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Button {
                        Task { await restorePurchases() }
                    } label: {
                        HStack {
                            Text(GTCopy.settingsRestorePurchases(lang))
                            if restoreInFlight {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(restoreInFlight)

                    if let restoreMessage {
                        Text(restoreMessage)
                            .font(.footnote)
                            .foregroundStyle(restoreFailed ? Color.red.opacity(0.9) : skin.muted)
                    }
                }
            }
            .navigationTitle(GTCopy.settingsTitle(lang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(GTCopy.settingsDone(lang)) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .tint(skin.ink)
            .scrollContentBackground(.hidden)
            .background(
                LinearGradient(
                    colors: [skin.upper, skin.lower],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
        }
    }

    @MainActor
    private func restorePurchases() async {
        restoreInFlight = true
        restoreFailed = false
        restoreMessage = GTCopy.settingsRestoreWorking(lang)
        defer { restoreInFlight = false }
        do {
            try await AppStore.sync()
            restoreFailed = false
            restoreMessage = GTCopy.settingsRestoreDone(lang)
        } catch {
            restoreFailed = true
            restoreMessage = "\(GTCopy.settingsRestoreFailed(lang))（\(error.localizedDescription)）"
        }
    }
}
