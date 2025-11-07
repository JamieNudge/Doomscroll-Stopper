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
    @AppStorage("blockMode") private var blockMode: String = "instant" // "instant" or "delayed"
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
    @State private var allowanceSeconds: Int = 0  // For delayed mode allowance countdown
    
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
                // Update shield status immediately when app becomes active
                updateCountdown()
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
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Text(isProtectionEnabled ? "Active - Freeing you from the scroll of doom" : "Inactive")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $isProtectionEnabled)
                                .labelsHidden()
                                .tint(.green)
                                .scaleEffect(1.2)
                        }
                        
                        if isProtectionEnabled {
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Image(systemName: "app.fill")
                                        .foregroundColor(.green)
                                        .font(.title3)
                                    Text(statusItemsText())
                                        .font(.body)
                                }
                                
                                HStack {
                                    Image(systemName: "clock.fill")
                                        .foregroundColor(.green)
                                        .font(.title3)
                                    Text(blockMode == "instant" ? "5-minute wait to access" : "5 min use, then 5 min wait")
                                        .font(.body)
                                }
                            }
                            
                            // Helpful note about visual state
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.blue)
                                        .font(.body)
                                    Text("Apps will stay dimmed after the timer expires until you tap them. Gives you a chance to wait a little longer if you like.")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.top, 8)
                            
                            Divider()
                            
                            // Countdown Timer, Allowance Timer, or Break Complete Message
                            VStack(spacing: 12) {
                                if blockMode == "delayed" && allowanceSeconds > 0 && remainingSeconds == 0 {
                                    // Delayed mode - allowance countdown
                                    VStack(spacing: 20) {
                                        Text("⏳")
                                            .font(.system(size: 80))
                                        
                                        Text("Time Until Block")
                                            .font(.body)
                                            .foregroundColor(.secondary)
                                        
                                        Text(formatTime(allowanceSeconds))
                                            .font(.system(size: 60, weight: .bold, design: .rounded))
                                            .foregroundColor(.blue)
                                            .monospacedDigit()
                                        
                                        Text("You have \(formatTime(allowanceSeconds)) to use your selected app")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal)
                                    }
                                } else if remainingSeconds > 0 {
                                    // Active block - show countdown
                                    Text("Time Remaining")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                    
                                    Text(formatTime(remainingSeconds))
                                        .font(.system(size: 60, weight: .bold, design: .rounded))
                                        .foregroundColor(.orange)
                                        .monospacedDigit()
                                } else {
                                    // Break complete state (instant mode or delayed mode after cooldown)
                                    VStack(spacing: 20) {
                                        Text("🌱")
                                            .font(.system(size: 80))
                                        
                                        Text("Break Complete!")
                                            .font(.system(size: 34, weight: .bold))
                                            .foregroundColor(.green)
                                        
                                        Text(blockMode == "instant" ? "You stayed away for 5 minutes" : "Cooldown complete!")
                                            .font(.body)
                                            .foregroundColor(.secondary)
                                        
                                        // Action buttons
                                        VStack(spacing: 12) {
                                            Button(action: {
                                                // Restart protection for another round
                                                startMonitoring()
                                            }) {
                                                HStack {
                                                    Image(systemName: "arrow.clockwise")
                                                    Text(blockMode == "instant" ? "Go Another 5 Minutes" : "Start Another Round")
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
                        FeatureRow(icon: "shield.fill", 
                                 title: blockMode == "instant" ? "Instant Block" : "5-Minute Allowance",
                                 description: blockMode == "instant" ? "Apps are blocked immediately when you try to open them" : "5-minute countdown starts when activated")
                        FeatureRow(icon: "clock.fill", 
                                 title: "5-Minute Block",
                                 description: blockMode == "instant" ? "Wait 5 minutes before you can access them again" : "After allowance expires, apps blocked for 5 minutes")
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
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .onAppear {
            // Load previously selected app
            loadSelectedApp()
            
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
                // Reset to wizard when protection is disabled (but keep selectedApp)
                hasCompletedSetup = false
                wizardStep = 1
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
                        .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.3))
                    
                    Text("Doomscroll Stopper")
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
                            .background(Color.white)
                            .foregroundColor(Color.orange)
                            .cornerRadius(12)
                            .fontWeight(.semibold)
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
                    .disabled(wizardStep == 2 && selectedApp.applicationTokens.isEmpty && selectedApp.categoryTokens.isEmpty && selectedApp.webDomainTokens.isEmpty)
                    .opacity(wizardStep == 2 && selectedApp.applicationTokens.isEmpty && selectedApp.categoryTokens.isEmpty && selectedApp.webDomainTokens.isEmpty ? 0.7 : 1)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
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
            
            Text("Choose your blocking mode:")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.top, 8)
            
            // Blocking Mode Selection
            VStack(spacing: 12) {
                // Instant Block Option
                Button(action: {
                    blockMode = "instant"
                }) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: blockMode == "instant" ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundColor(blockMode == "instant" ? .green : .orange)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Instant Block")
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                            Text("App blocked immediately for 5 minutes")
                                .font(.subheadline)
                                .foregroundColor(.orange.opacity(0.8))
                        }
                        Spacer()
                    }
                    .padding()
                    .background(blockMode == "instant" ? Color.white : Color.white.opacity(0.5))
                    .cornerRadius(12)
                }
                
                // Delayed Block Option
                Button(action: {
                    blockMode = "delayed"
                }) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: blockMode == "delayed" ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundColor(blockMode == "delayed" ? .green : .orange)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("5 Minutes Use, Then Block")
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                            Text("5-minute countdown starts when activated, then blocked for 5 minutes")
                                .font(.subheadline)
                                .foregroundColor(.orange.opacity(0.8))
                        }
                        Spacer()
                    }
                    .padding()
                    .background(blockMode == "delayed" ? Color.white : Color.white.opacity(0.5))
                    .cornerRadius(12)
                }
            }
            
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
                    .background(Color.white)
                    .foregroundColor(Color.orange)
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
            
            VStack(alignment: .leading, spacing: 12) {
                Text("ℹ️ You'll be asked to grant Screen Time permission when you tap to select apps. This is required for blocking to work.")
                    .font(.footnote)
                    .foregroundColor(.orange)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white)
                    .cornerRadius(8)
                
                Text("💡 Tip: Start with your biggest distractions. You can always change this later.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.7))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
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
                        Text(step3SelectionText())
                            .foregroundColor(.orange)
                    }
                    
                    HStack(spacing: 12) {
                        Image(systemName: "shield.fill")
                            .foregroundColor(.orange)
                        Text(blockMode == "instant" ? "Block: Instant when activated" : "Allowance: 5-minute countdown")
                            .foregroundColor(.orange)
                    }
                    
                    HStack(spacing: 12) {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.orange)
                        Text(blockMode == "instant" ? "Block: 5 minutes before access" : "Block: 5 minutes after allowance")
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
    private func step3SelectionText() -> String {
        var parts: [String] = []
        
        let appCount = selectedApp.applicationTokens.count
        let catCount = selectedApp.categoryTokens.count
        let webCount = selectedApp.webDomainTokens.count
        
        if appCount > 0 {
            parts.append("\(appCount) app\(appCount == 1 ? "" : "s")")
        }
        if catCount > 0 {
            parts.append("\(catCount) categor\(catCount == 1 ? "y" : "ies")")
        }
        if webCount > 0 {
            parts.append("\(webCount) website\(webCount == 1 ? "" : "s")")
        }
        
        if parts.isEmpty {
            return "Selected: Nothing"
        } else if parts.count == 1 {
            return "Selected: \(parts[0])"
        } else if parts.count == 2 {
            return "Selected: \(parts[0]) + \(parts[1])"
        } else {
            return "Selected: \(parts[0]) + \(parts[1]) + \(parts[2])"
        }
    }
    
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
    
    private func statusItemsText() -> String {
        var parts: [String] = []
        
        let appCount = selectedApp.applicationTokens.count
        let catCount = selectedApp.categoryTokens.count
        let webCount = selectedApp.webDomainTokens.count
        
        if appCount > 0 {
            parts.append("\(appCount) app\(appCount == 1 ? "" : "s")")
        }
        if catCount > 0 {
            parts.append("\(catCount) categor\(catCount == 1 ? "y" : "ies")")
        }
        if webCount > 0 {
            parts.append("\(webCount) website\(webCount == 1 ? "" : "s")")
        }
        
        // Determine status text based on mode and current state
        let statusWord: String
        if blockMode == "delayed" && allowanceSeconds > 0 {
            // During allowance period - not blocked yet
            statusWord = "selected for block"
        } else {
            // Instant mode or during block period
            statusWord = "blocked"
        }
        
        if parts.isEmpty {
            return "Nothing \(statusWord)"
        } else if parts.count == 1 {
            return "\(parts[0]) \(statusWord)"
        } else if parts.count == 2 {
            return "\(parts[0]) + \(parts[1]) \(statusWord)"
        } else {
            return "\(parts[0]) + \(parts[1]) + \(parts[2]) \(statusWord)"
        }
    }
    
    private func blockedItemsText() -> String {
        var parts: [String] = []
        
        let appCount = selectedApp.applicationTokens.count
        let catCount = selectedApp.categoryTokens.count
        let webCount = selectedApp.webDomainTokens.count
        
        if appCount > 0 {
            parts.append("\(appCount) app\(appCount == 1 ? "" : "s")")
        }
        if catCount > 0 {
            parts.append("\(catCount) categor\(catCount == 1 ? "y" : "ies")")
        }
        if webCount > 0 {
            parts.append("\(webCount) website\(webCount == 1 ? "" : "s")")
        }
        
        if parts.isEmpty {
            return "Nothing blocked"
        } else if parts.count == 1 {
            return "\(parts[0]) blocked"
        } else if parts.count == 2 {
            return "\(parts[0]) + \(parts[1]) blocked"
        } else {
            return "\(parts[0]) + \(parts[1]) + \(parts[2]) blocked"
        }
    }
    
    private func loadSelectedApp() {
        guard let suite = UserDefaults(suiteName: appGroupIdentifier),
              let data = suite.data(forKey: "selectedApp"),
              let loadedSelection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            print("[DOOMSCROLL] No previous app selection found")
            return
        }
        
        selectedApp = loadedSelection
        print("[DOOMSCROLL] ✓ Loaded previous app selection: \(selectedApp.applicationTokens.count) app(s)")
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
        print("[DOOMSCROLL] - Block mode: \(blockMode)")
        
        if let data = try? JSONEncoder().encode(selectedApp) {
            suite.set(data, forKey: "selectedApp")
            print("[DOOMSCROLL] - Saved selectedApp data (\(data.count) bytes)")
        } else {
            print("[DOOMSCROLL] ERROR: Failed to encode selectedApp")
        }
        
        suite.set(isProtectionEnabled, forKey: "isProtectionEnabled")
        suite.set(blockMode, forKey: "blockMode")
        suite.synchronize()
        
        print("[DOOMSCROLL] App Group save complete")
    }
    
    private func startMonitoring() {
        guard #available(iOS 16.0, *) else {
            print("[DOOMSCROLL] ERROR: iOS 16.0+ required")
            return
        }
        
        guard !selectedApp.applicationTokens.isEmpty || !selectedApp.categoryTokens.isEmpty || !selectedApp.webDomainTokens.isEmpty else {
            print("[DOOMSCROLL] ERROR: No apps, categories, or web domains selected!")
            return
        }
        
        print("[DOOMSCROLL] 📊 ========================================")
        print("[DOOMSCROLL] 📊 Starting protection in \(blockMode) mode...")
        print("[DOOMSCROLL] 📊 - Monitoring \(selectedApp.applicationTokens.count) app(s)")
        print("[DOOMSCROLL] 📊 - Monitoring \(selectedApp.categoryTokens.count) category(ies)")
        print("[DOOMSCROLL] 📊 - Monitoring \(selectedApp.webDomainTokens.count) web domain(s)")
        
        let store = ManagedSettingsStore()
        let center = DeviceActivityCenter()
        
        // Always clear previous shields first
        print("[DOOMSCROLL] 📊 Clearing any previous shields...")
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomainCategories = nil
        store.shield.webDomains = nil
        print("[DOOMSCROLL] ✅ Cleared any previous shields")
        
        if blockMode == "instant" {
            // INSTANT BLOCK MODE: Apply shields immediately
            print("[DOOMSCROLL] 📊 Mode: INSTANT BLOCK - Applying shields now...")
            
            // Save block start time FIRST (before applying shields)
            let startTime = Date().timeIntervalSince1970
            if let suite = UserDefaults(suiteName: appGroupIdentifier) {
                suite.set(startTime, forKey: "blockStartTime")
                suite.synchronize()
                print("[DOOMSCROLL] ✅ Saved blockStartTime: \(startTime)")
            }
            
            // Small delay to ensure UserDefaults sync completes
            Thread.sleep(forTimeInterval: 0.1)
            
            // Now apply shields (shield will read the blockStartTime we just set)
            if !selectedApp.applicationTokens.isEmpty {
                store.shield.applications = selectedApp.applicationTokens
                print("[DOOMSCROLL] ✅ Applied app shields")
            }
            if !selectedApp.categoryTokens.isEmpty {
                store.shield.applicationCategories = .specific(selectedApp.categoryTokens)
                print("[DOOMSCROLL] ✅ Applied category shields")
            }
            if !selectedApp.webDomainTokens.isEmpty {
                store.shield.webDomains = selectedApp.webDomainTokens
                print("[DOOMSCROLL] ✅ Applied web domain shields")
            }
            
            print("[DOOMSCROLL] ✅ Apps blocked instantly! Shield will auto-clear after 5 minutes")
            
            // Start simple monitoring for visual state management (no thresholds)
            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(hour: 0, minute: 0),
                intervalEnd: DateComponents(hour: 23, minute: 59),
                repeats: true
            )
            
            do {
                try center.startMonitoring(
                    DeviceActivityName("doomscrollProtection"),
                    during: schedule
                )
                print("[DOOMSCROLL] ✅ DeviceActivity monitoring started (visual state only)")
            } catch {
                print("[DOOMSCROLL] ❌ DeviceActivity monitoring failed: \(error)")
            }
            
            // Schedule notification and start timer for instant mode
            scheduleVisualRefreshNotification()
            startShieldCheckTimer()
            
        } else {
            // DELAYED BLOCK MODE: 5-minute allowance, then 5-minute block
            print("[DOOMSCROLL] 📊 Mode: DELAYED BLOCK - Starting 5-minute allowance...")
            
            // Set allowance start time for UI countdown
            let allowanceStartTime = Date().timeIntervalSince1970
            if let suite = UserDefaults(suiteName: appGroupIdentifier) {
                suite.set(allowanceStartTime, forKey: "allowanceStartTime")
                suite.set("delayed_allowance", forKey: "delayedBlockPhase")  // Track phase
                suite.synchronize()
                print("[DOOMSCROLL] ✅ Saved allowanceStartTime: \(allowanceStartTime)")
            }
            
            // Calculate time 5 minutes from now (include seconds for precision)
            let fiveMinutesLater = Date().addingTimeInterval(300)
            let components = Calendar.current.dateComponents([.hour, .minute, .second], from: fiveMinutesLater)
            
            print("[DOOMSCROLL] 📊 Scheduling for \(components.hour!):\(components.minute!):\(components.second!) (exactly 5 minutes)")
            
            // Schedule activity that starts in 5 minutes - intervalDidStart will apply shield
            let schedule = DeviceActivitySchedule(
                intervalStart: components,
                intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
                repeats: false  // One-time event
            )
            
            do {
                try center.startMonitoring(
                    DeviceActivityName("doomscrollDelayedBlock"),
                    during: schedule
                )
                print("[DOOMSCROLL] ✅ DeviceActivity scheduled to start at \(components.hour!):\(components.minute!):\(components.second!)")
                print("[DOOMSCROLL] 📊 Shield will apply automatically in background after 5 minutes")
            } catch {
                print("[DOOMSCROLL] ❌ DeviceActivity monitoring failed: \(error)")
            }
            
            // Start timer to track allowance countdown (for UI only)
            startShieldCheckTimer()
        }
    }
    
    private func stopMonitoring() {
        guard #available(iOS 16.0, *) else { return }
        
        print("[DOOMSCROLL] 📊 stopMonitoring() called - clearing protection...")
        
        // Stop DeviceActivity monitoring FIRST (triggers visual refresh)
        let center = DeviceActivityCenter()
        print("[DOOMSCROLL] 📊 Stopping DeviceActivity monitoring...")
        center.stopMonitoring([DeviceActivityName("doomscrollProtection"), DeviceActivityName("doomscrollDelayedBlock")])
        print("[DOOMSCROLL] ✅ Monitoring stopped")
        
        // Clear shields using the DEFAULT store (matching Nudgetronic)
        let store = ManagedSettingsStore()
        print("[DOOMSCROLL] 📊 Clearing shields from default store...")
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomainCategories = nil
        store.shield.webDomains = nil
        
        // Clear allowance and block times
        if let suite = UserDefaults(suiteName: appGroupIdentifier) {
            suite.set(0, forKey: "allowanceStartTime")
            suite.set(0, forKey: "blockStartTime")
            suite.synchronize()
        }
        allowanceSeconds = 0
        
        // Cancel any pending notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
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
            store.shield.webDomainCategories = nil
            store.shield.webDomains = nil
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
        
        // Use the DEFAULT store (same as startMonitoring)
        let store = ManagedSettingsStore()
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomainCategories = nil
        store.shield.webDomains = nil
        
        // Stop DeviceActivity monitoring to trigger visual refresh
        let center = DeviceActivityCenter()
        center.stopMonitoring([DeviceActivityName("doomscrollProtection"), DeviceActivityName("doomscrollDelayedBlock")])
        
        if let suite = UserDefaults(suiteName: appGroupIdentifier) {
            suite.set(0, forKey: "blockStartTime")
            suite.set(0, forKey: "allowanceStartTime")
            suite.synchronize()
        }
        
        // Cancel any pending notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        stopShieldCheckTimer()
        remainingSeconds = 0
        allowanceSeconds = 0
        print("[DOOMSCROLL] ✓ Shield cleared - apps accessible")
    }
    
    private func updateCountdown() {
        guard let suite = UserDefaults(suiteName: appGroupIdentifier) else {
            print("[DOOMSCROLL] ⚠️ Cannot access App Group in updateCountdown")
            return
        }
        
        let currentTime = Date().timeIntervalSince1970
        
        // Check for allowance time (delayed mode only)
        let allowanceStartTime = suite.double(forKey: "allowanceStartTime")
        if allowanceStartTime > 0 {
            let elapsedAllowance = currentTime - allowanceStartTime
            let remainingAllowance = max(0, 300 - Int(elapsedAllowance))
            
            if remainingAllowance > 0 {
                // Still in allowance period
                allowanceSeconds = remainingAllowance
                remainingSeconds = 0
                return
            } else if remainingAllowance == 0 && suite.double(forKey: "blockStartTime") == 0 {
                // Allowance just expired - apply shield and start block
                print("[DOOMSCROLL] ⏰ 5-minute allowance expired - applying shield")
                
                allowanceSeconds = 0
                
                // Apply shield
                if let data = suite.data(forKey: "selectedApp"),
                   let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
                    let store = ManagedSettingsStore()
                    store.shield.applications = selection.applicationTokens
                    if !selection.categoryTokens.isEmpty {
                        store.shield.applicationCategories = .specific(selection.categoryTokens)
                    }
                    if !selection.webDomainTokens.isEmpty {
                        store.shield.webDomains = selection.webDomainTokens
                    }
                    print("[DOOMSCROLL] ✅ Shield applied after allowance")
                }
                
                // Set block start time
                let blockStartTime = currentTime
                suite.set(blockStartTime, forKey: "blockStartTime")
                suite.set(0, forKey: "allowanceStartTime")  // Clear allowance
                suite.synchronize()
                print("[DOOMSCROLL] ✅ Block started at: \(blockStartTime)")
                
                remainingSeconds = 300  // Start 5-minute block
                return
            }
        }
        
        // Update block countdown (for both modes when block is active)
        let blockStartTime = suite.double(forKey: "blockStartTime")
        guard blockStartTime > 0 else {
            remainingSeconds = 0
            allowanceSeconds = 0
            return
        }
        
        let elapsedSeconds = currentTime - blockStartTime
        let remaining = max(0, 300 - Int(elapsedSeconds))
        
        remainingSeconds = remaining
        allowanceSeconds = 0
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
            store.shield.webDomains = nil
            
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
        content.body = "Your break is complete! Ready to go another 5 minutes?"
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
    
    private func scheduleShieldApplication() {
        print("[DOOMSCROLL] 📊 Scheduling shield application for 5 minutes (background task)")
        
        // Cancel any existing shield notifications
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["doomscroll.apply.shield"])
        
        // Create silent notification that will trigger shield application
        let content = UNMutableNotificationContent()
        content.title = "Doomscroll Stopper"
        content.body = "Time's up! App is now blocked for 5 minutes."
        content.sound = .default
        content.userInfo = ["action": "applyShield"]  // Custom data for handling
        
        // Trigger after 5 minutes
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 300, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "doomscroll.apply.shield",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[DOOMSCROLL] ❌ Failed to schedule shield application: \(error)")
            } else {
                print("[DOOMSCROLL] ✅ Shield application scheduled for 5 minutes from now")
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
