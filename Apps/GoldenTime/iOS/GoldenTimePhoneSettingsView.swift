import CoreLocation
import GoldenTimeCore
import SwiftUI
import UserNotifications

/// Fixed sRGB for settings `List` cells — never `Color.primary` / `.secondary` / phase `tint`, which can render white-on-white on grouped rows.
private enum GTPhoneSettingsListColors {
    static let rowLabel = Color(red: 24 / 255, green: 26 / 255, blue: 32 / 255)
    static let rowSecondary = Color(red: 88 / 255, green: 91 / 255, blue: 99 / 255)
    static let rowBackground = Color(red: 1, green: 1, blue: 1)
    /// Standard iOS blue for toggle / menu chrome on white rows.
    static let controlAccent = Color(red: 0, green: 122 / 255, blue: 255 / 255)
    static let successText = Color(red: 34 / 255, green: 139 / 255, blue: 34 / 255)
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
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var model: GoldenTimePhoneViewModel
    @StateObject private var reminderStore: GTTwilightReminderStore

    @AppStorage(GTAppLanguage.storageKey, store: GTAppGroup.shared) private var langPreferenceRaw: String =
        GTAppLanguage.followSystemStorageValue
    @AppStorage(GTTwilightDisplayMode.storageKey, store: GTAppGroup.shared) private var twilightModeRaw: String =
        GTTwilightDisplayMode.clockTimes.rawValue
    @State private var legalSheet: GTPhoneSettingsLegalSheet?
    @State private var reminderDebugPendingCount = "0"
    @State private var reminderDebugDeliveredCount = "0"
    @State private var reminderDebugPlanCount = "0"

    private static let reminderMinuteChoices = [5, 10, 15, 20, 30, 45, 60]

    init(model: GoldenTimePhoneViewModel) {
        self.model = model
        _reminderStore = StateObject(wrappedValue: GTTwilightReminderStore())
    }

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

    private var reminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { reminderStore.isEnabled },
            set: { on in updateReminderEnabled(on) }
        )
    }

    private var reminderTargetBinding: Binding<String> {
        Binding(
            get: { reminderStore.target.rawValue },
            set: { value in
                let nextTarget = GTTwilightReminderSettings.Target(rawValue: value) ?? .blue
                reminderStore.setTarget(nextTarget)
                guard reminderStore.isEnabled else { return }
                model.refreshTwilightReminderSchedule()
                Task { await refreshReminderDiagnostics() }
            }
        )
    }

    private var reminderMinutesBinding: Binding<Int> {
        Binding(
            get: { reminderStore.minutesBefore },
            set: { value in
                reminderStore.setMinutesBefore(value)
                guard reminderStore.isEnabled else { return }
                model.refreshTwilightReminderSchedule()
                Task { await refreshReminderDiagnostics() }
            }
        )
    }

    private var skin: GTPhaseSkin {
        GTPhaseSkin(phase: model.phase)
    }

    private var showsReminderDebugDiagnostics: Bool {
        GTUITestLaunchOverrides.isEnabled
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

    private var locationFeedbackText: String? {
        switch model.settingsLocationFeedback {
        case .idle:
            return nil
        case .waitingForPermission:
            return GTCopy.settingsLocationFeedbackWaitingForPermission(lang)
        case .refreshing:
            return GTCopy.settingsLocationFeedbackRefreshing(lang)
        case .success:
            return GTCopy.settingsLocationFeedbackSuccess(lang)
        case .denied:
            return GTCopy.settingsLocationFeedbackDenied(lang)
        case .restricted:
            return GTCopy.settingsLocationFeedbackRestricted(lang)
        case .failed:
            return GTCopy.settingsLocationFeedbackFailed(lang)
        }
    }

    private var locationFeedbackColor: Color {
        switch model.settingsLocationFeedback {
        case .success:
            return GTPhoneSettingsListColors.successText
        case .denied, .restricted, .failed:
            return GTPhoneSettingsListColors.errorText
        default:
            return GTPhoneSettingsListColors.rowSecondary
        }
    }

    private func shouldShowLocationFeedback(isAuthorizationRow: Bool) -> Bool {
        if model.settingsLocationFeedback == .idle {
            return false
        }
        if model.locationAuthorizationStatus == .notDetermined {
            return isAuthorizationRow
        }
        return !isAuthorizationRow
    }

    var body: some View {
        NavigationStack {
            List {
                if showsReminderDebugDiagnostics {
                    Section {
                        debugMetricRow(
                            title: "Pending",
                            value: reminderDebugPendingCount,
                            identifier: "gt.phone.debug.reminderPendingCount"
                        )
                        debugMetricRow(
                            title: "Delivered",
                            value: reminderDebugDeliveredCount,
                            identifier: "gt.phone.debug.reminderDeliveredCount"
                        )
                        debugMetricRow(
                            title: "Planned",
                            value: reminderDebugPlanCount,
                            identifier: "gt.phone.debug.reminderPlanCount"
                        )
                        Button("Refresh Notification Debug") {
                            Task { await refreshReminderDiagnostics() }
                        }
                        .foregroundStyle(GTPhoneSettingsListColors.rowLabel)
                        .listRowBackground(GTPhoneSettingsListColors.rowBackground)
                        .accessibilityIdentifier("gt.phone.debug.refreshReminderDiagnostics")

                        Button(reminderStore.isEnabled ? "Disable Reminder Debug" : "Enable Reminder Debug") {
                            updateReminderEnabled(!reminderStore.isEnabled)
                        }
                        .foregroundStyle(GTPhoneSettingsListColors.rowLabel)
                        .listRowBackground(GTPhoneSettingsListColors.rowBackground)
                        .accessibilityIdentifier("gt.phone.debug.toggleReminder")
                    } header: {
                        settingsSectionHeader("Notification Debug")
                    }
                }

                Section {
                    Toggle(isOn: reminderEnabledBinding) {
                        Text(GTCopy.settingsReminderToggle(lang))
                            .foregroundStyle(GTPhoneSettingsListColors.rowLabel)
                    }
                    .tint(GTPhoneSettingsListColors.controlAccent)
                    .listRowBackground(GTPhoneSettingsListColors.rowBackground)
                    .accessibilityIdentifier("gt.phone.reminderEnabledToggle")

                    Picker(selection: reminderTargetBinding) {
                        Text(GTCopy.settingsReminderTargetBlue(lang)).tag(GTTwilightReminderSettings.Target.blue.rawValue)
                        Text(GTCopy.settingsReminderTargetGolden(lang)).tag(GTTwilightReminderSettings.Target.golden.rawValue)
                    } label: {
                        Text(GTCopy.settingsReminderTarget(lang))
                            .foregroundStyle(GTPhoneSettingsListColors.rowLabel)
                    }
                    .pickerStyle(.menu)
                    .tint(GTPhoneSettingsListColors.controlAccent)
                    .listRowBackground(GTPhoneSettingsListColors.rowBackground)
                    .disabled(!reminderStore.isEnabled)
                    .opacity(reminderStore.isEnabled ? 1 : 0.4)

                    Picker(selection: reminderMinutesBinding) {
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
                    .disabled(!reminderStore.isEnabled)
                    .opacity(reminderStore.isEnabled ? 1 : 0.4)
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
                        .font(.body)
                        .foregroundStyle(GTPhoneSettingsListColors.rowSecondary)
                        .listRowBackground(GTPhoneSettingsListColors.rowBackground)

                    switch model.locationAuthorizationStatus {
                    case .notDetermined:
                        locationActionRow(
                            title: GTCopy.settingsAllowLocation(lang),
                            isAuthorizationRow: true,
                            action: model.requestLocationAccessFromSettings
                        )
                    case .denied, .restricted:
                        Button(GTCopy.settingsOpenSystemSettings(lang)) {
                            model.openSystemSettings()
                        }
                        .foregroundStyle(GTPhoneSettingsListColors.rowLabel)
                        .listRowBackground(GTPhoneSettingsListColors.rowBackground)
                    default:
                        EmptyView()
                    }

                    locationActionRow(
                        title: GTCopy.settingsRefreshLocation(lang),
                        isAuthorizationRow: false,
                        action: model.refreshLocationFromSettings
                    )
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
            .accessibilityIdentifier("gt.phone.settingsSheet")
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
            .task {
                reminderStore.reloadFromPersistentStore()
                guard showsReminderDebugDiagnostics else { return }
                await refreshReminderDiagnostics()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    reminderStore.reloadFromPersistentStore()
                }
                guard showsReminderDebugDiagnostics, phase == .active else { return }
                Task { await refreshReminderDiagnostics() }
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
    private func locationActionRow(title: String, isAuthorizationRow: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .foregroundStyle(GTPhoneSettingsListColors.rowLabel)

                Spacer(minLength: 12)

                if shouldShowLocationFeedback(isAuthorizationRow: isAuthorizationRow),
                   let locationFeedbackText
                {
                    locationFeedbackView(text: locationFeedbackText)
                }
            }
        }
        .listRowBackground(GTPhoneSettingsListColors.rowBackground)
        .disabled(model.isPerformingSettingsLocationAction)
    }

    @ViewBuilder
    private func locationFeedbackView(text: String) -> some View {
        HStack(spacing: 6) {
            switch model.settingsLocationFeedback {
            case .waitingForPermission, .refreshing:
                ProgressView()
                    .controlSize(.small)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(GTPhoneSettingsListColors.successText)
            case .denied, .restricted, .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(GTPhoneSettingsListColors.errorText)
            case .idle:
                EmptyView()
            }

            Text(text)
                .font(.footnote)
                .foregroundStyle(locationFeedbackColor)
                .multilineTextAlignment(.trailing)
        }
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

    private func debugMetricRow(title: String, value: String, identifier: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .foregroundStyle(GTPhoneSettingsListColors.rowLabel)
            Spacer(minLength: 12)
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundStyle(GTPhoneSettingsListColors.rowSecondary)
                .accessibilityIdentifier(identifier)
                .accessibilityLabel(identifier)
                .accessibilityValue(value)
        }
        .listRowBackground(GTPhoneSettingsListColors.rowBackground)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(title)
        .accessibilityValue(value)
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

    private func updateReminderEnabled(_ enabled: Bool) {
        reminderStore.setEnabled(enabled)
        if enabled {
            Task { @MainActor in
                _ = await TwilightReminderScheduler.shared.requestAuthorizationIfNeeded()
                model.refreshTwilightReminderSchedule()
                await refreshReminderDiagnostics()
            }
        } else {
            model.refreshTwilightReminderSchedule()
            Task { await refreshReminderDiagnostics() }
        }
    }

    @MainActor
    private func refreshReminderDiagnostics() async {
        let center = UNUserNotificationCenter.current()
        let prefix = GTTwilightReminderSettings.requestIdentifierPrefix
        let pendingCount: Int = await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.filter { $0.identifier.hasPrefix(prefix) }.count)
            }
        }
        let deliveredCount: Int = await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications.filter { $0.request.identifier.hasPrefix(prefix) }.count)
            }
        }
        reminderDebugPendingCount = String(pendingCount)
        reminderDebugDeliveredCount = String(deliveredCount)
        reminderDebugPlanCount = String(
            GTAppGroup.shared.stringArray(forKey: GTTwilightReminderSettings.scheduledIdentifiersKey)?.count ?? 0
        )
    }
}
