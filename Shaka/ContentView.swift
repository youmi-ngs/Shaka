//
//  ContentView.swift
//  Shaka
//
//  Created by Youmi Nagase on 2025/04/28.
//

import SwiftUI
import FirebaseAuth

struct ContentView: View {
    @EnvironmentObject var deepLinkManager: DeepLinkManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var notificationManager: NotificationManager
    @State private var showAddFriendConfirmation = false
    @State private var pendingFriendToAdd: (uid: String, displayName: String)?
    @State private var showProfileView = false
    @State private var profileToShow: String?
    @State private var showWorkDetail = false
    @State private var workToShow: String?
    @State private var showQuestionDetail = false
    @State private var questionToShow: String?
    @State private var hasRequestedNotifications = false
    @State private var selectedTab = 0
    @State private var tabSelection = UUID()  // NavigationViewをリセットするためのトリガー
    
    var tabAccentColor: Color {
        switch selectedTab {
        case 0: return Color.mint //DiscoverView
        case 1: return Color.indigo  // SeeWorksView
        case 2: return Color.purple  // AskView
        case 3: return Color.cyan //SearchView
        default: return Color.teal //ProfileView
        }
    }
    
    var body: some View {
        TabView(selection: Binding(
            get: { selectedTab },
            set: { newValue in
                if selectedTab == newValue {
                    // 同じタブが再度選択された場合、NavigationViewをルートに戻す
                    NotificationCenter.default.post(name: Notification.Name("PopToRootView"), object: nil, userInfo: ["tab": newValue])
                }
                selectedTab = newValue
            }
        )) {
            
            NavigationView {
                SeeWorksView()
                    .popToRootOnTabReselect(tabIndex: 1)
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Works", systemImage: "eyeglasses")
            }
            .tag(1)
            
            NavigationView {
                AskView()   
                    .popToRootOnTabReselect(tabIndex: 2)
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Ask", systemImage: "questionmark.bubble")
            }
            .tag(2)
            
            NavigationView {
                DiscoverView()
                    .popToRootOnTabReselect(tabIndex: 0)
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Discover", systemImage: "globe")
            }
            .tag(0)
            
            NavigationView {
                SearchView()
                    .navigationBarHidden(true)
                    .popToRootOnTabReselect(tabIndex: 3)
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }
            .tag(3)
            
            NavigationView {
                ProfileView()
                    .popToRootOnTabReselect(tabIndex: 4)
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Profile", systemImage: "person.circle")
            }
            .tag(4)
            
        }
        .accentColor(tabAccentColor)
        .onAppear {
            #if targetEnvironment(macCatalyst)
            // Mac Catalystの場合、TabBarの色を明示的に設定
            UITabBar.appearance().tintColor = UIColor.systemIndigo
            UITabBar.appearance().unselectedItemTintColor = UIColor.systemGray
            #else
            // iOSの場合は動的に色を変更
            UITabBar.appearance().tintColor = UIColor(tabAccentColor)
            #endif
        }
        .onChange(of: deepLinkManager.showAddFriendAlert) { newValue in
            if newValue, let friend = deepLinkManager.friendToAdd {
                pendingFriendToAdd = friend
                showAddFriendConfirmation = true
                deepLinkManager.showAddFriendAlert = false
            }
        }
        .alert("Follow", isPresented: $showAddFriendConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingFriendToAdd = nil
            }
            Button("Follow") {
                if let friend = pendingFriendToAdd {
                    addFriend(uid: friend.uid)
                }
            }
        } message: {
            if let friend = pendingFriendToAdd {
                Text("Follow \(friend.displayName)?")
            }
        }
        .sheet(isPresented: $showProfileView) {
            if let uid = profileToShow {
                NavigationView {
                    PublicProfileView(authorUid: uid)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowProfile"))) { notification in
            if let uid = notification.userInfo?["uid"] as? String {
                profileToShow = uid
                showProfileView = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowWork"))) { notification in
            if let id = notification.userInfo?["id"] as? String {
                // Worksタブに切り替えて、詳細を表示
                selectedTab = 1
                // TODO: WorkDetailViewへの遷移を実装
                // 現時点では、タブを切り替えるのみ
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowQuestion"))) { notification in
            if let id = notification.userInfo?["id"] as? String {
                // Askタブに切り替えて、詳細を表示
                selectedTab = 2
                // TODO: QuestionDetailViewへの遷移を実装
                // 現時点では、タブを切り替えるのみ
            }
        }
        .onAppear {
            // 通知許可をリクエスト（初回のみ）
            if !hasRequestedNotifications && authManager.isAuthenticated {
                hasRequestedNotifications = true
                // 少し遅延させて確実に表示
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    notificationManager.requestNotificationPermission()
                }
            }
        }
    }
    
    private func addFriend(uid: String) {
        // 認証チェック
        guard Auth.auth().currentUser != nil else {
            // サインインが必要
            return
        }
        
        let followViewModel = FollowViewModel()
        followViewModel.followUser(targetUid: uid) { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                break
            }
        }
        
        pendingFriendToAdd = nil
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager.shared)
        .environmentObject(DeepLinkManager.shared)
}
