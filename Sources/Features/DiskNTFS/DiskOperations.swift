import Foundation

/// Mount, First Aid, rename and erase for external drives. Every call re-validates the target with
/// diskutil itself rather than trusting the possibly stale `DiskVolume` the UI holds.
enum DiskOperations {
    struct Report: Equatable {
        let succeeded: Bool
        let summary: String
        let log: String
    }

    /// FSKit (exFAT/FAT on recent macOS) can block `diskutil mount` indefinitely while it checks a
    /// dirty volume, so give up after a bound instead of leaving the UI spinning.
    static func mount(_ volume: DiskVolume) async -> Report {
        await perform(volume, ["mount", volume.bsdName], timeout: 45)
    }

    static func verify(_ volume: DiskVolume) async -> Report {
        await perform(volume, ["verifyVolume", volume.bsdName], timeout: 3600)
    }

    /// diskutil unmounts the volume for the repair and remounts it afterwards.
    static func repair(_ volume: DiskVolume) async -> Report {
        if let refusal = await identityRefusal(volume) { return refusal }
        return await perform(volume, ["repairVolume", volume.bsdName], timeout: 3600)
    }

    static func rename(_ volume: DiskVolume, to newName: String, format: DiskFormat?) async -> Report {
        let name = format?.normalizedName(newName) ?? newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = format?.nameProblem(name) ?? (name.isEmpty ? L10n.text("Tên ổ không được để trống.") : nil) {
            return Report(succeeded: false, summary: problem, log: "")
        }
        if let refusal = await identityRefusal(volume) { return refusal }
        return await perform(volume, ["rename", volume.bsdName, name], timeout: 60)
    }

    static func erase(_ volume: DiskVolume, format: DiskFormat, name: String, scope: DiskEraseScope) async -> Report {
        let name = format.normalizedName(name)
        if let problem = format.nameProblem(name) {
            return Report(succeeded: false, summary: problem, log: "")
        }
        guard let info = await DiskUtil.infoPlist(volume.bsdName),
              DiskEraseGuard.isSameVolume(info: info, as: volume) else {
            return changedDriveReport
        }
        guard DiskEraseGuard.isAllowed(targetInfo: info, bootInfo: await DiskUtil.infoPlist("/")) else {
            return Report(succeeded: false, summary: L10n.text("Xmac chỉ định dạng ổ ngoài, không phải ổ hệ thống."), log: "")
        }
        let arguments: [String]
        switch scope {
        case .volume:
            arguments = ["eraseVolume", format.diskutilName, name, volume.bsdName]
        case .wholeDisk:
            let physical = DiskEraseGuard.physicalDisks(of: info)
            guard physical.count == 1, let whole = physical.first else {
                return Report(succeeded: false, summary: L10n.text("Không xác định được thiết bị chứa phân vùng."), log: "")
            }
            arguments = ["eraseDisk", format.diskutilName, name, format.partitionScheme, whole]
        }
        return await perform(volume, arguments, timeout: 1800)
    }

    private static let changedDriveReport = Report(
        succeeded: false,
        summary: L10n.text("Ổ đĩa đã thay đổi kể từ lúc bạn chọn. Hãy quét lại rồi thử lại."),
        log: ""
    )

    /// Nil when the device still holds the volume the UI showed; otherwise a refusal to act on it.
    private static func identityRefusal(_ volume: DiskVolume) async -> Report? {
        guard let info = await DiskUtil.infoPlist(volume.bsdName),
              DiskEraseGuard.isSameVolume(info: info, as: volume) else { return changedDriveReport }
        return nil
    }

    private static func perform(_ volume: DiskVolume, _ arguments: [String], timeout: TimeInterval) async -> Report {
        guard BSDDeviceName.isValid(volume.bsdName) else {
            return Report(succeeded: false, summary: L10n.text("Mã phân vùng không hợp lệ."), log: "")
        }
        let outcome = await DiskUtil.run(arguments, timeout: timeout)
        await MainActor.run { DiskManager.shared.refreshVolumes() }
        return Report(succeeded: outcome.succeeded, summary: DiskUtil.summary(of: outcome.output), log: outcome.output)
    }
}
