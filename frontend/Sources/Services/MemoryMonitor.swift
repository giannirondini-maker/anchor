/**
 * Memory Monitor
 *
 * Monitors application memory usage and posts notifications when
 * memory pressure is detected, allowing views to reduce memory footprint.
 */

import Foundation
import os.log

extension Notification.Name {
    static let memoryPressureDetected = Notification.Name("com.anchor.memoryPressure")
}

@MainActor
class MemoryMonitor: ObservableObject {
    @Published var currentMemoryMB: Double = 0
    @Published var isHighMemoryPressure: Bool = false

    private let logger = Logger(subsystem: "com.gianni.rondini.anchor", category: "memory")
    private var monitorTimer: Timer?

    // Memory thresholds in MB
    private let warningThreshold: Double = 300.0
    private let criticalThreshold: Double = 400.0

    static let shared = MemoryMonitor()

    private init() {
        startMonitoring()
    }

    deinit {
        // Stop monitoring synchronously on the main actor.
        // Creating a Task in deinit can outlive deinit and capture `self`,
        // which produces a warning/error in Swift 6.
        stopMonitoring()
    }

    /// Start periodic memory monitoring
    func startMonitoring() {
        // Check memory every 5 seconds
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkMemoryUsage()
            }
        }

        // Initial check
        Task {
            await checkMemoryUsage()
        }
    }

    /// Stop memory monitoring
    nonisolated func stopMonitoring() {
        // Invalidate the timer on the main queue.
        // Marked `nonisolated` so it can be safely called from `deinit` without
        // requiring `await`/`@MainActor` context. We use a weak self to avoid
        // retaining `self` from an escaping closure that may outlive deinit.
        DispatchQueue.main.async { [weak self] in
            self?.monitorTimer?.invalidate()
            self?.monitorTimer = nil
        }
    }

    /// Check current memory usage and trigger notifications if needed
    func checkMemoryUsage() async {
        let memoryBytes = getMemoryUsage()
        let memoryMB = Double(memoryBytes) / 1024 / 1024

        currentMemoryMB = memoryMB

        logger.info("Memory usage: \(String(format: "%.2f", memoryMB)) MB")

        // Check if we should trigger memory pressure notification
        if memoryMB > criticalThreshold && !isHighMemoryPressure {
            isHighMemoryPressure = true
            logger.warning("⚠️ Critical memory pressure detected: \(String(format: "%.2f", memoryMB)) MB")
            NotificationCenter.default.post(name: .memoryPressureDetected, object: nil)
        } else if memoryMB > warningThreshold && !isHighMemoryPressure {
            logger.info("⚠️ High memory usage detected: \(String(format: "%.2f", memoryMB)) MB")
        } else if memoryMB < warningThreshold && isHighMemoryPressure {
            // Memory pressure has subsided
            isHighMemoryPressure = false
            logger.info("✅ Memory pressure subsided: \(String(format: "%.2f", memoryMB)) MB")
        }
    }

    /// Get current memory usage in bytes
    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }

        if result == KERN_SUCCESS {
            return info.resident_size
        } else {
            logger.error("Failed to get memory usage info")
            return 0
        }
    }

    /// Force a memory check (useful for testing)
    func forceCheck() async {
        await checkMemoryUsage()
    }
}
