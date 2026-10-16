import SwiftUI

struct DownloadsOrganizerView: View {
    @ObservedObject private var organizer: DownloadsOrganizer

    init(organizer: DownloadsOrganizer = .shared) {
        self.organizer = organizer
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BrandPageHeader(
                    title: "Sắp xếp Downloads",
                    subtitle: "Xem trước nơi đến của từng tệp trước khi xác nhận di chuyển."
                ) {
                    Button("Chọn thư mục…") { organizer.chooseFolder() }
                        .buttonStyle(BrandSecondaryButtonStyle())
                        .disabled(organizer.busy)
                }

                rulesCard
                actionCard
                previewSection
            }
            .padding(26)
        }
        .xmacPage()
        .onAppear { organizer.startWatching() }
        .onDisappear { organizer.stopWatching() }
        .alert("Di chuyển các tệp trong bản xem trước?", isPresented: $organizer.confirmation) {
            Button("Hủy", role: .cancel) { organizer.cancelApply() }
            Button("Sắp xếp") { organizer.apply() }
        } message: {
            Text("Không ghi đè tệp trùng tên. Tệp thay đổi sau bản xem trước sẽ được bỏ qua; các mục đã di chuyển có thể hoàn tác.")
        }
        .alert("Giữ thay đổi và bỏ khả năng hoàn tác?", isPresented: $organizer.keepConfirmation) {
            Button("Hủy", role: .cancel) {}
            Button("Giữ thay đổi") { organizer.keepChanges() }
        } message: {
            Text("Các tệp vẫn ở vị trí hiện tại. Nhật ký hoàn tác sẽ được xóa để bạn có thể sắp xếp lần mới.")
        }
    }

    private var rulesCard: some View {
        ModernCard {
            HStack(spacing: 13) {
                BrandIconTile(iconName: "folder.fill", color: XmacTheme.blue, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Thư mục đang theo dõi")
                        .font(.system(size: 13, weight: .semibold))
                    Text(organizer.root.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer()
                if organizer.busy {
                    ProgressView().controlSize(.small)
                }
            }

            Divider().opacity(0.55)

            BrandSectionTitle(
                "Quy tắc phân loại",
                subtitle: "Chọn nhóm tệp Xmac sẽ đưa vào thư mục tương ứng."
            )

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(organizer.rules.indices, id: \.self) { index in
                    ruleToggle(at: index)
                }
            }

            Label(
                "Xmac chỉ lập bản xem trước. Thư mục, liên kết và tệp vừa thay đổi sẽ được bỏ qua để tránh di chuyển nhầm.",
                systemImage: "shield.checkered"
            )
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
    }

    private func ruleToggle(at index: Int) -> some View {
        Toggle(
            isOn: Binding(
                get: { organizer.rules[index].enabled },
                set: {
                    organizer.rules[index].enabled = $0
                    organizer.refresh()
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(organizer.rules[index].folder)
                    .font(.system(size: 12, weight: .semibold))
                Text(organizer.rules[index].extensions.sorted().joined(separator: ", "))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .tint(XmacTheme.blue)
        .disabled(organizer.busy)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(XmacTheme.blue.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(XmacTheme.cardStroke, lineWidth: 1)
        )
    }

    private var actionCard: some View {
        ModernCard {
            HStack(spacing: 13) {
                BrandIconTile(
                    iconName: organizer.undoCount > 0 ? "arrow.uturn.backward.circle.fill" : "list.bullet.clipboard.fill",
                    color: organizer.undoCount > 0 ? .orange : XmacTheme.cyan,
                    size: 42
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(organizer.undoCount > 0 ? "Có thể hoàn tác" : "Trạng thái bản xem trước")
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.text(organizer.message))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 12)
                Button("Quét lại") { organizer.refresh() }
                    .buttonStyle(BrandSecondaryButtonStyle())
                    .disabled(organizer.busy)
                Button(L10n.format("Sắp xếp %lld tệp…", Int64(organizer.preview.count))) { organizer.requestApply() }
                    .buttonStyle(BrandPrimaryButtonStyle())
                    .disabled(organizer.busy || organizer.preview.isEmpty || organizer.undoCount > 0)
            }

            if organizer.undoCount > 0 {
                Divider().opacity(0.55)
                HStack(spacing: 10) {
                    Text(L10n.format("%lld tệp của lần sắp xếp trước vẫn có thể khôi phục.", Int64(organizer.undoCount)))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Hoàn tác") { organizer.undo() }
                        .buttonStyle(BrandSecondaryButtonStyle())
                        .disabled(organizer.busy)
                    Button("Giữ thay đổi…") { organizer.keepConfirmation = true }
                        .buttonStyle(BrandDestructiveButtonStyle())
                        .disabled(organizer.busy)
                }
                Text(organizer.undoRoot)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if !organizer.preview.isEmpty {
            BrandSectionTitle(
                "Bản xem trước",
                subtitle: L10n.format("%lld tệp sẽ được di chuyển sau khi bạn xác nhận.", Int64(organizer.preview.count))
            )

            ModernCard {
                LazyVStack(spacing: 0) {
                    ForEach(Array(organizer.preview.enumerated()), id: \.element.id) { index, entry in
                        BrandListRow {
                            HStack(spacing: 12) {
                                BrandIconTile(iconName: "doc.fill", color: XmacTheme.blue, size: 34)
                                Text(entry.source.lastPathComponent)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                Spacer()
                                Label(entry.folder, systemImage: "folder.fill")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(XmacTheme.blue)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(XmacTheme.blue.opacity(0.09)))
                            }
                        }
                        if index < organizer.preview.count - 1 {
                            Divider().opacity(0.55)
                        }
                    }
                }
            }
        }
    }
}
