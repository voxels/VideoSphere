//
//  ImmersiveStreamingView.swift
//  VideoSphere
//
//  Created by Michael A Edgcumbe on 2/20/24.
//

import SwiftUI
import RealityKit
import RealityKitContent
import AVFoundation

struct ImmersiveStreamingView: View {
    @Binding public var fileName:String
    @Binding public var audioFileName:String
    @State private var sphereEntity :ModelEntity?
    @State private var avPlayer:AVPlayer?
    @State private var avPlayerItem:AVPlayerItem?
    @State private var audioPlayer:AVAudioPlayer?
    var body: some View {
        RealityView { content in
            
            // Add the initial RealityKit content
            if let immersiveContentEntity = try? await Entity(named: "VideoDomeScene", in: realityKitContentBundle) {
                content.add(immersiveContentEntity)
                print(immersiveContentEntity.children)
                if let sphere = immersiveContentEntity.findEntity(named: "Sphere") as? ModelEntity {
                    sphereEntity = sphere
                    sphereEntity?.setScale(SIMD3(10,10,10), relativeTo: nil)
                    if let avPlayer = avPlayer {
                        // Instantiate and configure the video material.
                        let material = VideoMaterial(avPlayer: avPlayer)

                        // Configure audio playback mode.
                        sphereEntity?.model?.materials = [material]
                        avPlayer.play()
                        audioPlayer?.play()
                    }
                    
                }
            }
        }
        .task {
            avPlayerItem = AVPlayerItem(asset: AVAsset(url:  Bundle.main.url(forResource: fileName, withExtension: "mov")!))
            avPlayer = AVPlayer(playerItem: avPlayerItem)
            audioPlayer = try? AVAudioPlayer(contentsOf: Bundle.main.url(forResource: audioFileName, withExtension: "aac")!)
        }
        .onAppear(perform: {
            avPlayer?.play()
            audioPlayer?.play()
        })
        .onDisappear(perform: {
            avPlayer?.pause()
            audioPlayer?.pause()
        })
    }
}

#Preview {
    ImmersiveStreamingView(fileName: .constant("180Video-Spatial"), audioFileName: .constant("180Video_audio"))
}
