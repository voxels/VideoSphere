//
//  ImmersiveView.swift
//  VideoSphere
//
//  Created by Michael A Edgcumbe on 2/20/24.
//

import SwiftUI
import RealityKit
import RealityKitContent


struct ImmersiveView: View {
    @Binding public var fileName:String
    @Binding public var audioFileName:String
    @State private var model = ImmersiveViewModel(fileName: "180Video_source", ext: "mp4", audioFileName: "180Video_audio")
    @State private var sphereEntity :ModelEntity?
    var body: some View {
        RealityView { content in
            
            // Add the initial RealityKit content
            if let immersiveContentEntity = try? await Entity(named: "VideoDomeScene", in: realityKitContentBundle) {
                content.add(immersiveContentEntity)
                if let sphere = immersiveContentEntity.findEntity(named: "Sphere") as? ModelEntity {
                    sphereEntity = sphere
                    
                    sphereEntity?.setScale(SIMD3(10,10,10), relativeTo: nil)
                }
            }
        } update: { content in
            
            
        }
        .onDisappear(perform: {
            model.stop()
        })
        .onAppear(perform: {
            Task{
                do {
                    try await model.play()
                } catch {
                    print(error)
                }
            }
        })
        .onChange(of: fileName, { oldValue, newValue in
            switch fileName{
            case "360Video_Spatial":
                model.updateAsset(fileName: fileName, ext: "mov", audioFileName: audioFileName)
            case "180Video_Spatial":
                model.updateAsset(fileName: fileName, ext: "mov", audioFileName: audioFileName)
            case "180Video_source":
                model.updateAsset(fileName: fileName, ext: "mp4", audioFileName: audioFileName)
            default:
                model.updateAsset(fileName: fileName, ext: "mov", audioFileName: audioFileName)
            }
        })
        .onChange(of: model.frameReady ) { oldValue, newValue in
            guard newValue else {
                return
            }
                guard let sphere = sphereEntity else {
                    return
                }
                
                guard var modelComponent = sphere.components[ModelComponent.self] else {
                    print("Did not find model component")
                    return
                }
                
                guard var shaderGraphMaterial = modelComponent.materials.first as? ShaderGraphMaterial else {
                    print("Did not find shader graph material")
                    return
                }
                
                do {

                    if let leftTextureResource = model.leftTextureResource {
                        try shaderGraphMaterial.setParameter(name: "leftImage", value: .textureResource(leftTextureResource))
                    }
                    
                    if let rightTextureResource = model.rightTextureResource {
                        try shaderGraphMaterial.setParameter(name: "rightImage", value: .textureResource(rightTextureResource))
                    }
                    
                    modelComponent.materials = [shaderGraphMaterial]
                    sphere.components.set(modelComponent)
                    print(model.displayLinkTimestamp)
                    
                } catch {
                    print(error)
                }
        }
         
    }
}

#Preview {
    ImmersiveView(fileName: .constant("180Video-Spatial"), audioFileName: .constant("180Video_audio"))
        .previewLayout(.sizeThatFits)
}
