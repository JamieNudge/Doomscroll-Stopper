//
//  DeviceActivityMonitorExtension.swift
//  DoomscrollMonitor
//
//  Created by Jamie on 24/10/2025.
//

import DeviceActivity
import Foundation
import ManagedSettings
import FamilyControls

final class DoomscrollMonitor: DeviceActivityMonitor {
    private let appGroupIdentifier = "group.Me.DoomscrollStopper"
    
    override func intervalDidStart(for activity: DeviceActivityName) {
        guard activity == .doomscrollDelayedBlock else { return }
        
        print("[DOOMSCROLL_MONITOR] intervalDidStart for doomscrollDelayedBlock - applying shield!")
        
        let suite = UserDefaults(suiteName: appGroupIdentifier)
        
        // Apply shield
        if let data = suite?.data(forKey: "selectedApp"),
           let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            print("[DOOMSCROLL_MONITOR] - Decoded selection: \(selection.applicationTokens.count) app(s)")
            
            let store = ManagedSettingsStore()
            store.shield.applications = selection.applicationTokens
            
            if !selection.categoryTokens.isEmpty {
                store.shield.applicationCategories = .specific(selection.categoryTokens)
            }
            if !selection.webDomainTokens.isEmpty {
                store.shield.webDomains = selection.webDomainTokens
            }
            
            print("[DOOMSCROLL_MONITOR] ✓ Shield applied in background!")
            
            // Set block start time
            let blockStartTime = Date().timeIntervalSince1970
            suite?.set(blockStartTime, forKey: "blockStartTime")
            suite?.set(0, forKey: "allowanceStartTime")  // Clear allowance
            suite?.set("delayed_block", forKey: "delayedBlockPhase")
            suite?.synchronize()
            print("[DOOMSCROLL_MONITOR] ✓ Block started at: \(blockStartTime)")
        } else {
            print("[DOOMSCROLL_MONITOR] ✗ No selectedApp data found")
        }
    }
    
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        print("[DOOMSCROLL_MONITOR] eventDidReachThreshold called")
        print("[DOOMSCROLL_MONITOR] - Activity: \(activity.rawValue)")
        print("[DOOMSCROLL_MONITOR] - Event: \(event.rawValue)")
        
        guard activity == .doomscrollProtection else {
            print("[DOOMSCROLL_MONITOR] Not doomscroll activity, ignoring")
            return
        }
        guard event == .thresholdReached else {
            print("[DOOMSCROLL_MONITOR] Not threshold event, ignoring")
            return
        }
        
        let suite = UserDefaults(suiteName: appGroupIdentifier)
        let isEnabled = suite?.bool(forKey: "isProtectionEnabled") ?? false
        let blockMode = suite?.string(forKey: "blockMode") ?? "instant"
        
        print("[DOOMSCROLL_MONITOR] - Protection enabled: \(isEnabled)")
        print("[DOOMSCROLL_MONITOR] - Block mode: \(blockMode)")
        
        guard isEnabled else {
            print("[DOOMSCROLL_MONITOR] Protection is disabled, skipping shield")
            return
        }
        
        guard blockMode == "delayed" else {
            print("[DOOMSCROLL_MONITOR] Not in delayed mode, ignoring threshold event")
            return
        }
        
        // Threshold reached after 5 minutes of cumulative usage
        print("[DOOMSCROLL_MONITOR] ✓ 5-minute threshold reached!")
        
        // Set block start time for countdown
        let blockStartTime = Date().timeIntervalSince1970
        suite?.set(blockStartTime, forKey: "blockStartTime")
        suite?.synchronize()
        
        print("[DOOMSCROLL_MONITOR] ✓ Set blockStartTime: \(blockStartTime)")
        
        // Apply shield
        if let data = suite?.data(forKey: "selectedApp") {
            print("[DOOMSCROLL_MONITOR] - Found selectedApp data (\(data.count) bytes)")
            
            if let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
                print("[DOOMSCROLL_MONITOR] - Decoded selection: \(selection.applicationTokens.count) app(s)")
                
                let store = ManagedSettingsStore()
                store.shield.applications = selection.applicationTokens
                
                if !selection.categoryTokens.isEmpty {
                    store.shield.applicationCategories = .specific(selection.categoryTokens)
                }
                if !selection.webDomainTokens.isEmpty {
                    store.shield.webDomains = selection.webDomainTokens
                }
                
                print("[DOOMSCROLL_MONITOR] ✓ Shield applied!")
                
                // Signal app to restart monitoring
                suite?.set(true, forKey: "restartMonitoring")
                suite?.synchronize()
                
                print("[DOOMSCROLL_MONITOR] ✓ Restart signal sent")
            } else {
                print("[DOOMSCROLL_MONITOR] ✗ Failed to decode selectedApp")
            }
        } else {
            print("[DOOMSCROLL_MONITOR] ✗ No selectedApp data found in App Group")
        }
    }
    
    override func intervalDidEnd(for activity: DeviceActivityName) {
        guard activity == .doomscrollProtection else { return }
        print("[DOOMSCROLL_MONITOR] Interval ended")
    }
}

// Local definition of activity names
extension DeviceActivityName {
    static let doomscrollProtection = Self("doomscrollProtection")
    static let doomscrollDelayedBlock = Self("doomscrollDelayedBlock")
}

extension DeviceActivityEvent.Name {
    static let thresholdReached = Self("thresholdReached")
    static let shieldApplication = Self("shieldApplication")
}
