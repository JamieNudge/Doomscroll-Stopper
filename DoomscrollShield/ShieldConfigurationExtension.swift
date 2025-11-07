//
//  ShieldConfigurationExtension.swift
//  DoomscrollShield
//
//  Created by Jamie on 24/10/2025.
//

import ManagedSettings
import ManagedSettingsUI
import UIKit
import DeviceActivity
import FamilyControls

class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        return doomscrollShieldConfiguration()
    }
    
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        return doomscrollShieldConfiguration()
    }
    
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        return doomscrollShieldConfiguration()
    }
    
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        return doomscrollShieldConfiguration()
    }
    
    private func doomscrollShieldConfiguration() -> ShieldConfiguration {
        let appGroupIdentifier = "group.Me.DoomscrollStopper"
        let suite = UserDefaults(suiteName: appGroupIdentifier)
        
        print("[SHIELD] 📊 ========================================")
        print("[SHIELD] 📊 Shield configuration requested")
        
        // Check if 5 minutes have elapsed
        let blockStartTime = suite?.double(forKey: "blockStartTime") ?? 0
        let currentTime = Date().timeIntervalSince1970
        let elapsedSeconds = currentTime - blockStartTime
        let remainingSeconds = max(0, 300 - Int(elapsedSeconds)) // 300 = 5 minutes
        
        print("[SHIELD] 📊 Block start time: \(blockStartTime)")
        print("[SHIELD] 📊 Current time: \(currentTime)")
        print("[SHIELD] 📊 Elapsed seconds: \(Int(elapsedSeconds))")
        print("[SHIELD] 📊 Remaining seconds: \(remainingSeconds)")
        
        // Debug: Check if blockStartTime is actually set
        if blockStartTime == 0 {
            print("[SHIELD] ⚠️ WARNING: blockStartTime is 0! Shield will show 0:00")
            print("[SHIELD] ⚠️ This means blockStartTime wasn't set before shield was applied")
        }
        
        // If 5 minutes have passed, clear the shield NOW
        if blockStartTime > 0 && elapsedSeconds >= 300 {
            print("[SHIELD] ⏰ 5 minutes elapsed - TIME TO CLEAR!")
            print("[SHIELD] 📊 Attempting to clear shield and stop monitoring...")
            
            // Use the DEFAULT store (matching Nudgetronic approach)
            let store = ManagedSettingsStore()
            
            // Clear all shields
            print("[SHIELD] 📊 Clearing all shields from default store...")
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomainCategories = nil
            store.shield.webDomains = nil
            print("[SHIELD] ✅ All shields cleared from store")
            
            // Stop DeviceActivity monitoring to trigger visual refresh
            // (This is the KEY to making iOS update the home screen icons!)
            let center = DeviceActivityCenter()
            print("[SHIELD] 📊 Stopping DeviceActivity monitoring to refresh visual state...")
            center.stopMonitoring([DeviceActivityName("doomscrollProtection"), DeviceActivityName("doomscrollDelayedBlock")])
            print("[SHIELD] ✅ Monitoring stopped - iOS should refresh icon states now")
            
            // Mark as cleared and signal main app to update state
            suite?.set(0, forKey: "blockStartTime")
            suite?.set(true, forKey: "restartMonitoring")
            suite?.synchronize()
            print("[SHIELD] ✅ blockStartTime reset to 0 in App Group")
            print("[SHIELD] 📊 Signaled main app to update state")
            
            print("[SHIELD] ✅ Shield cleared and monitoring stopped - apps now accessible")
            print("[SHIELD] 📊 Apps should now appear UNBLOCKED in home screen")
            print("[SHIELD] 📊 ========================================")
            
            // Show a "cleared" message with dismissible button
            // The shield is now removed, so next access attempt will succeed
            let title = ShieldConfiguration.Label(
                text: "Break complete! 🌱",
                color: .label
            )
            
            let subtitle = ShieldConfiguration.Label(
                text: "Your 5-minute break is over. The block has been removed.\n\nTap OK and try again!",
                color: .secondaryLabel
            )
            
            let primaryButton = ShieldConfiguration.Label(
                text: "OK",
                color: .white
            )
            
            return ShieldConfiguration(
                title: title,
                subtitle: subtitle,
                primaryButtonLabel: primaryButton,
                secondaryButtonLabel: nil
            )
        }
        
        // Still in cooldown - show countdown
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        
        print("[SHIELD] ⏳ Still in cooldown - showing countdown")
        print("[SHIELD] 📊 Time remaining: \(minutes):\(String(format: "%02d", seconds))")
        print("[SHIELD] 📊 ========================================")
        
        let title = ShieldConfiguration.Label(
            text: "Taking a break from doomscrolling 🌱",
            color: .label
        )
        
        let subtitle = ShieldConfiguration.Label(
            text: "You can access this app again in \(minutes):\(String(format: "%02d", seconds))\n\nUse this time to work on your goals!",
            color: .secondaryLabel
        )
        
        let primaryButton = ShieldConfiguration.Label(
            text: "Okay, I'll wait",
            color: .white
        )
        
        return ShieldConfiguration(
            title: title,
            subtitle: subtitle,
            primaryButtonLabel: primaryButton,
            secondaryButtonLabel: nil
        )
    }
}
