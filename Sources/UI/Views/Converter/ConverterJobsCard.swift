import SwiftUI

struct ConverterJobsCard: View {
    @ObservedObject var manager: ConverterManager

    var body: some View {
        if !manager.jobs.isEmpty {
            ModernCard {
                HStack {
                    BrandSectionTitle("Tác vụ chuyển đổi")
                    Spacer()
                    if manager.jobs.contains(where: { !$0.state.isFinished }) {
                        Button(L10n.text("Hủy tất cả"), action: manager.cancelAll)
                            .buttonStyle(BrandDestructiveButtonStyle())
                    }
                    if manager.jobs.contains(where: { $0.state.isFinished }) {
                        Button(L10n.text("Xóa mục đã xong"), action: manager.clearFinished)
                            .buttonStyle(BrandSecondaryButtonStyle())
                    }
                }
                VStack(spacing: 0) {
                    ForEach(manager.jobs.reversed()) { job in
                        ConverterJobRow(job: job) { manager.cancel(job.id) }
                        if job.id != manager.jobs.first?.id { Divider() }
                    }
                }
            }
        }
    }
}
