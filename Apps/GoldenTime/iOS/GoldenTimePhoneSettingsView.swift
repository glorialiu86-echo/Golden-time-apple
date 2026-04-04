import CoreLocation
import GoldenTimeCore
import StoreKit
import SwiftUI

/// Fixed sRGB for settings `List` cells — never `Color.primary` / `.secondary` / phase `tint`, which can render white-on-white on grouped rows.
private enum GTPhoneSettingsListColors {
    static let rowLabel = Color(red: 24 / 255, green: 26 / 255, blue: 32 / 255)
    static let rowSecondary = Color(red: 88 / 255, green: 91 / 255, blue: 99 / 255)
    static let rowBackground = Color(red: 1, green: 1, blue: 1)
    /// Standard iOS blue for toggle / menu chrome on white rows.
    static let controlAccent = Color(red: 0, green: 122 / 255, blue: 255 / 255)
    static let errorText = Color(red: 200 / 255, green: 52 / 255, blue: 52 / 255)
}

/// iPhone settings sheet: language preference, location, twilight display (synced with Watch), App Store restore.
struct GoldenTimePhoneSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @ObservedObject var model: GoldenTimePhoneViewModel

    @AppStorage(GTAppLanguage.storageKey, store: GTAppGroup.shared) private var langPreferenceRaw: String =
        GTAppLanguage.followSystemStorageValue
    @AppStorage(GTTwilightDisplayMode.storageKey, store: GTAppGroup.shared) private var twilightModeRaw: String =
        GTTwilightDisplayMode.clockTimes.rawValue
    @AppStorage(GTTwilightReminderSettings.enabledKey, store: GTAppGroup.shared) private var reminderEnabled = false
    @AppStorage(GTTwilightReminderSettings.targetKey, store: GTAppGroup.shared) private var reminderTargetRaw: String =
        GTTwilightReminderSettings.Target.blue.rawValue
    @AppStorage(GTTwilightReminderSettings.minutesBeforeKey, store: GTAppGroup.shared) private var reminderMinutes: Int =
        GTTwilightReminderSettings.defaultMinutesBefore

    private static let reminderMinuteChoices = [5, 10, 15, 20, 30, 45, 60]

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
                    Toggle(isOn: $reminderEnabled) {
                        Text(GTCopy.settingsReminderToggle(lang))
                            .foregroundStyle(GTPhoneSettingsListColors.rowLabel)
                    }
                    .tint(GTPhoneSettingsListColors.controlAccent)
                    .listRowBackground(GTPhoneSettingsListColors.rowBackground)
                        .onChange(of: reminderEnabled) { _, on in
                            if on {
                                Task { @MainActor in
                                    _ = await TwilightReminderScheduler.shared.requestAuthorizationIfNeeded()
                                    model.refreshTwilightReminderSchedule()
                                }
                            } else {
                                model.refreshTwilightReminderSchedule()
                            }
                        }

                    Picker(selection: $reminderTargetRaw) {
                        Text(GTCopy.settingsReminderTargetBlue(lang)).tag(GTTwilightReminderSettings.Target.blue.rawValue)
                        Text(GTCopy.settingsReminderTargetGolden(lang)).tag(GTTwilightReminderSettings.Target.golden.rawValue)
                    } label: {
                        Text(GTCopy.settingsReminderTarget(lang))
                            .foregroundStyle(GTPhoneSettingsListColors.rowLabel)
                    }
                    .pickerStyle(.menu)
                    .tint(GTPhoneSettingsListColors.controlAccent)
                    .listRowBackground(GTPhoneSettingsListColors.rowBackground)
                    .disabled(!reminderEnabled)
                    .opacity(reminderEnabled ? 1 : 0.4)
                    .onChange(of: reminderTargetRaw) { _, _ in
                        guard reminderEnabled else { return }
                        model.refreshTwilightReminderSchedule()
                    }

                    Picker(selection: $reminderMinutes) {
                        ForEach(Self.reminderMinuteChoices, id: \.self) { m in
                            Text("\(m) \(GTCopy.settingsReminderLeadTimeSuffix(lang))").tag(m)
                        }
                    } label: {
                        Text(GTCopy.settingsReminderLeadTime(lang))
                            .foregroundStyle(GTPhoneSettingsListColors.rowLabel)
                    }
                    .pickerStyle(.menu)
                    .tint(GTPhoneSettingsListColors.controlAccent)
                    .listRowBackground(GTPhoneSettingsListColors.rowBackground)
                    .disabled(!reminderEnabled)
                    .opacity(reminderEnabled ? 1 : 0.4)
                    .onChange(of: reminderMinutes) { _, _ in
                        guard reminderEnabled else { return }
                        model.refreshTwilightReminderSchedule()
                    }
                } header: {
                    settingsSectionHeader(GTCopy.settingsReminderSection(lang))
                }

                Section {
                    Picker(selection: $twilightModeRaw) {
                        Text(GTCopy.settingsTwilightClockTimes(lang)).tag(GTTwilightDisplayMode.clockTimes.rawValue)
                        Text(GTCopy.settingsTwilightCountdown(lang)).tag(GTTwilightDisplayMode.countdown.rawValue)
                    } label: {
                        Text(GTCopy.settingsTwilightDisplay(lang))
                            .foregroundStyle(GTPhoneSettingsListColors.rowLabel)
                    }
                    .pickerStyle(.menu)
                    .tint(GTPhoneSettingsListColors.controlAccent)
                    .listRowBackground(GTPhoneSettingsListColors.rowBackground)
                    .accessibilityLabel(GTCopy.settingsTwilightDisplay(lang))
                }

                Section {
                    Text("\(GTCopy.settingsStatusPrefix(lang))：\(locationStatusWord)")
                        .font(.subheadline)
                        .foregroundStyle(GTPhoneSettingsListColors.rowSecondary)
                        .listRowBackground(GTPhoneSettingsListColors.rowBackground)

                    switch model.locationAuthorizationStatus {
                    case .notDetermined:
                        Button(GTCopy.settingsAllowLocation(lang)) {
                            model.refreshGPS()
                        }
                        .foregroundStyle(GTPhoneSettingsListColors.rowLabel)
                        .listRowBackground(GTPhoneSettingsListColors.rowBackground)
                    case .denied, .restricted:
                        Button(GTCopy.settingsOpenSystemSettings(lang)) {
                            model.openSystemSettings()
                        }
                        .foregroundStyle(GTPhoneSettingsListColors.rowLabel)
                        .listRowBackground(GTPhoneSettingsListColors.rowBackground)
                    default:
                        EmptyView()
                    }

                    Button(GTCopy.settingsRefreshLocation(lang)) {
                        model.refreshGPS()
                    }
                    .foregroundStyle(GTPhoneSettingsListColors.rowLabel)
                    .listRowBackground(GTPhoneSettingsListColors.rowBackground)
                } header: {
                    settingsSectionHeader(GTCopy.settingsLocation(lang))
                }

                Section {
                    Picker(selection: languagePreferencePickerSelection) {
                        Text(GTCopy.settingsLanguageOptionFollowSystem(lang)).tag(GTAppLanguage.followSystemStorageValue)
                        Text(GTCopy.settingsLanguageOptionChinese(lang)).tag(GTAppLanguage.chinese.rawValue)
                        Text(GTCopy.settingsLanguageOptionEnglish(lang)).tag(GTAppLanguage.english.rawValue)
                    } label: {
                        Text(GTCopy.settingsLanguageSectionTitle(lang))
                            .foregroundStyle(GTPhoneSettingsListColors.rowLabel)
                    }
                    .pickerStyle(.menu)
                    .tint(GTPhoneSettingsListColors.controlAccent)
                    .listRowBackground(GTPhoneSettingsListColors.rowBackground)
                    .accessibilityLabel(GTCopy.settingsLanguageSectionTitle(lang))
                }

                Section {
                    Button {
                        Task { await restorePurchases() }
                    } label: {
                        HStack {
                            Text(GTCopy.settingsRestorePurchases(lang))
                                .foregroundStyle(GTPhoneSettingsListColors.rowLabel)
                            if restoreInFlight {
                                Spacer()
                                ProgressView()
                                    .tint(GTPhoneSettingsListColors.controlAccent)
                            }
                        }
                    }
                    .foregroundStyle(GTPhoneSettingsListColors.rowLabel)
                    .listRowBackground(GTPhoneSettingsListColors.rowBackground)
                    .disabled(restoreInFlight)

                    if let restoreMessage {
                        Text(restoreMessage)
                            .font(.footnote)
                            .foregroundStyle(restoreFailed ? GTPhoneSettingsListColors.errorText : GTPhoneSettingsListColors.rowSecondary)
                            .listRowBackground(GTPhoneSettingsListColors.rowBackground)
                    }
                }
            }
            // Transparent list over a dark phase gradient: without this, UIKit often resolves row labels as “dark content” (light text) → white on white cells.
            .environment(\.colorScheme, .light)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(GTCopy.settingsTitle(lang))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(skin.ink)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(GTCopy.settingsDone(lang)) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(skin.ink)
                }
            }
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

    @ViewBuilder
    private func settingsSectionHeader(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(skin.settingsSectionHeaderForeground)
            .shadow(color: skin.settingsSectionHeaderShadowColor, radius: 2, x: 0, y: 1)
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
