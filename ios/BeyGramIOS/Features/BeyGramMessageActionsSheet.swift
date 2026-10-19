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
    @State private var allowedEmojis: [String] = []
    @State private var loadingReactions = true

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
                        if !allowedEmojis.isEmpty {
                            Section("Реакции") {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(allowedEmojis, id: \.self) { emoji in
                                            let chosen = message.reactions.contains {
                                                $0.emoji == emoji && $0.isChosen
                                            }
                                            Button {
                                                conversations.setEmojiReaction(
                                                    emoji,
                                                    for: message,
                                                    removing: chosen
                                                )
                                                dismiss()
                                            } label: {
                                                Text(emoji)
                                                    .font(.system(size: 28))
                                                    .padding(8)
                                                    .background(
                                                        chosen ? Color.accentColor.opacity(0.2)
                                                               : Color.secondary.opacity(0.10),
                                                        in: RoundedRectangle(cornerRadius: 12)
                                                    )
                                            }
                                            .accessibilityLabel(chosen ? "Убрать реакцию" : "Поставить реакцию")
                                        }
                                    }
                                    .padding(.vertical, 5)
                                }
                            }
                        }
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
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                        Text("Действия недоступны")
                            .font(.headline)
                        Text("Не удалось получить права на сообщение через TDLib.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Сообщение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
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
            conversations.availableEmojiReactions(for: message) { emoji in
                allowedEmojis = emoji
                loadingReactions = false
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
