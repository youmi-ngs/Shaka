//
//  DiscoverView.swift
//  Shaka
//
//  Created by Youmi Nagase on 2025/04/28.
//

import SwiftUI
import MapKit
import CoreLocation
import FirebaseFirestore

struct DiscoverView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var workViewModel = WorkPostViewModel()
    @StateObject private var locationSharing = LocationSharingManager.shared
    @StateObject private var searchCompleter = DiscoverLocationSearchCompleter()
    @EnvironmentObject var authManager: AuthManager
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6814, longitude: 139.7667), // 東京駅
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var showUserLocation = false
    @State private var trackingMode: MapUserTrackingMode = .follow
    @State private var workPins: [WorkMapPin] = []
    @State private var selectedWork: WorkPost?
    @State private var mapType: MKMapType = .standard
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6814, longitude: 139.7667),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    ))
    @State private var showLocationSharingSheet = false
    @State private var searchText = ""
    @State private var showingSearch = false
    @State private var showingSearchBar = false
    @State private var showPostWorkSheet = false
    @State private var longPressedCoordinate: CLLocationCoordinate2D?
    @State private var longPressedLocationName: String = ""
    @State private var pressLocation: CGPoint = .zero
    
    @ViewBuilder
    private var mapView: some View {
        if #available(iOS 17.0, *) {
            modernMapView
        } else {
            legacyMapView
        }
    }
    
    @available(iOS 17.0, *)
    @ViewBuilder
    private var modernMapView: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                mapAnnotations
            }
            .mapStyle(.standard(elevation: .flat))
            .edgesIgnoringSafeArea(.bottom)
            .gesture(
                LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onEnded { value in
                        switch value {
                        case .second(true, let drag):
                            if let location = drag?.location,
                               let coordinate = proxy.convert(location, from: .local) {
                                handleMapLongPress(at: coordinate)
                            }
                        default:
                            break
                        }
                    }
            )
            .onMapCameraChange { context in
                // Keep region in sync with camera position for iOS 17+
                region = context.region
            }
        }
    }
    
    @ViewBuilder
    private var legacyMapView: some View {
        Map(
            coordinateRegion: $region,
            showsUserLocation: true,
            userTrackingMode: $trackingMode,
            annotationItems: workPins
        ) { pin in
            MapAnnotation(coordinate: pin.coordinate) {
                PinView(pinType: .work, isOwnPost: pin.post.userID == authManager.userID)
                    .onTapGesture {
                        selectedWork = pin.post
                    }
            }
        }
        .edgesIgnoringSafeArea(.bottom)
    }
    
    @available(iOS 17.0, *)
    @MapContentBuilder
    private var mapAnnotations: some MapContent {
        // Show current user location if sharing
        if locationSharing.isSharing,
           let location = locationSharing.currentLocation {
            Annotation("Me", coordinate: location.coordinate) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
            }
        }
        
        // Show mutual followers' locations
        ForEach(locationSharing.mutualFollowersLocations) { userLocation in
            Annotation(userLocation.displayName, coordinate: userLocation.location) {
                VStack(spacing: 0) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 30, height: 30)
                        .overlay(
                            Text(String(userLocation.displayName.prefix(1)))
                                .foregroundColor(.white)
                                .font(.caption.bold())
                        )
                    
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                        .offset(y: -5)
                }
            }
        }
        
        // Work posts pins
        ForEach(workPins) { pin in
            Annotation(pin.post.title, coordinate: pin.coordinate) {
                PinView(pinType: .work, isOwnPost: pin.post.userID == authManager.userID)
                    .onTapGesture {
                        selectedWork = pin.post
                    }
            }
        }
    }
    
    var body: some View {
        ZStack {
            mapView
            
            // 検索バーをオーバーレイ表示（表示切り替え可能）
            if showingSearchBar {
                VStack {
                    // 検索バーと予測候補
                    VStack(spacing: 0) {
                        // 検索バー
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                            
                            TextField("Search for a place...", text: $searchText)
                                .textFieldStyle(PlainTextFieldStyle())
                                .onChange(of: searchText) { newValue in
                                    searchCompleter.searchQuery = newValue
                                    showingSearch = !newValue.isEmpty
                                }
                                .onSubmit {
                                    if let firstResult = searchCompleter.searchResults.first {
                                        selectSearchResult(firstResult)
                                    }
                                }
                            
                            Button(action: { 
                                searchText = ""
                                showingSearch = false
                                showingSearchBar = false
                                searchCompleter.searchResults = []
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding()
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(10, corners: showingSearch && !searchCompleter.searchResults.isEmpty ? [.topLeft, .topRight] : .allCorners)
                        
                        // 検索候補
                        if showingSearch && !searchCompleter.searchResults.isEmpty {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(searchCompleter.searchResults, id: \.self) { result in
                                        Button(action: {
                                            selectSearchResult(result)
                                        }) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(result.title)
                                                    .font(.subheadline)
                                                    .foregroundColor(.primary)
                                                if !result.subtitle.isEmpty {
                                                    Text(result.subtitle)
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            .padding(.horizontal)
                                            .padding(.vertical, 8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        
                                        if result != searchCompleter.searchResults.last {
                                            Divider()
                                                .padding(.horizontal)
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 120)
                            .background(Color(UIColor.systemBackground))
                            .cornerRadius(10, corners: [.bottomLeft, .bottomRight])
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    
                    Spacer()
                }
            }
                
                // UI オーバーレイ（iOS 16以前のみ現在地ボタンを表示）
                if #unavailable(iOS 17.0) {
                    VStack {
                        Spacer()
                        
                        // 現在地ボタン
                        HStack {
                            Spacer()
                            Button(action: {
                                centerOnUserLocation()
                            }) {
                                Image(systemName: "location.fill")
                                    .padding()
                                    .background(Color(UIColor.systemBackground))
                                    .clipShape(Circle())
                                    .shadow(radius: 5)
                            }
                            .padding()
                        }
                    }
                }
        }
        .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 検索ボタン（左側）
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        withAnimation {
                            showingSearchBar.toggle()
                            if !showingSearchBar {
                                searchText = ""
                                showingSearch = false
                                searchCompleter.searchResults = []
                            }
                        }
                    }) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(showingSearchBar ? .blue : .primary)
                    }
                }
                
                // 位置共有ボタン（右側）
                ToolbarItem(placement: .navigationBarTrailing) {
                    if authManager.userID != nil {
                        Button(action: {
                            if locationSharing.isSharing {
                                locationSharing.stopSharingLocation()
                            } else {
                                showLocationSharingSheet = true
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: locationSharing.isSharing ? "location.fill" : "location")
                                    .foregroundColor(locationSharing.isSharing ? .green : .primary)
                                if locationSharing.isSharing {
                                    Text(timeRemaining())
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                }
            }
            .onAppear {
                locationSharing.checkSharingStatus()
                locationSharing.startListeningToMutualLocations()
                loadPosts()
            }
            .onDisappear {
                locationSharing.stopListeningToMutualLocations()
            }
            .refreshable {
                loadPosts()
            }
            .sheet(item: $selectedWork) { work in
                NavigationView {
                    WorkDetailView(post: work, viewModel: workViewModel)
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .onDisappear {
                    // WorkDetailViewから戻ってきた時にデータを再読み込み
                    loadPosts()
                }
            }
            .sheet(isPresented: $showLocationSharingSheet) {
                LocationSharingSheet(
                    isPresented: $showLocationSharingSheet,
                    locationSharing: locationSharing
                )
            }
            .sheet(isPresented: $showPostWorkSheet, onDismiss: {
                // 投稿後にマップを更新
                loadPosts()
            }) {
                PostWorkView(
                    viewModel: workViewModel,
                    presetLocation: longPressedCoordinate,
                    presetLocationName: longPressedLocationName
                )
            }
    }
    
    private func timeRemaining() -> String {
        guard let expiresAt = locationSharing.sharingExpiresAt else { return "" }
        let remaining = expiresAt.timeIntervalSinceNow
        if remaining <= 0 { return "Expired" }
        
        let minutes = Int(remaining / 60)
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
        }
    }
    
    private func centerOnUserLocation() {
        if let location = locationManager.userLocation {
            withAnimation {
                region = MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
                trackingMode = .follow
            }
        }
    }
    
    private func loadPosts() {
        // 作品投稿を取得
        workViewModel.fetchPostsWithLocation { posts in
            self.workPins = posts.compactMap { post in
                guard let coordinate = post.coordinate else { 
                    return nil 
                }
                return WorkMapPin(post: post, coordinate: coordinate)
            }
        }
    }
    
    private func handleMapLongPress(at coordinate: CLLocationCoordinate2D) {
        // 触覚フィードバック
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // 座標を保存
        longPressedCoordinate = coordinate
        longPressedLocationName = ""

        // 逆ジオコーディングで地名を取得
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            DispatchQueue.main.async {
                if let placemark = placemarks?.first {
                    // 地名を組み立て
                    var components: [String] = []
                    if let name = placemark.name {
                        components.append(name)
                    }
                    if let locality = placemark.locality {
                        if !components.contains(locality) {
                            components.append(locality)
                        }
                    }
                    if let administrativeArea = placemark.administrativeArea {
                        if !components.contains(administrativeArea) {
                            components.append(administrativeArea)
                        }
                    }
                    self.longPressedLocationName = components.joined(separator: ", ")
                }

                // シートを表示
                self.showPostWorkSheet = true
            }
        }
    }

    private func selectSearchResult(_ result: MKLocalSearchCompletion) {
        // 検索結果からMKLocalSearchを実行して詳細な座標を取得
        let request = MKLocalSearch.Request(completion: result)
        let search = MKLocalSearch(request: request)
        
        search.start { response, error in
            guard let response = response, 
                  let item = response.mapItems.first else { return }
            
            DispatchQueue.main.async {
                withAnimation {
                    self.region = MKCoordinateRegion(
                        center: item.placemark.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                    
                    if #available(iOS 17.0, *) {
                        self.cameraPosition = .region(self.region)
                    }
                }
                
                // 検索をクリアして検索バーを閉じる
                self.searchText = ""
                self.showingSearch = false
                self.showingSearchBar = false
                self.searchCompleter.searchResults = []
            }
        }
    }
    
    
}

// MARK: - Discover Location Search Completer
class DiscoverLocationSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var searchResults: [MKLocalSearchCompletion] = []
    
    private let completer = MKLocalSearchCompleter()
    var searchQuery = "" {
        didSet {
            completer.queryFragment = searchQuery
        }
    }
    
    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        
        // 日本優先の検索設定
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.6814, longitude: 139.7667),
            span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
        )
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        self.searchResults = completer.results
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // エラーハンドリング（静かに失敗）
    }
}

// マップピンのプロトコル
protocol MapPinProtocol: Identifiable {
    var id: String { get }
    var coordinate: CLLocationCoordinate2D { get }
    var title: String { get }
    var pinType: PinType { get }
}

enum PinType {
    case work
    case question
}

// 作品投稿用のマップピン
struct WorkMapPin: MapPinProtocol {
    let post: WorkPost
    let coordinate: CLLocationCoordinate2D
    
    var id: String { post.id }
    var title: String { post.title }
    var pinType: PinType { .work }
}

// ピンビュー
struct PinView: View {
    let pinType: PinType
    var isOwnPost: Bool = false
    
    var body: some View {
        // 標準的な地図ピン（チョコミント風）
        Image(systemName: "mappin.circle.fill")
            .font(.system(size: 35))
            .foregroundColor(isOwnPost ? Color(red: 0.55, green: 0.27, blue: 0.07) : .mint)
            .background(
                Circle()
                .fill(Color.white)
                .frame(width: 30, height: 30)
            )
    }
}

// Location Sharing Sheet
struct LocationSharingSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var locationSharing: LocationSharingManager
    @State private var selectedDuration = 60.0 // Default 1 hour
    
    var body: some View {
        NavigationView {
            VStack {
                Spacer()
                
                VStack(spacing: 25) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "location.circle.fill")
                            .font(.system(size: 70))
                            .foregroundColor(.green)
                            .symbolRenderingMode(.hierarchical)
                        
                        Text("Share Location with Mutual Followers")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)
                        
                        Text("Only people you follow who also follow you can see your location")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                    
                    // Duration selector
                    VStack(spacing: 12) {
                        Text("Duration")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Picker("Duration", selection: $selectedDuration) {
                            Text("15 min").tag(15.0)
                            Text("30 min").tag(30.0)
                            Text("1 hour").tag(60.0)
                            Text("2 hours").tag(120.0)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    .padding(.horizontal, 20)
                    
                    // Permission check and action button
                    if locationSharing.authorizationStatus == .notDetermined {
                        Button(action: {
                            locationSharing.requestLocationPermission()
                        }) {
                            Label("Enable Location Services", systemImage: "location")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal, 20)
                    } else if locationSharing.authorizationStatus == .denied || 
                             locationSharing.authorizationStatus == .restricted {
                        VStack(spacing: 10) {
                            Label("Location Services Disabled", systemImage: "location.slash")
                                .foregroundColor(.red)
                            
                            Text("Please enable location services in Settings to share your location")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 20)
                    } else {
                        // Start sharing button
                        Button(action: {
                            locationSharing.startSharingLocation(duration: selectedDuration * 60)
                            isPresented = false
                        }) {
                            Label("Start Sharing", systemImage: "location.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal, 20)
                    }
                }
                
                Spacer()
                
                // Privacy note
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: "lock.shield")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Text("Your Privacy")
                            .font(.footnote.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Stops automatically after selected time", systemImage: "clock")
                        Label("Stop sharing anytime", systemImage: "stop.circle")
                        Label("Only mutual followers can see you", systemImage: "person.2")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Location Sharing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

#Preview {
    DiscoverView()
}
