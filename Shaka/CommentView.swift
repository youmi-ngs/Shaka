//
//  CommentView.swift
//  Shaka
//
//  Created by Youmi Nagase on 2025/08/13.
//

import SwiftUI

struct CommentView: View {
    let postID: String
    let postType: Comment.PostType
    let postUserID: String
    @StateObject private var viewModel = CommentViewModel()
    @State private var newCommentText = ""
    @State private var showDeleteAlert = false
    @State private var commentToDelete: Comment?
    @State private var mentionedUsers: [(id: String, name: String)] = [] // メンション用のユーザーリスト
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Label("Comments", systemImage: "bubble.left.fill")
                    .font(.headline)
                    .foregroundColor(postType == .question ? .purple : .orange)
                
                Spacer()
            }
            
            // Comment input
            HStack {
                TextField("Add a comment...", text: $newCommentText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($isTextFieldFocused)
                
                Button(action: submitComment) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(newCommentText.isEmpty ? .gray : (postType == .question ? .purple : .orange))
                }
                .disabled(newCommentText.isEmpty)
            }
            
            // Comments list
            if viewModel.comments.isEmpty {
                Text("No comments yet")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.comments) { comment in
                    CommentRow(
                        comment: comment,
                        viewModel: viewModel,
                        isOwnComment: comment.userID == AuthManager.shared.getCurrentUserID(),
                        onDelete: {
                            commentToDelete = comment
                            showDeleteAlert = true
                        },
                        onMention: { userID, displayName in
                            // コメント欄に@メンションを追加
                            if !newCommentText.isEmpty && !newCommentText.hasSuffix(" ") {
                                newCommentText += " "
                            }
                            newCommentText += "@\(displayName) "
                            
                            // メンションリストに追加（重複を避ける）
                            if !mentionedUsers.contains(where: { $0.id == userID }) {
                                mentionedUsers.append((id: userID, name: displayName))
                            }
                        }
                    )
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .onAppear {
            viewModel.fetchComments(for: postID, postType: postType)
        }
        .alert("Delete Comment", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let comment = commentToDelete {
                    viewModel.deleteComment(comment)
                }
            }
        } message: {
            Text("Are you sure you want to delete this comment?")
        }
    }
    
    @State private var isSubmitting = false
    
    private func submitComment() {
        // 重複送信を防ぐ
        guard !isSubmitting else { return }
        
        let trimmedText = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        isSubmitting = true
        
        // メンションされたユーザーIDを抽出
        let mentionedUserIDs = mentionedUsers.map { $0.id }
        
        // テキストフィールドを即座にクリア
        let tempText = newCommentText
        let tempMentions = mentionedUsers
        newCommentText = ""
        mentionedUsers = []
        isTextFieldFocused = false
        
        viewModel.addComment(
            to: postID,
            postType: postType,
            postUserID: postUserID,
            text: trimmedText,
            mentionedUserIDs: mentionedUserIDs
        )
        
        // 1秒後に送信フラグをリセット
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isSubmitting = false
        }
    }
}

struct CommentRow: View {
    let comment: Comment
    let viewModel: CommentViewModel
    let isOwnComment: Bool
    let onDelete: () -> Void
    let onMention: (String, String) -> Void // (userID, displayName)
    @State private var isLiked: Bool = false
    @State private var likeCount: Int = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(action: {
                    // 自分以外の名前をタップしたらメンション
                    if !isOwnComment {
                        onMention(comment.userID, comment.displayName)
                    }
                }) {
                    Text(comment.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(isOwnComment ? .blue : .primary)
                }
                .buttonStyle(PlainButtonStyle())
                
                Text("•")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(timeAgoString(from: comment.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // いいねボタン
                Button(action: {
                    toggleLike()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 14))
                            .foregroundColor(isLiked ? .red : .gray)
                        
                        if likeCount > 0 {
                            Text("\(likeCount)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                if isOwnComment {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            // @メンションをハイライト表示
            Text(attributedString(from: comment.text))
                .font(.subheadline)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isOwnComment ? Color.blue.opacity(0.05) : Color.clear)
        .cornerRadius(8)
        .onAppear {
            // 初期状態を設定
            isLiked = comment.likedBy.contains(AuthManager.shared.getCurrentUserID() ?? "")
            likeCount = comment.likedBy.count
        }
    }
    
    private func toggleLike() {
        // UI を即座に更新
        if isLiked {
            isLiked = false
            likeCount = max(0, likeCount - 1)
        } else {
            isLiked = true
            likeCount += 1
        }
        
        // Firestoreを更新
        viewModel.toggleLikeComment(comment)
    }
    
    private func attributedString(from text: String) -> AttributedString {
        var attributedString = AttributedString(text)
        
        // @メンションをハイライト
        let pattern = "@([a-zA-Z0-9_]+)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
            
            for match in matches {
                if let range = Range(match.range, in: text),
                   let attributedRange = Range(range, in: attributedString) {
                    attributedString[attributedRange].foregroundColor = .purple
                    attributedString[attributedRange].font = .subheadline.bold()
                }
            }
        }
        
        return attributedString
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            if days == 1 {
                return "yesterday"
            } else if days < 30 {
                return "\(days)d ago"
            } else {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                return formatter.string(from: date)
            }
        }
    }
}

#Preview {
    CommentView(
        postID: "sample-id",
        postType: .work,
        postUserID: "user123"
    )
}