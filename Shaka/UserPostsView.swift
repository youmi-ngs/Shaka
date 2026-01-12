//
//  UserPostsView.swift
//  Shaka
//
//  Created by Assistant on 2025/08/17.
//

import SwiftUI
import FirebaseFirestore

struct UserPostsView: View {
    let userId: String
    let displayName: String
    @State private var works: [WorkPost] = []
    @State private var questions: [QuestionPost] = []
    @State private var isLoading = false
    @State private var selectedTab = 0
    
    private let db = Firestore.firestore()
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab Picker
            Picker("", selection: $selectedTab) {
                Text("Works (\(works.count))").tag(0)
                Text("Questions (\(questions.count))").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            // Content
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabView(selection: $selectedTab) {
                    worksTab.tag(0)
                    questionsTab.tag(1)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
        }
        .navigationTitle("\(displayName)'s Posts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fetchUserPosts()
        }
    }
    
    // MARK: - Works Tab
    private var worksTab: some View {
        Group {
            if works.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("No works yet")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(works) { work in
                            NavigationLink {
                                WorkDetailView(post: work, viewModel: WorkPostViewModel())
                            } label: {
                                UserWorkCard(work: work)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Questions Tab
    private var questionsTab: some View {
        Group {
            if questions.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "questionmark.bubble")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("No questions yet")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(questions) { question in
                            NavigationLink {
                                QuestionDetailView(post: question, viewModel: QuestionPostViewModel())
                            } label: {
                                UserQuestionCard(question: question)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Fetch User Posts
    private func fetchUserPosts() {
        isLoading = true
        
        // Fetch works
        db.collection("works")
            .whereField("userID", isEqualTo: userId)
            .getDocuments { snapshot, error in
                if let error = error {
                }
                if let documents = snapshot?.documents {
                    self.works = documents.compactMap { doc in
                        let data = doc.data()
                        guard let title = data["title"] as? String,
                              let userID = data["userID"] as? String,
                              let displayName = data["displayName"] as? String,
                              let timestamp = data["createdAt"] as? Timestamp else {
                            return nil
                        }
                        
                        let imageURL = (data["imageURL"] as? String).flatMap { URL(string: $0) }
                        
                        let work = WorkPost(
                            id: doc.documentID,
                            title: title,
                            description: data["description"] as? String,
                            detail: data["detail"] as? String,
                            imageURL: imageURL,
                            createdAt: timestamp.dateValue(),
                            userID: userID,
                            displayName: displayName,
                            location: data["location"] as? GeoPoint,
                            locationName: data["locationName"] as? String,
                            isActive: data["isActive"] as? Bool ?? true
                        )
                        return work
                    }.sorted { $0.createdAt > $1.createdAt }
                }
            }
        
        // Fetch questions
        db.collection("questions")
            .whereField("userID", isEqualTo: userId)
            .getDocuments { snapshot, error in
                if let error = error {
                }
                if let documents = snapshot?.documents {
                    self.questions = documents.compactMap { doc in
                        let data = doc.data()
                        guard let title = data["title"] as? String,
                              let body = data["body"] as? String,
                              let userID = data["userID"] as? String,
                              let displayName = data["displayName"] as? String,
                              let timestamp = data["createdAt"] as? Timestamp else {
                            return nil
                        }
                        
                        let question = QuestionPost(
                            id: doc.documentID,
                            title: title,
                            body: body,
                            createdAt: timestamp.dateValue(),
                            userID: userID,
                            displayName: displayName,
                            location: data["location"] as? GeoPoint,
                            locationName: data["locationName"] as? String,
                            isActive: data["isActive"] as? Bool ?? true
                        )
                        return question
                    }.sorted { $0.createdAt > $1.createdAt }
                }
                isLoading = false
            }
    }
}

// MARK: - Work Card
struct UserWorkCard: View {
    let work: WorkPost
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Group {
                        if let url = work.imageURL {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .overlay(ProgressView())
                            }
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .overlay(
                                    Image(systemName: "photo")
                                        .foregroundColor(.gray)
                                        .font(.system(size: 40))
                                )
                        }
                    }
                )
                .clipped()
            
            // Title
            Text(work.title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Question Card
struct UserQuestionCard: View {
    let question: QuestionPost
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            Image(systemName: "questionmark.circle.fill")
                .font(.title2)
                .foregroundColor(.blue)
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                Text(question.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                
                if !question.body.isEmpty {
                    Text(question.body)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                
                // Date
                Text(question.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}