import Cocoa
import Combine
import Foundation
import SwiftUI

@MainActor
public final class DeduplicatorViewModel: ObservableObject {
    public static let shared = DeduplicatorViewModel()

    @Published public var phase: DeduplicatorPhase = .idle
    @Published public var groups: [DuplicateGroup] = []
    @Published public var isScanning: Bool = false
    @Published public var isCloning: Bool = false
    @Published public var statusMessage: String = ""
    @Published public var selectedRoots: Set<String> = [
        NSHomeDirectory() + "/Downloads",
        NSHomeDirectory() + "/Documents",
        NSHomeDirectory() + "/Desktop"
    ]
    @Published public var lastClonedBytes: Int64 = 0
    @Published public var lastClonedFilesCount: Int = 0
    @Published public var undoAvailable: Bool = false
    @Published public var selectedCategory: DeduplicatorFileCategory = .all
    @Published public var isScheduleSheetPresented: Bool = false

    public var scheduler: DeduplicatorScheduler {
        DeduplicatorScheduler.shared
    }

    private var currentScanner: DeduplicatorScanner?
    private let journal = DeduplicatorJournal.shared

    public init() {
        checkUndoAvailability()
    }

    public var totalReclaimableBytes: Int64 {
        filteredGroups.filter { $0.isSelected }.reduce(0) { $0 + $1.reclaimableBytes }
    }

    public var formattedTotalReclaimable: String {
        ByteSize.string(totalReclaimableBytes, countStyle: .file)
    }

    public var filteredGroups: [DuplicateGroup] {
        if selectedCategory == .all {
            return groups
        }
        return groups.filter { $0.category == selectedCategory }
    }

    public func checkUndoAvailability() {
        undoAvailable = !journal.readEntries().isEmpty
    }

    // MARK: - Actions

    public func startScan() {
        guard !isScanning, !isCloning else { return }

        isScanning = true
        groups.removeAll()
        statusMessage = L10n.text("Đang bắt đầu quét các thư mục đã chọn...")
        phase = .scanningDirectories(scannedFiles: 0)

        let minSize: Int64 = (selectedCategory == .code) ? 1024 : (64 * 1024)

        let options = DeduplicatorScanOptions(
            rootPaths: Array(selectedRoots),
            minSizeBytes: minSize,
            skipPaths: [
                NSHomeDirectory() + "/Library",
                NSHomeDirectory() + "/.Trash"
            ],
            category: selectedCategory
        )

        let scanner = DeduplicatorScanner(options: options) { [weak self] progressPhase in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.phase = progressPhase
                switch progressPhase {
                case .scanningDirectories(let count):
                    self.statusMessage = L10n.format("Đang duyệt thư mục: đã tìm thấy %d tệp...", count)
                case .edgeHashing(let done, let total):
                    self.statusMessage = L10n.format("Sàng lọc nhanh (Edge Hash): %d / %d tệp", done, total)
                case .fullHashing(let done, let total):
                    self.statusMessage = L10n.format("Băm toàn diện (Full SHA-256): %d / %d tệp", done, total)
                case .byteVerifying(let done, let total):
                    self.statusMessage = L10n.format("Đối chiếu từng byte: %d / %d nhóm", done, total)
                case .cloning:
                    break
                case .done:
                    self.statusMessage = L10n.text("Quét hoàn tất!")
                case .idle:
                    break
                }
            }
        }
        self.currentScanner = scanner

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let report = scanner.scan()
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.groups = report.groups
                self.isScanning = false
                self.phase = .done
                if report.groups.isEmpty {
                    self.statusMessage = L10n.text("Không tìm thấy tệp trùng lặp nào cần hợp nhất.")
                } else {
                    self.statusMessage = L10n.format("Tìm thấy %d nhóm tệp trùng lặp (Có thể tiết kiệm %@).",
                                                     report.groups.count,
                                                     ByteSize.string(report.totalReclaimableBytes, countStyle: .file))
                }
            }
        }
    }

    public func cancelScan() {
        currentScanner?.cancel()
        isScanning = false
        phase = .idle
        statusMessage = L10n.text("Đã hủy quét.")
    }

    public func reclaimSelected() {
        guard !isCloning, !isScanning else { return }
        let selectedGroups = filteredGroups.filter { $0.isSelected }
        guard !selectedGroups.isEmpty else { return }

        isCloning = true
        var totalClonedCount = 0
        var totalFreedBytes: Int64 = 0

        var workItems: [(path: String, keeper: String, size: Int64)] = []
        for g in selectedGroups {
            for dup in g.duplicates {
                workItems.append((path: dup, keeper: g.keeper, size: g.size))
            }
        }

        let totalItems = workItems.count
        phase = .cloning(done: 0, total: totalItems, currentPath: "")

        let selectedIDs = Set(selectedGroups.map { $0.id })

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            for (idx, item) in workItems.enumerated() {
                Task { @MainActor [weak self] in
                    self?.phase = .cloning(done: idx + 1, total: totalItems, currentPath: item.path)
                    self?.statusMessage = L10n.format("Đang CoW clone: %d / %d tệp...", idx + 1, totalItems)
                }

                // Call clone without quiet requirement so user-initiated scan takes effect immediately
                let res = APFSCloneEngine.clone(
                    path: item.path,
                    into: item.keeper,
                    expectedSize: item.size,
                    requireQuietPeriod: false
                )

                if res.outcome == .cloned {
                    totalClonedCount += 1
                    totalFreedBytes += item.size
                    self.journal.record(path: item.path, keeper: item.keeper, size: item.size)
                }
            }

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isCloning = false
                self.phase = .done
                self.lastClonedFilesCount = totalClonedCount
                self.lastClonedBytes = totalFreedBytes
                self.checkUndoAvailability()

                // Remove successfully cloned items from UI list
                self.groups.removeAll { selectedIDs.contains($0.id) }
                self.statusMessage = L10n.format("Đã hợp nhất thành công %d tệp, tiết kiệm %@ ổ cứng!",
                                                 totalClonedCount,
                                                 ByteSize.string(totalFreedBytes, countStyle: .file))
            }
        }
    }

    public func undoAll() {
        guard !isCloning, !isScanning else { return }
        isCloning = true
        statusMessage = L10n.text("Đang hoàn nguyên các tệp đã hợp nhất về trạng thái riêng lẻ...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let (success, failed) = self.journal.undoAll()

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isCloning = false
                self.checkUndoAvailability()
                self.statusMessage = L10n.format("Hoàn tác hoàn tất: %d tệp đã tách riêng, %d tệp thất bại/đã bị xóa.", success, failed)
            }
        }
    }

    public func toggleSelectAll() {
        let allSelected = filteredGroups.allSatisfy { $0.isSelected }
        let currentFilteredIDs = Set(filteredGroups.map { $0.id })
        for i in 0..<groups.count {
            if currentFilteredIDs.contains(groups[i].id) {
                groups[i].isSelected = !allSelected
            }
        }
    }

    public func revealInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
