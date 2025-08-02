import SwiftUI

struct GalleryView: View {
    @EnvironmentObject var gallery: GalleryManager
    @State private var newProfile = ""

    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    TextField("New profile", text: $newProfile)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("Add") {
                        gallery.addProfile(named: newProfile)
                        newProfile = ""
                    }
                }
                .padding()

                List {
                    ForEach(gallery.profiles) { profile in
                        NavigationLink(destination: ProfileDetailView(profile: profile)) {
                            Text(profile.name)
                        }
                    }
                }
            }
            .navigationTitle("Gallery")
        }
    }
}
