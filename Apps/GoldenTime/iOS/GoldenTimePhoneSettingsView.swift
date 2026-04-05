import CoreLocation
import GoldenTimeCore
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

private enum GTPhoneSettingsLegalSheet: String, Identifiable {
    case privacyPolicy
    case support

    var id: String { rawValue }
}

/// iPhone settings sheet: reminders, display, location, language, and lightweight legal/support entry points.
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
    @State private var legalSheet: GTPhoneSettingsLegalSheet?

    private static let reminderMinuteChoices = [5, 10, 15, 20, 30, 45, 60]

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
                    VStack(spacing: 8) {
                        HStack(spacing: 10) {
                            legalButton(title: GTCopy.settingsPrivacyPolicy(lang), sheet: .privacyPolicy)
                            Text("·")
                                .foregroundStyle(GTPhoneSettingsListColors.rowSecondary)
                            legalButton(title: GTCopy.settingsSupport(lang), sheet: .support)
                        }
                        .frame(maxWidth: .infinity)

                        Text(GTCopy.settingsLegalFooter(lang))
                            .font(.footnote)
                            .foregroundStyle(GTPhoneSettingsListColors.rowSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 10, leading: 18, bottom: 8, trailing: 18))
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
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
            .sheet(item: $legalSheet) { sheet in
                legalSheetView(sheet)
            }
        }
    }

    @ViewBuilder
    private func settingsSectionHeader(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(skin.settingsSectionHeaderForeground)
            .shadow(color: skin.settingsSectionHeaderShadowColor, radius: 2, x: 0, y: 1)
    }

    @ViewBuilder
    private func legalButton(title: String, sheet: GTPhoneSettingsLegalSheet) -> some View {
        Button {
            legalSheet = sheet
        } label: {
            Text(title)
                .font(.footnote)
                .underline()
                .foregroundStyle(GTPhoneSettingsListColors.controlAccent)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func legalSheetView(_ sheet: GTPhoneSettingsLegalSheet) -> some View {
        NavigationStack {
            ScrollView {
                Text(legalBody(for: sheet))
                    .font(.body)
                    .foregroundStyle(GTPhoneSettingsListColors.rowLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    .textSelection(.enabled)
            }
            .background(
                LinearGradient(
                    colors: [skin.upper, skin.lower],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle(legalTitle(for: sheet))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(GTCopy.settingsDone(lang)) {
                        legalSheet = nil
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(skin.ink)
                }
            }
        }
    }

    private func legalTitle(for sheet: GTPhoneSettingsLegalSheet) -> String {
        switch sheet {
        case .privacyPolicy:
            return GTCopy.settingsPrivacyPolicy(lang)
        case .support:
            return GTCopy.settingsSupport(lang)
        }
    }

    private func legalBody(for sheet: GTPhoneSettingsLegalSheet) -> String {
        switch sheet {
        case .privacyPolicy:
            return GTCopy.legalPrivacyPolicyBody(lang)
        case .support:
            return GTCopy.legalSupportBody(lang)
        }
    }
}
