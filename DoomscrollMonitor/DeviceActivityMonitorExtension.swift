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
        
        print("[DOOMSCROLL_MONITOR] - Protection enabled: \(isEnabled)")
        
        guard isEnabled else {
            print("[DOOMSCROLL_MONITOR] Protection is disabled, skipping shield")
            return
        }
        
        // Increment total minutes used
        let currentMinutes = suite?.integer(forKey: "totalMinutesUsed") ?? 0
        let newMinutes = currentMinutes + 1
        suite?.set(newMinutes, forKey: "totalMinutesUsed")
        suite?.synchronize()
        
        print("[DOOMSCROLL_MONITOR] - Total minutes used: \(newMinutes)")
        
        // Check if we've reached 5 minutes
        if newMinutes >= 5 {
            print("[DOOMSCROLL_MONITOR] ✓ 5-minute threshold reached!")
            
            // Reset counter
            suite?.set(0, forKey: "totalMinutesUsed")
            suite?.synchronize()
            
            // Apply shield
            if let data = suite?.data(forKey: "selectedApp") {
                print("[DOOMSCROLL_MONITOR] - Found selectedApp data (\(data.count) bytes)")
                
                if let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
                    print("[DOOMSCROLL_MONITOR] - Decoded selection: \(selection.applicationTokens.count) app(s)")
                    
                    let store = ManagedSettingsStore()
                    store.shield.applications = selection.applicationTokens
                    
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
        } else {
            print("[DOOMSCROLL_MONITOR] Not yet at 5 minutes, continuing to monitor...")
        }
    }
    
    override func intervalDidEnd(for activity: DeviceActivityName) {
        guard activity == .doomscrollProtection else { return }
        print("[DOOMSCROLL_MONITOR] Interval ended")
    }
}

// Local definition of activity name
extension DeviceActivityName {
    static let doomscrollProtection = Self("doomscrollProtection")
}

extension DeviceActivityEvent.Name {
    static let thresholdReached = Self("thresholdReached")
}
