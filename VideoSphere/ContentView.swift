//
//  ContentView.swift
//  VideoSphere
//
//  Created by Michael A Edgcumbe on 2/20/24.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ContentView: View {
    @Binding public var fileName:String
    @Binding public var audioFileName:String
    @State private var showImmersiveSpace = false
    @State private var immersiveSpaceIsShown = false

    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    var body: some View {
        VStack {
            Button(action: {
                fileName = "180Video_source"
                audioFileName = ""
                showImmersiveSpace.toggle()
            }, label: {
                Text("Party Vibe (Metal rendered from source)")
            }).padding()
            Button(action: {
                fileName = "180Video_Spatial"
                audioFileName = "180Video_audio"
                showImmersiveSpace.toggle()
            }, label: {
                Text("Party Vibe (Pre-rendered)")
            }).padding()

            Button(action: {
                fileName = "360Video_Spatial"
                audioFileName = "360Video_audio"
                showImmersiveSpace.toggle()
            }, label: {
                Text("Peaceful Vibe (Pre-rendered)")
            }).padding()

        }
        .padding()
        .onChange(of: showImmersiveSpace) { _, newValue in
            Task {
                if newValue {
                    switch await openImmersiveSpace(id:"ImmersiveSpace") {
                    case .opened:
                        immersiveSpaceIsShown = true
                    case .error, .userCancelled:
                        fallthrough
                    @unknown default:
                        immersiveSpaceIsShown = false
                        showImmersiveSpace = false
                    }
                } else if immersiveSpaceIsShown {
                    await dismissImmersiveSpace()
                    immersiveSpaceIsShown = false
                }
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView(fileName: .constant("180Video-Spatial"), audioFileName: .constant("180Video_audio"))
}

