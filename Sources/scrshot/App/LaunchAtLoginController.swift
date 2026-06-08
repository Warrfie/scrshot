import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController {
    func apply(isEnabled: Bool) {
        guard #available(macOS 13.0, *) else { return }

        let service = SMAppService.mainApp
#if DEBUG
        do {
            if service.status != .notRegistered {
                try service.unregister()
                AppLogger.shared.info(.appLifecycle, "launch at login disabled for debug build")
            }
        } catch {
            AppLogger.shared.error(.appLifecycle, "debug launch at login cleanup failed: \(error.localizedDescription)")
        }
        return
#else
        do {
            switch (isEnabled, service.status) {
            case (true, .enabled), (false, .notRegistered):
                return
            case (true, _):
                try service.register()
                AppLogger.shared.info(.appLifecycle, "launch at login enabled")
            case (false, _):
                try service.unregister()
                AppLogger.shared.info(.appLifecycle, "launch at login disabled")
            }
        } catch {
            AppLogger.shared.error(.appLifecycle, "launch at login update failed: \(error.localizedDescription)")
        }
#endif
    }
}
