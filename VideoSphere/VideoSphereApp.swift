//
//  VideoSphereApp.swift
//  VideoSphere
//
//  Created by Michael A Edgcumbe on 2/20/24.
//

import SwiftUI

@main
struct VideoSphereApp: App {
    @State private var fileName:String = "180Video_source"
    @State private var audioFileName:String = "180Video_audio"
    var body: some Scene {
        
        WindowGroup {
            ContentView(fileName: $fileName, audioFileName: $audioFileName)
        }

        ImmersiveSpace(id: "ImmersiveSpace") {
            if fileName.hasSuffix("source") {
                ImmersiveView(fileName: $fileName, audioFileName: $audioFileName)
            } else {
                ImmersiveStreamingView(fileName: $fileName, audioFileName: $audioFileName)
            }

        }.immersionStyle(selection: .constant(.full), in: .full)
    }
}

