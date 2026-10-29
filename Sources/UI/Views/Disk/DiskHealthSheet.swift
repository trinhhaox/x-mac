import SwiftUI

final class DiskHealthModel: ObservableObject {
    @Published var info: DiskHealthInfo?
    @Published var isLoading = true
    @Published var speed: DiskSpeedTest.Result?
    @Published var speedError: String?
    @Published var isTesting = false

    func load(_ volume: DiskVolume) {
        Task {
            let info = await DiskHealthInfo.load(for: volume)
            await MainActor.run {
                self.info = info
                self.isLoading = false
            }
        }
    }

    func runSpeedTest(_ volume: DiskVolume) {
        guard let mountPoint = volume.mountPoint else { return }
        isTesting = true
        speedError = nil
        Task {
            var result: DiskSpeedTest.Result?
            var failure: String?
            do {
                result = try await DiskSpeedTest.run(at: mountPoint)
            } catch DiskSpeedTest.Failure.notEnoughSpace {
                failure = L10n.text("Ổ không đủ chỗ trống để đo (cần khoảng 512 MB).")
            } catch {
                failure = L10n.format("Không đo được: %@", "\(error)")
            }
            let (finalResult, finalFailure) = (result, failure)
            await MainActor.run {
                self.speed = finalResult
                self.speedError = finalFailure
                self.isTesting = false
            }
        }
    }
}

struct DiskHealthSheet: View {
    let volume: DiskVolume
    @StateObject private var model = DiskHealthModel()
    @ObservedObject private var tools = DiskToolsController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BrandSectionTitle(L10n.format("Sức khoẻ ổ %@", volume.name), subtitle: "Thông tin phần cứng và tốc độ đọc ghi thực tế.")

            if model.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let info = model.info {
                VStack(alignment: .leading, spacing: 8) {
                    row("Thiết bị", info.model)
                    row("Kết nối", info.connection)
                    row("Loại ổ", info.isSolidState.map { $0 ? "SSD" : "HDD" } ?? L10n.text("Không rõ"))
                    HStack(alignment: .top) {
                        Text("SMART").frame(width: 90, alignment: .leading).foregroundColor(.secondary)
                        smartStatus(info.smart)
                    }
                }
                .font(.system(size: 12))
            } else {
                Text("Không đọc được thông tin ổ.").font(.system(size: 12)).foregroundColor(.secondary)
            }

            Divider()
            speedSection

            HStack {
                Spacer()
                Button("Xong") { tools.activeSheet = nil }
                    .buttonStyle(BrandSecondaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isTesting)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear { model.load(volume) }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(L10n.text(title)).frame(width: 90, alignment: .leading).foregroundColor(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func smartStatus(_ smart: DiskHealthInfo.SMART) -> some View {
        switch smart {
        case .verified:
            StatusBadge(title: "Tốt", isPositive: true)
        case .failing:
            VStack(alignment: .leading, spacing: 4) {
                StatusBadge(title: "Sắp hỏng", isPositive: false)
                Text("Ổ báo lỗi phần cứng. Hãy sao lưu dữ liệu ngay.").foregroundColor(.red)
            }
        case .unsupported:
            Text("Không hỗ trợ (đa số hộp USB không truyền SMART).").foregroundColor(.secondary)
        }
    }

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tốc độ đọc/ghi").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(model.isTesting ? L10n.text("Đang đo...") : L10n.format("Đo tốc độ (%lld MB)", Int64(DiskSpeedTest.defaultSizeMB))) {
                    model.runSpeedTest(volume)
                }
                .buttonStyle(BrandPrimaryButtonStyle())
                .disabled(model.isTesting || !volume.isMounted || !volume.isWritable)
            }
            if !volume.isMounted || !volume.isWritable {
                Text("Cần gắn kết ổ ở chế độ đọc - ghi để đo tốc độ.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            if model.isTesting {
                ProgressView().controlSize(.small)
            }
            if let speed = model.speed {
                HStack(spacing: 24) {
                    metric("Ghi", speed.writeMBps)
                    metric("Đọc", speed.readMBps)
                }
            }
            if let error = model.speedError {
                Text(error).font(.system(size: 11)).foregroundColor(.red)
            }
        }
    }

    private func metric(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.text(title)).font(.system(size: 11)).foregroundColor(.secondary)
            Text(String(format: "%.0f MB/s", value)).font(.system(size: 20, weight: .bold))
        }
    }
}
