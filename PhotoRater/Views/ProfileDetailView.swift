import SwiftUI

struct ProfileDetailView: View {
    @EnvironmentObject var gallery: GalleryManager
    var profile: GalleryProfile

    @State private var viewMode: GalleryViewMode = .grid
    @State private var minScore: Double = 0
    @State private var selectedTag: PhotoTag?
    @State private var sortOption: GallerySortOption = .dateAdded

    var body: some View {
        if let index = gallery.profiles.firstIndex(where: { $0.id == profile.id }) {
            let currentProfile = gallery.profiles[index]
            VStack {
                viewModePicker
                filterControls
                content(for: currentProfile)
            }
            .navigationTitle(currentProfile.name)
            .toolbar { EditButton().disabled(viewMode != .list) }
        } else {
            Text("Profile not found")
        }
    }
}

private extension ProfileDetailView {
    var viewModePicker: some View {
        Picker("View Mode", selection: $viewMode) {
            ForEach(GalleryViewMode.allCases, id: \.self) { mode in
                Text(mode.rawValue.capitalized).tag(mode)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding([.horizontal, .top])
    }

    var filterControls: some View {
        VStack {
            HStack {
                Slider(value: $minScore, in: 0...100, step: 10)
                Text("Min \(Int(minScore))")
                    .frame(width: 50, alignment: .leading)
            }
            HStack {
                Menu {
                    Button("All", action: { selectedTag = nil })
                    ForEach(PhotoTag.allCases, id: \.self) { tag in
                        Button(tag.rawValue.capitalized, action: { selectedTag = tag })
                    }
                } label: {
                    Label(selectedTag?.rawValue.capitalized ?? "Tag", systemImage: "tag")
                }

                Menu {
                    ForEach(GallerySortOption.allCases, id: \.self) { option in
                        Button(option.rawValue, action: { sortOption = option })
                    }
                } label: {
                    Label(sortOption.rawValue, systemImage: "arrow.up.arrow.down")
                }

                Spacer()
            }
        }
        .padding(.horizontal)
    }

    func content(for profile: GalleryProfile) -> some View {
        let photos = filteredPhotos(from: profile)
        return Group {
            switch viewMode {
            case .grid:
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(photos) { photo in
                            GalleryPhotoCard(rankedPhoto: photo)
                        }
                    }
                    .padding()
                }
            case .list:
                List {
                    ForEach(photos) { photo in
                        GalleryPhotoCard(rankedPhoto: photo)
                            .listRowInsets(EdgeInsets())
                            .padding(.vertical, 4)
                    }
                    .onMove { offsets, dest in
                        gallery.movePhoto(at: offsets, to: dest, in: profile)
                    }
                }
                .listStyle(PlainListStyle())
            default:
                Text("View not implemented")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
    }

    func filteredPhotos(from profile: GalleryProfile) -> [RankedPhoto] {
        var photos = profile.photos
        photos = photos.filter { $0.score >= minScore }
        if let tag = selectedTag {
            photos = photos.filter { $0.tags?.contains(tag) ?? false }
        }
        switch sortOption {
        case .score:
            photos = photos.sorted { $0.score > $1.score }
        case .dateAdded:
            break
        }
        return photos
    }
}
