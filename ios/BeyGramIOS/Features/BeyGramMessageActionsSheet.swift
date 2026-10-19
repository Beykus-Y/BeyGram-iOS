import SwiftUI

/// Actions are scoped to the selected message's server-provided permissions.
/// A delayed response cannot enable actions on a different selected message.
struct BeyGramMessageActionsSheet: View {
    let message: TelegramChatMessage
    @ObservedObject var conversations: TelegramConversations
    let onReply: () -> Void
    let onEdit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rights: TelegramMessagePermissions?
    @State private var loading = true
    @State private var showingDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Проверяем разрешённые действия…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let rights {
                    List {
                        Section {
                            if rights.canCopy && message.isText {
                                Button {
                                    UIPasteboard.general.string = message.text
                                    dismiss()
                                } label: {
                                    Label("Копировать текст", systemImage: "doc.on.doc")
                                }
                            }

                            if rights.canReply {
                                Button {
                                    dismiss()
                                    onReply()
                                } label: {
                                    Label("Ответить", systemImage: "arrowshape.turn.up.left")
                                }
                            }

                            if rights.canEdit && message.isText {
                                Button {
                                    dismiss()
                                    onEdit()
                                } label: {
                                    Label("Изменить", systemImage: "pencil")
                                }
                            }
                        }

                        if rights.canDeleteForSelf || rights.canDeleteForEveryone {
                            Section {
                                Button(role: .destructive) {
                                    showingDeleteConfirm = true
                                } label: {
                                    Label("Удалить сообщение", systemImage: "trash")
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Действия недоступны",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Не удалось получить права на сообщение через TDLib.")
                    )
                }
            }
            .navigationTitle("Сообщение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            conversations.messagePermissions(message) { result in
                rights = result
                loading = false
            }
        }
        .confirmationDialog(
            "Удалить сообщение?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            if rights?.canDeleteForSelf == true {
                Button("Удалить у меня", role: .destructive) {
                    conversations.deleteMessage(message, forEveryone: false)
                    dismiss()
                }
            }

            if rights?.canDeleteForEveryone == true {
                Button("Удалить у всех", role: .destructive) {
                    conversations.deleteMessage(message, forEveryone: true)
                    dismiss()
                }
            }
        } message: {
            Text("Отменить удаление после подтверждения может быть невозможно.")
        }
    }
}
