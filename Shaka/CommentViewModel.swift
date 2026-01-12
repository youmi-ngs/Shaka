//
//  CommentViewModel.swift
//  Shaka
//
//  Created by Youmi Nagase on 2025/08/13.
//

import Foundation
import FirebaseFirestore

class CommentViewModel: ObservableObject {
    @Published var comments: [Comment] = []
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    
    deinit {
        listener?.remove()
    }
    
    // コメントをリアルタイムで取得
    func fetchComments(for postID: String, postType: Comment.PostType) {
        listener?.remove()
        
        let collection = postType == .work ? "works" : "questions"
        
        listener = db.collection(collection)
            .document(postID)
            .collection("comments")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                self.comments = snapshot.documents.compactMap { doc in
                    let data = doc.data()
                    let id = doc.documentID
                    let text = data["text"] as? String ?? ""
                    let userID = data["userID"] as? String ?? "unknown"
                    let displayName = data["displayName"] as? String ?? "User_\(String(userID.prefix(6)))"
                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    let isPrivate = data["isPrivate"] as? Bool ?? false
                    
                    // コメントは全て公開（プライベートコメントの処理を削除）
                    
                    let likedBy = data["likedBy"] as? [String] ?? []
                    let mentionedUserIDs = data["mentionedUserIDs"] as? [String] ?? []
                    
                    return Comment(
                        id: id,
                        postID: postID,
                        postType: postType,
                        text: text,
                        userID: userID,
                        displayName: displayName,
                        createdAt: createdAt,
                        isPrivate: isPrivate,
                        likedBy: likedBy,
                        mentionedUserIDs: mentionedUserIDs
                    )
                }
            }
    }
    
    // コメントを追加
    func addComment(to postID: String, postType: Comment.PostType, postUserID: String, text: String, mentionedUserIDs: [String] = []) {
        print("🚀 addComment called with mentionedUserIDs: \(mentionedUserIDs)")
        
        let userID = AuthManager.shared.getCurrentUserID() ?? "anonymous"
        let displayName = AuthManager.shared.getDisplayName()
        let collection = postType == .work ? "works" : "questions"
        let isPrivate = false // 両方とも公開コメントに変更
        
        let data: [String: Any] = [
            "text": text,
            "userID": userID,
            "displayName": displayName,
            "createdAt": Timestamp(date: Date()),
            "isPrivate": isPrivate,
            "postUserID": postUserID, // 投稿者IDを保存（プライベートコメントの表示制御用）
            "likedBy": [], // 空のいいねリスト
            "mentionedUserIDs": mentionedUserIDs // メンションされたユーザーIDリスト
        ]
        
        db.collection(collection)
            .document(postID)
            .collection("comments")
            .addDocument(data: data) { [weak self] error in
                if let error = error {
                    print("Error adding comment: \(error)")
                } else {
                    print("📝 Comment added by: \(userID)")
                    print("📝 Post owner: \(postUserID)")
                    print("📝 Mentioned users: \(mentionedUserIDs)")
                    
                    // メンションされたユーザーに通知を送信
                    var notifiedUsers = Set<String>() // 通知済みユーザーを記録
                    
                    // まずメンション通知を送信
                    for mentionedUserID in mentionedUserIDs {
                        if mentionedUserID != userID {
                            print("📢 Sending MENTION notification to: \(mentionedUserID)")
                            self?.sendMentionNotification(
                                to: mentionedUserID,
                                postID: postID,
                                postType: postType,
                                commentText: text
                            )
                            notifiedUsers.insert(mentionedUserID)
                        }
                    }
                    
                    // 投稿者にコメント通知を送信（メンション通知を受けていない場合のみ）
                    print("📝 Checking if should send comment notification:")
                    print("   - postUserID != userID: \(postUserID != userID)")
                    print("   - !notifiedUsers.contains(postUserID): \(!notifiedUsers.contains(postUserID))")
                    
                    if postUserID != userID && !notifiedUsers.contains(postUserID) {
                        print("📢 Sending COMMENT notification to post owner: \(postUserID)")
                        self?.sendCommentNotification(
                            to: postUserID,
                            postID: postID,
                            postType: postType,
                            commentText: text
                        )
                    } else {
                        print("⏭️ Skipping comment notification (already notified or self-comment)")
                    }
                }
            }
    }
    
    // コメントを削除
    func deleteComment(_ comment: Comment) {
        let collection = comment.postType == .work ? "works" : "questions"
        
        db.collection(collection)
            .document(comment.postID)
            .collection("comments")
            .document(comment.id)
            .delete { error in
                if let error = error {
                } else {
                }
            }
    }
    
    // コメントにいいねを追加/削除
    func toggleLikeComment(_ comment: Comment) {
        guard let userID = AuthManager.shared.getCurrentUserID() else { return }
        let collection = comment.postType == .work ? "works" : "questions"
        
        db.collection(collection)
            .document(comment.postID)
            .collection("comments")
            .document(comment.id)
            .getDocument { [weak self] snapshot, error in
                guard let self = self,
                      let data = snapshot?.data() else { return }
                
                var likedBy = data["likedBy"] as? [String] ?? []
                
                if let index = likedBy.firstIndex(of: userID) {
                    // いいねを削除
                    likedBy.remove(at: index)
                } else {
                    // いいねを追加
                    likedBy.append(userID)
                    
                    // 通知を送信（自分のコメントでなければ）
                    if comment.userID != userID {
                        self.sendCommentLikeNotification(to: comment)
                    }
                }
                
                // Firestoreを更新
                self.db.collection(collection)
                    .document(comment.postID)
                    .collection("comments")
                    .document(comment.id)
                    .updateData(["likedBy": likedBy]) { error in
                        if let error = error {
                            print("Error updating comment like: \(error)")
                        }
                    }
            }
    }
    
    // コメントいいね通知を送信
    private func sendCommentLikeNotification(to comment: Comment) {
        guard let currentUserID = AuthManager.shared.getCurrentUserID() else { return }
        let currentUserName = AuthManager.shared.getDisplayName()
        
        let notificationData: [String: Any] = [
            "type": "comment_like",
            "actorUid": currentUserID,
            "actorName": currentUserName,
            "targetType": comment.postType.rawValue,
            "targetId": comment.postID,
            "message": "\(currentUserName) liked your comment",
            "snippet": String(comment.text.prefix(50)),
            "createdAt": Timestamp(date: Date()),
            "read": false
        ]
        
        db.collection("notifications")
            .document(comment.userID)
            .collection("items")
            .addDocument(data: notificationData) { error in
                if let error = error {
                    print("Error sending comment like notification: \(error)")
                }
            }
    }
    
    // コメント通知を送信
    private func sendCommentNotification(to userID: String, postID: String, postType: Comment.PostType, commentText: String) {
        guard let currentUserID = AuthManager.shared.getCurrentUserID() else { return }
        let currentUserName = AuthManager.shared.getDisplayName()
        
        print("🔥 Actually sending COMMENT notification to Firestore for user: \(userID)")
        
        let notificationData: [String: Any] = [
            "type": "comment",
            "actorUid": currentUserID,
            "actorName": currentUserName,
            "targetType": postType.rawValue,
            "targetId": postID,
            "message": "\(currentUserName) commented on your \(postType.rawValue)",
            "snippet": String(commentText.prefix(50)),
            "createdAt": Timestamp(date: Date()),
            "read": false
        ]
        
        db.collection("notifications")
            .document(userID)
            .collection("items")
            .addDocument(data: notificationData) { error in
                if let error = error {
                    print("❌ Error sending comment notification: \(error)")
                } else {
                    print("✅ COMMENT notification sent to Firestore")
                }
            }
    }
    
    
    // メンション通知を送信
    private func sendMentionNotification(to userID: String, postID: String, postType: Comment.PostType, commentText: String) {
        guard let currentUserID = AuthManager.shared.getCurrentUserID() else { return }
        let currentUserName = AuthManager.shared.getDisplayName()
        
        print("🔥 Actually sending MENTION notification to Firestore for user: \(userID)")
        
        let notificationData: [String: Any] = [
            "type": "mention",
            "actorUid": currentUserID,
            "actorName": currentUserName,
            "targetType": postType.rawValue,
            "targetId": postID,
            "message": "\(currentUserName) mentioned you in a comment",
            "snippet": String(commentText.prefix(50)),
            "createdAt": Timestamp(date: Date()),
            "read": false
        ]
        
        db.collection("notifications")
            .document(userID)
            .collection("items")
            .addDocument(data: notificationData) { error in
                if let error = error {
                    print("❌ Error sending mention notification: \(error)")
                } else {
                    print("✅ MENTION notification sent to Firestore")
                }
            }
    }
}