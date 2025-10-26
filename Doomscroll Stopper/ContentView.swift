//
//  ContentView.swift
//  Doomscroll Stopper
//
//  Created by Jamie on 24/10/2025.
//

import SwiftUI
import FamilyControls
import DeviceActivity
import ManagedSettings
import UserNotifications

struct ContentView: View {
    // MARK: - State Variables
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false
    @AppStorage("isProtectionEnabled") private var isProtectionEnabled = false
    @State private var selectedApp = FamilyActivitySelection()
    @State private var showingWizard = false
    @State private var wizardStep = 1
    @State private var showingAppPicker = false
    
    // Family Controls authorization
    @StateObject private var authorizationCenter = AuthorizationCenter.shared
    
    // Leaf animation states
    @State private var leafScale: CGFloat = 1.0
    @State private var leafColor: Color = .white
    @State private var leafPulseTimer: Timer?
    @State private var leafHasAppeared = false
    
    // Scene phase monitoring
    @Environment(\.scenePhase) private var scenePhase
    
    // Timer for checking shield expiry
    @State private var shieldCheckTimer: Timer?
    @State private var remainingSeconds: Int = 0
    
    private let appGroupIdentifier = "group.Me.DoomscrollStopper"
    
    var body: some View {
        ZStack {
            // Warm gradient background
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.85, blue: 0.6),
                    Color(red: 1.0, green: 0.7, blue: 0.4),
                    Color(red: 1.0, green: 0.5, blue: 0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            if !hasCompletedSetup {
                wizardView
            } else {
                mainView
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            // Clear any orphaned shields on first launch
            clearOrphanedShields()
        }
        .onChange(of: hasCompletedSetup) { completed in
            if completed {
                // Start leaf animation after setup
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    startLeafAnimation()
                }
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                checkForRestartSignal()
                // Check immediately when app becomes active
                checkAndRemoveExpiredShield()
                startShieldCheckTimer()
            } else if phase == .background {
                stopShieldCheckTimer()
            }
        }
        .onAppear {
            // Timer will be started by startMonitoring() when protection is enabled
        }
        .onDisappear {
            stopShieldCheckTimer()
        }
    }
    
    // MARK: - Main View
    private var mainView: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {
                    // Header with animated leaf
                    VStack(spacing: 20) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 80))
                            .foregroundColor(leafColor)
                            .scaleEffect(leafScale)
                        
                        Text("Doomscroll Stopper")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("Break free from endless scrolling")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(.top, 40)
                    
                    // Status Card
                    VStack(spacing: 20) {
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Protection Status")
                                    .font(.headline)
                                Text(isProtectionEnabled ? "Active - Freeing you from the scroll of doom" : "Inactive")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $isProtectionEnabled)
                                .labelsHidden()
                                .tint(.green)
                        }
                        
                        if isProtectionEnabled {
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "app.fill")
                                        .foregroundColor(.green)
                                    if selectedApp.applicationTokens.count > 0 && selectedApp.categoryTokens.count > 0 {
                                        Text("\(selectedApp.applicationTokens.count) app\(selectedApp.applicationTokens.count == 1 ? "" : "s") + \(selectedApp.categoryTokens.count) categor\(selectedApp.categoryTokens.count == 1 ? "y" : "ies") blocked")
                                            .font(.subheadline)
                                    } else if selectedApp.applicationTokens.count > 0 {
                                        Text("\(selectedApp.applicationTokens.count) app\(selectedApp.applicationTokens.count == 1 ? "" : "s") blocked")
                                            .font(.subheadline)
                                    } else {
                                        Text("\(selectedApp.categoryTokens.count) categor\(selectedApp.categoryTokens.count == 1 ? "y" : "ies") blocked")
                                            .font(.subheadline)
                                    }
                                }
                                
                                HStack {
                                    Image(systemName: "clock.fill")
                                        .foregroundColor(.green)
                                    Text("5-minute wait to access")
                                        .font(.subheadline)
                                }
                            }
                            
                            Divider()
                            
                            // Countdown Timer or Break Complete Message
                            VStack(spacing: 8) {
                                if remainingSeconds > 0 {
                                    Text("Time Remaining")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Text(formatTime(remainingSeconds))
                                        .font(.system(size: 48, weight: .bold, design: .rounded))
                                        .foregroundColor(.orange)
                                        .monospacedDigit()
                                } else {
                                    // Break complete state
                                    VStack(spacing: 16) {
                                        Text("🌱")
                                            .font(.system(size: 60))
                                        
                                        Text("Break Complete!")
                                            .font(.system(size: 28, weight: .bold))
                                            .foregroundColor(.green)
                                        
                                        Text("You stayed away for 5 minutes")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        
                                        // Action buttons
                                        VStack(spacing: 12) {
                                            Button(action: {
                                                // Restart protection for another 5 minutes
                                                startMonitoring()
                                            }) {
                                                HStack {
                                                    Image(systemName: "arrow.clockwise")
                                                    Text("Go Another 5 Minutes")
                                                }
                                                .font(.headline)
                                                .foregroundColor(.white)
                                                .frame(maxWidth: .infinity)
                                                .padding()
                                                .background(Color.green)
                                                .cornerRadius(12)
                                            }
                                            
                                            Button(action: {
                                                wizardStep = 2
                                                showingWizard = true
                                            }) {
                                                HStack {
                                                    Image(systemName: "arrow.triangle.2.circlepath")
                                                    Text("Change Apps")
                                                }
                                                .font(.subheadline)
                                                .foregroundColor(.blue)
                                                .frame(maxWidth: .infinity)
                                                .padding()
                                                .background(Color.blue.opacity(0.1))
                                                .cornerRadius(12)
                                            }
                                        }
                                        .padding(.top, 8)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.1), radius: 10)
                    .padding(.horizontal)
                    
                    // How It Works
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How It Works")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        FeatureRow(icon: "leaf.fill", title: "Pick Your Apps", description: "Choose one or more apps you want to limit")
                        FeatureRow(icon: "shield.fill", title: "Instant Block", description: "Apps are blocked immediately when you try to open them")
                        FeatureRow(icon: "clock.fill", title: "5-Minute Cooldown", description: "Wait 5 minutes before you can access them again")
                    }
                    .padding()
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(16)
                    .padding(.horizontal)
                    
                    // Reconfigure Button
                    Button(action: {
                        wizardStep = 1
                        showingWizard = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Reconfigure")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.3))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            // Check for expired shield when main view appears
            if isProtectionEnabled {
                checkIfShieldExpiredAndPrompt()
            }
        }
        .fullScreenCover(isPresented: $showingWizard) {
            wizardView
                .transition(.opacity)
        }
        .onChange(of: isProtectionEnabled) { enabled in
            if enabled {
                startMonitoring()
            } else {
                stopMonitoring()
                // Reset to wizard when protection is disabled
                hasCompletedSetup = false
                wizardStep = 1
                selectedApp = FamilyActivitySelection()
            }
        }
    }
    
    // MARK: - Wizard View
    private var wizardView: some View {
        ZStack {
            // Same warm gradient
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.85, blue: 0.6),
                    Color(red: 1.0, green: 0.7, blue: 0.4),
                    Color(red: 1.0, green: 0.5, blue: 0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Close button (only if already completed setup)
                if hasCompletedSetup {
                    HStack {
                        Spacer()
                        Button(action: { showingWizard = false }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white.opacity(0.9))
                                .padding()
                        }
                    }
                }
                
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                    
                    Text("Stop Doomscrolling")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.top, hasCompletedSetup ? 0 : 60)
                .padding(.bottom, 40)
                
                // Progress dots
                HStack(spacing: 12) {
                    ForEach(1...3, id: \.self) { step in
                        Circle()
                            .fill(step == wizardStep ? Color.white : Color.white.opacity(0.3))
                            .frame(width: 12, height: 12)
                    }
                }
                .padding(.bottom, 8)
                
                Text("Step \(wizardStep) of 3")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.bottom, 32)
                
                // Wizard content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        if wizardStep == 1 {
                            step1View
                        } else if wizardStep == 2 {
                            step2View
                        } else {
                            step3View
                        }
                    }
                    .padding(.horizontal, 24)
                }
                
                // Navigation buttons
                HStack(spacing: 16) {
                    if wizardStep > 1 {
                        Button(action: { withAnimation { wizardStep -= 1 } }) {
                            HStack {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white.opacity(0.2))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                    
                    Button(action: {
                        if wizardStep < 3 {
                            withAnimation { wizardStep += 1 }
                        } else {
                            // Complete setup
                            activateProtection()
                        }
                    }) {
                        HStack {
                            Text(wizardStep == 3 ? "Activate Protection" : "Next")
                            if wizardStep < 3 {
                                Image(systemName: "chevron.right")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .foregroundColor(Color.orange)
                        .cornerRadius(12)
                        .fontWeight(.semibold)
                    }
                    .disabled(wizardStep == 2 && selectedApp.applicationTokens.isEmpty && selectedApp.categoryTokens.isEmpty)
                    .opacity(wizardStep == 2 && selectedApp.applicationTokens.isEmpty && selectedApp.categoryTokens.isEmpty ? 0.5 : 1)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }
        .sheet(isPresented: $showingAppPicker) {
            NavigationView {
                VStack {
                    if #available(iOS 16.0, *) {
                        FamilyActivityPicker(selection: $selectedApp)
                            .navigationTitle("Select App to Monitor")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Done") { showingAppPicker = false }
                    }
                }
            }
        }
    }
    
    // MARK: - Wizard Steps
    private var step1View: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Help me! I want to stop doomscrolling!")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Here's how it works:")
                    .font(.body)
                    .foregroundColor(.orange)
                
                HStack(alignment: .top, spacing: 12) {
                    Text("🌱")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Choose one or more apps")
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                        Text("Pick the apps that pull you in the most")
                            .font(.subheadline)
                            .foregroundColor(.orange.opacity(0.8))
                    }
                }
                
                HStack(alignment: .top, spacing: 12) {
                    Text("🛡️")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Instant block")
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                        Text("The app is blocked immediately when you try to open it")
                            .font(.subheadline)
                            .foregroundColor(.orange.opacity(0.8))
                    }
                }
                
                HStack(alignment: .top, spacing: 12) {
                    Text("⏱️")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("5-minute cooldown")
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                        Text("You must wait 5 minutes before accessing the app again")
                            .font(.subheadline)
                            .foregroundColor(.orange.opacity(0.8))
                    }
                }
            }
            .padding()
            .background(Color.white)
            .cornerRadius(12)
            
            Text("This is a voluntary tool to help you build healthier habits. You can turn it off anytime.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.7))
                .padding(.top, 8)
        }
        .onAppear {
            // Request notification permission at Step 1 (like normal apps)
            requestNotificationPermission()
        }
    }
    
    private var step2View: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Which apps keep pulling you in?")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Select one or more apps you want help with:")
                .font(.body)
                .foregroundColor(.white.opacity(0.9))
            
            VStack(spacing: 12) {
                Button(action: {
                    // Request authorization before showing picker
                    Task {
                        do {
                            print("[DOOMSCROLL] Requesting Family Controls authorization...")
                            try await authorizationCenter.requestAuthorization(for: .individual)
                            print("[DOOMSCROLL] ✓ Family Controls authorization granted")
                            
                            // Show picker after authorization
                            await MainActor.run {
                                showingAppPicker = true
                            }
                        } catch {
                            print("[DOOMSCROLL] ✗ Family Controls authorization failed: \(error)")
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: "app.badge.checkmark")
                            .font(.title3)
                        Text(selectedApp.applicationTokens.isEmpty ? "Tap to select apps" : "Apps Selected ✓")
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding()
                    .background(Color.white.opacity(0.2))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                
                if !selectedApp.applicationTokens.isEmpty || !selectedApp.categoryTokens.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        let totalCount = selectedApp.applicationTokens.count + selectedApp.categoryTokens.count
                        Text("\(totalCount) item\(totalCount == 1 ? "" : "s") selected")
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(.top, 4)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("ℹ️ You'll be asked to grant Screen Time permission when you tap to select apps. This is required for blocking to work.")
                    .font(.footnote)
                    .foregroundColor(.orange)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(8)
                
                Text("💡 Tip: Start with your biggest distractions. You can always change this later.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.top, 8)
        }
    }
    
    private var step3View: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Ready to break free?")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 16) {
                Text("You're all set!")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "app.fill")
                            .foregroundColor(.orange)
                        if selectedApp.applicationTokens.count > 0 && selectedApp.categoryTokens.count > 0 {
                            Text("Selected: \(selectedApp.applicationTokens.count) app\(selectedApp.applicationTokens.count == 1 ? "" : "s") + \(selectedApp.categoryTokens.count) categor\(selectedApp.categoryTokens.count == 1 ? "y" : "ies")")
                                .foregroundColor(.orange)
                        } else if selectedApp.applicationTokens.count > 0 {
                            Text("Selected: \(selectedApp.applicationTokens.count) app\(selectedApp.applicationTokens.count == 1 ? "" : "s")")
                                .foregroundColor(.orange)
                        } else {
                            Text("Selected: \(selectedApp.categoryTokens.count) categor\(selectedApp.categoryTokens.count == 1 ? "y" : "ies")")
                                .foregroundColor(.orange)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        Image(systemName: "shield.fill")
                            .foregroundColor(.orange)
                        Text("Block: Instant when activated")
                            .foregroundColor(.orange)
                    }
                    
                    HStack(spacing: 12) {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.orange)
                        Text("Cooldown: 5 minutes before access")
                            .foregroundColor(.orange)
                    }
                }
                .padding()
                .background(Color.white)
                .cornerRadius(12)
            }
            
            Text("You can disable this feature anytime from the main screen.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.7))
                .padding(.top, 8)
        }
    }
    
    // MARK: - Helper Functions
    private func activateProtection() {
        // Immediate state changes for fast transition
        hasCompletedSetup = true
        isProtectionEnabled = true
        wizardStep = 1
        
        // Save to App Group
        saveToAppGroup()
        
        // Start monitoring immediately
        startMonitoring()
        
        // Dismiss wizard and start animation quickly
        DispatchQueue.main.async {
            showingWizard = false
            // Start leaf animation immediately after wizard dismisses
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                startLeafAnimation()
            }
        }
    }
    
    private func saveToAppGroup() {
        guard let suite = UserDefaults(suiteName: appGroupIdentifier) else {
            print("[DOOMSCROLL] ERROR: Could not access App Group")
            return
        }
        
        print("[DOOMSCROLL] Saving to App Group...")
        print("[DOOMSCROLL] - Apps selected: \(selectedApp.applicationTokens.count)")
        print("[DOOMSCROLL] - Categories selected: \(selectedApp.categoryTokens.count)")
        print("[DOOMSCROLL] - Protection enabled: \(isProtectionEnabled)")
        
        if let data = try? JSONEncoder().encode(selectedApp) {
            suite.set(data, forKey: "selectedApp")
            print("[DOOMSCROLL] - Saved selectedApp data (\(data.count) bytes)")
        } else {
            print("[DOOMSCROLL] ERROR: Failed to encode selectedApp")
        }
        
        suite.set(isProtectionEnabled, forKey: "isProtectionEnabled")
        suite.synchronize()
        
        print("[DOOMSCROLL] App Group save complete")
    }
    
    private func startMonitoring() {
        guard #available(iOS 16.0, *) else {
            print("[DOOMSCROLL] ERROR: iOS 16.0+ required")
            return
        }
        
        guard !selectedApp.applicationTokens.isEmpty || !selectedApp.categoryTokens.isEmpty else {
            print("[DOOMSCROLL] ERROR: No apps or categories selected!")
            return
        }
        
        print("[DOOMSCROLL] 📊 ========================================")
        print("[DOOMSCROLL] 📊 Starting instant block protection...")
        print("[DOOMSCROLL] 📊 - Blocking \(selectedApp.applicationTokens.count) app(s)")
        print("[DOOMSCROLL] 📊 - Blocking \(selectedApp.categoryTokens.count) category(ies)")
        
        // Use the DEFAULT store (not named) - this is what Nudgetronic does
        let store = ManagedSettingsStore()
        
        // IMPORTANT: Clear any previous shields first (in case user changed apps)
        print("[DOOMSCROLL] 📊 Clearing any previous shields...")
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomainCategories = nil
        
        print("[DOOMSCROLL] ✅ Cleared any previous shields")
        
        // Now apply the new shields (apps and/or categories)
        print("[DOOMSCROLL] 📊 Applying new shields...")
        if !selectedApp.applicationTokens.isEmpty {
            store.shield.applications = selectedApp.applicationTokens
            print("[DOOMSCROLL] ✅ Applied app shields")
        }
        if !selectedApp.categoryTokens.isEmpty {
            store.shield.applicationCategories = .specific(selectedApp.categoryTokens)
            print("[DOOMSCROLL] ✅ Applied category shields")
        }
        
        // Save block start time
        let startTime = Date().timeIntervalSince1970
        if let suite = UserDefaults(suiteName: appGroupIdentifier) {
            suite.set(startTime, forKey: "blockStartTime")
            suite.synchronize()
            print("[DOOMSCROLL] ✅ Saved blockStartTime: \(startTime)")
        }
        
        print("[DOOMSCROLL] ✅ Apps/categories blocked instantly!")
        print("[DOOMSCROLL] ✅ Shield is now active and persistent")
        print("[DOOMSCROLL] 📊 Shield will auto-clear after 5 minutes (300 seconds)")
        
        // Start DeviceActivity monitoring (needed for visual state management)
        // We use an all-day schedule like Nudgetronic, but without threshold events
        let center = DeviceActivityCenter()
        
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        
        print("[DOOMSCROLL] 📊 Starting DeviceActivity monitoring for visual state management...")
        
        do {
            try center.startMonitoring(
                DeviceActivityName("doomscrollProtection"),
                during: schedule
            )
            print("[DOOMSCROLL] ✅ DeviceActivity monitoring started")
            print("[DOOMSCROLL] 📊 Stopping/restarting this will refresh visual state")
        } catch {
            print("[DOOMSCROLL] ❌ DeviceActivity monitoring failed: \(error)")
        }
        
        // Schedule a background notification for 5 minutes to trigger visual refresh
        scheduleVisualRefreshNotification()
        
        // Start the timer to check for shield expiry
        startShieldCheckTimer()
    }
    
    private func stopMonitoring() {
        guard #available(iOS 16.0, *) else { return }
        
        print("[DOOMSCROLL] 📊 stopMonitoring() called - clearing protection...")
        
        // Stop DeviceActivity monitoring FIRST (triggers visual refresh)
        let center = DeviceActivityCenter()
        print("[DOOMSCROLL] 📊 Stopping DeviceActivity monitoring...")
        center.stopMonitoring([DeviceActivityName("doomscrollProtection")])
        print("[DOOMSCROLL] ✅ Monitoring stopped")
        
        // Clear shields using the DEFAULT store (matching Nudgetronic)
        let store = ManagedSettingsStore()
        print("[DOOMSCROLL] 📊 Clearing shields from default store...")
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomainCategories = nil
        
        print("[DOOMSCROLL] ✅ Protection stopped - shield cleared")
        print("[DOOMSCROLL] 📊 Apps should now appear unblocked in UI")
    }
    
    private func startLeafAnimation() {
        guard !leafHasAppeared else { return }
        
        // Sprout animation
        leafScale = 0.3
        withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
            leafScale = 1.0
        }
        leafHasAppeared = true
        
        // Start pulse after sprout
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            startLeafPulse()
        }
    }
    
    private func startLeafPulse() {
        leafPulseTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 1.0)) {
                if self.leafScale <= 1.0 {
                    self.leafScale = 1.3
                    self.leafColor = Color(red: 0.2, green: 0.8, blue: 0.3)
                } else {
                    self.leafScale = 0.75
                    self.leafColor = .white
                }
            }
        }
        // Start with first pulse
        withAnimation(.easeInOut(duration: 1.0)) {
            leafScale = 0.75
            leafColor = .white
        }
    }
    
    private func checkForRestartSignal() {
        guard let suite = UserDefaults(suiteName: appGroupIdentifier) else { return }
        
        let shouldRestart = suite.bool(forKey: "restartMonitoring")
        
        print("[DOOMSCROLL] 📊 Checking for restart signal...")
        print("[DOOMSCROLL] 📊 shouldRestart: \(shouldRestart), isProtectionEnabled: \(isProtectionEnabled)")
        
        if shouldRestart && isProtectionEnabled {
            print("[DOOMSCROLL] ✅ Restart signal detected - restarting monitoring")
            
            // Clear the flag
            suite.set(false, forKey: "restartMonitoring")
            suite.synchronize()
            print("[DOOMSCROLL] 📊 Cleared restart flag")
            
            // Restart monitoring (this will start a new DeviceActivity session)
            print("[DOOMSCROLL] 📊 Calling startMonitoring() to restart...")
            startMonitoring()
            print("[DOOMSCROLL] ✅ Monitoring restarted successfully")
        } else {
            print("[DOOMSCROLL] 📊 No restart needed")
        }
    }
    
    private func startShieldCheckTimer() {
        // Stop any existing timer
        stopShieldCheckTimer()
        
        guard isProtectionEnabled else { return }
        
        print("[DOOMSCROLL] Starting shield check timer")
        
        // Update countdown immediately
        updateCountdown()
        
        // Check every 1 second for smooth countdown
        shieldCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] _ in
            self.updateCountdown()
            
            // Check for expiry every update
            if self.remainingSeconds <= 0 {
                self.checkAndRemoveExpiredShield()
            }
        }
    }
    
    private func stopShieldCheckTimer() {
        shieldCheckTimer?.invalidate()
        shieldCheckTimer = nil
    }
    
    private func checkAndRemoveExpiredShield() {
        guard let suite = UserDefaults(suiteName: appGroupIdentifier) else { return }
        
        let blockStartTime = suite.double(forKey: "blockStartTime")
        
        // If no block start time, don't do anything
        guard blockStartTime > 0 else {
            print("[DOOMSCROLL] No block start time set")
            return
        }
        
        let currentTime = Date().timeIntervalSince1970
        let elapsedSeconds = currentTime - blockStartTime
        
        print("[DOOMSCROLL] Shield check: \(Int(elapsedSeconds)) seconds elapsed (need 300)")
        
        // If more than 5 minutes have passed, clear the shield
        if elapsedSeconds >= 300 {
            print("[DOOMSCROLL] ⏰ 5 minutes elapsed - clearing shield from main app")
            
            // Stop DeviceActivity monitoring FIRST (triggers visual refresh)
            let center = DeviceActivityCenter()
            print("[DOOMSCROLL] 📊 Stopping DeviceActivity monitoring to refresh visual state...")
            center.stopMonitoring([DeviceActivityName("doomscrollProtection")])
            print("[DOOMSCROLL] ✅ Monitoring stopped - visual state should refresh now")
            
            // Clear shields
            let store = ManagedSettingsStore()
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            print("[DOOMSCROLL] ✅ Shields cleared")
            
            // Mark that shield was cleared (don't reset to current time, set to 0)
            suite.set(0, forKey: "blockStartTime")
            suite.synchronize()
            
            print("[DOOMSCROLL] ✅ Shield cleared - apps accessible again")
            print("[DOOMSCROLL] 📊 Apps should now appear UNBLOCKED on home screen")
            
            // Stop the timer since shield is cleared
            stopShieldCheckTimer()
            
            // DON'T turn off protection toggle - keep user on Protection Status screen
            // They can choose to go another round or change apps
            print("[DOOMSCROLL] 📊 Break complete - staying on Protection Status screen")
            print("[DOOMSCROLL] 📊 User can restart or change apps from UI")
        }
    }
    
    private func checkIfShieldExpiredAndPrompt() {
        guard let suite = UserDefaults(suiteName: appGroupIdentifier) else { return }
        
        let blockStartTime = suite.double(forKey: "blockStartTime")
        guard blockStartTime > 0 else { return }
        
        let currentTime = Date().timeIntervalSince1970
        let elapsedSeconds = currentTime - blockStartTime
        
        // If 5 minutes have passed, automatically clear shield
        if elapsedSeconds >= 300 {
            print("[DOOMSCROLL] 5 minutes elapsed - automatically clearing shield")
            clearShield()
        }
    }
    
    private func clearShield() {
        print("[DOOMSCROLL] Clearing shield - apps now accessible")
        
        let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("doomscroll"))
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        
        if let suite = UserDefaults(suiteName: appGroupIdentifier) {
            suite.set(0, forKey: "blockStartTime")
            suite.synchronize()
        }
        
        stopShieldCheckTimer()
        remainingSeconds = 0
        print("[DOOMSCROLL] ✓ Shield cleared - apps accessible")
    }
    
    private func updateCountdown() {
        guard let suite = UserDefaults(suiteName: appGroupIdentifier) else { return }
        
        let blockStartTime = suite.double(forKey: "blockStartTime")
        guard blockStartTime > 0 else {
            remainingSeconds = 0
            return
        }
        
        let currentTime = Date().timeIntervalSince1970
        let elapsedSeconds = currentTime - blockStartTime
        let remaining = max(0, 300 - Int(elapsedSeconds))
        
        remainingSeconds = remaining
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
    
    private func clearOrphanedShields() {
        // On first launch, clear any shields that might be left from previous installs
        // This prevents shields from persisting after app deletion
        if !hasCompletedSetup && !isProtectionEnabled {
            print("[DOOMSCROLL] First launch detected - clearing any orphaned shields")
            let store = ManagedSettingsStore()
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomainCategories = nil
            
            // Also clear App Group data
            if let suite = UserDefaults(suiteName: appGroupIdentifier) {
                suite.set(0, forKey: "blockStartTime")
                suite.synchronize()
            }
            
            print("[DOOMSCROLL] ✓ Orphaned shields cleared")
        }
    }
    
    private func requestNotificationPermission() {
        print("[DOOMSCROLL] 📊 Requesting notification permission at Step 1...")
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("[DOOMSCROLL] ✅ Notification permission granted")
            } else {
                print("[DOOMSCROLL] ⚠️ Notification permission denied: \(error?.localizedDescription ?? "unknown")")
            }
        }
    }
    
    private func scheduleVisualRefreshNotification() {
        print("[DOOMSCROLL] 📊 Scheduling break complete notification for 5 minutes")
        
        // Cancel any existing notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Break complete! 🌱"
        content.body = "Your doomscroll break is over. Apps are now accessible."
        content.sound = .default
        
        // Trigger after 5 minutes (300 seconds)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 300, repeats: false)
        
        // Create request
        let request = UNNotificationRequest(
            identifier: "doomscroll.visual.refresh",
            content: content,
            trigger: trigger
        )
        
        // Schedule notification
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[DOOMSCROLL] ❌ Failed to schedule notification: \(error)")
            } else {
                print("[DOOMSCROLL] ✅ Notification scheduled for 5 minutes from now")
                print("[DOOMSCROLL] 📊 This should trigger iOS to refresh home screen state")
            }
        }
    }
}

// MARK: - Supporting Views
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }
}

#Preview {
    ContentView()
}
