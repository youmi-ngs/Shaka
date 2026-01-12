//
//  Comment.swift
//  Shaka
//
//  Created by Youmi Nagase on 2025/08/13.
//

import Foundation
import FirebaseFirestore

struct Comment: Identifiable {
    let id: String
    let postID: String
    let postType: PostType // "work" or "question"
    let text: String
    let userID: String
    let displayName: String
    let createdAt: Date
    let isPrivate: Bool // true for questions, false for works
    var likedBy: [String] = [] // いいねしたユーザーIDのリスト
    var mentionedUserIDs: [String] = [] // メンションされたユーザーIDのリスト
    
    enum PostType: String {
        case work = "work"
        case question = "question"
    }
    
    // 編集・削除権限のチェック
    var canEdit: Bool {
        return userID == AuthManager.shared.getCurrentUserID()
    }
    
    var canDelete: Bool {
        return userID == AuthManager.shared.getCurrentUserID()
    }
}