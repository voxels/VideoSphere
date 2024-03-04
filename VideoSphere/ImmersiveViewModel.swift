//
//  ImmersiveViewModel.swift
//  VideoSphere
//
//  Created by Michael A Edgcumbe on 2/20/24.
//

import Foundation
import AVFoundation
import RealityKit
import CoreGraphics
import Metal
import MetalKit
import CoreVideo
import CoreImage

@Observable
class ImmersiveViewModel {

    static let localAsset:AVAsset = AVAsset(url: Bundle.main.url(forResource: "180Video_source", withExtension: "mp4")!)
    public var player:AVPlayer
    public var playerItem:AVPlayerItem
    public var imageGenerator:AVAssetImageGenerator
    public var assetReader:AVAssetReader?
    public var trackOutput:AVAssetReaderTrackOutput?
    public var leftTextureResource:TextureResource?
    public var rightTextureResource:TextureResource?
    public var frameReady:Bool = false
    public var displayLinkTimestamp:Double = 0
    public var lastFrameDisplayLinkTimestamp:Double = 0
    private var displayLink:CADisplayLink!
    private var dateStarted:Date = Date.now
    let mtlDevice = MTLCreateSystemDefaultDevice()
    private let loader:MTKTextureLoader
    //private var commandQueue: MTLCommandQueue?
    private var renderPipelineState: MTLRenderPipelineState?
    private var leftImagePlaneVertexBuffer: MTLBuffer?
    private var rightImagePlaneVertexBuffer: MTLBuffer?
    
    private var CVMTLTextureCache = UnsafeMutablePointer<CVMetalTextureCache?>.allocate(capacity:1)
    
    let CVMTLTexture = UnsafeMutablePointer<CVMetalTexture?>.allocate(capacity: 1)
    
    public var audioPlayer = AVAudioPlayer()
    public var audioFileName:String
    
    private func initializeRenderPipelineState() {
        guard
            let library = mtlDevice?.makeDefaultLibrary()
        else {
            return
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        
        let imagePlaneVertexDescriptor = MTLVertexDescriptor()
        imagePlaneVertexDescriptor.attributes[0].format = .float2
        imagePlaneVertexDescriptor.attributes[0].offset = 0
        imagePlaneVertexDescriptor.attributes[0].bufferIndex = 0
        imagePlaneVertexDescriptor.attributes[1].format = .float2
        imagePlaneVertexDescriptor.attributes[1].offset = 8
        imagePlaneVertexDescriptor.attributes[1].bufferIndex = 0
        imagePlaneVertexDescriptor.layouts[0].stride = 16
        imagePlaneVertexDescriptor.layouts[0].stepRate = 1
        imagePlaneVertexDescriptor.layouts[0].stepFunction = .perVertex
        
        /**
         *  Vertex function to map the texture to the view controller's view
         */
        //pipelineDescriptor.vertexFunction = library.makeFunction(name: "mapTexture")
        pipelineDescriptor.vertexFunction = library.makeFunction(
            name: "drawableQueueVertexShader"
        )
        
        /**
         *  Fragment function to display texture's pixels in the area bounded by vertices of `mapTexture` shader
         */
        pipelineDescriptor.fragmentFunction = library.makeFunction(
            name: "drawableQueueFragmentShader"
        )
        
        pipelineDescriptor.vertexDescriptor = imagePlaneVertexDescriptor
        
        do {
            try renderPipelineState = mtlDevice?.makeRenderPipelineState(descriptor: pipelineDescriptor)
        }
        catch {
            assertionFailure("Failed creating a render state pipeline. Can't render the texture without one. Error: \(error)")
            return
        }
    }
    
    private let planeVertexData: [Float] = [
        -1, -1,  0,  1,
         1, -1,  1,  1,
         -1,  1,  0,  0,
         1,  1,  1,  0
    ]
    
    public let leftQueue: TextureResource.DrawableQueue = {

        // can be whatever you like – 200 × 200 for most GIFs is probably enough
        let descriptor = TextureResource.DrawableQueue.Descriptor(
            pixelFormat: .rgba8Unorm,
            width: 8192,
            height: 4320,
            usage: [.renderTarget, .shaderRead, .shaderWrite],
            mipmapsMode: .none
        )
        
        do {
            let queue = try TextureResource.DrawableQueue(descriptor)
            queue.allowsNextDrawableTimeout = true
            return queue
        } catch {
            fatalError("Could not create DrawableQueue: \(error)")
        }
    }()
    
    public let rightQueue: TextureResource.DrawableQueue = {
        
        // can be whatever you like – 200 × 200 for most GIFs is probably enough
        let descriptor = TextureResource.DrawableQueue.Descriptor(
            pixelFormat: .rgba8Unorm,
            width: 8192,
            height: 4320,
            usage: [.renderTarget, .shaderRead, .shaderWrite],
            mipmapsMode: .none
        )
        
        do {
            let queue = try TextureResource.DrawableQueue(descriptor)
            queue.allowsNextDrawableTimeout = true
            return queue
        } catch {
            fatalError("Could not create DrawableQueue: \(error)")
        }
    }()
    
    public init(fileName:String, ext:String, audioFileName:String) {
        self.audioFileName = audioFileName
        playerItem = AVPlayerItem(asset: AVAsset(url: Bundle.main.url(forResource: fileName, withExtension: ext)!))
        player = AVPlayer(playerItem: _playerItem)
        imageGenerator = AVAssetImageGenerator(asset: _playerItem.asset)

        guard let mtlDevice = mtlDevice else  {
            fatalError()
        }
        
        loader = MTKTextureLoader(device: mtlDevice)
        
        let imagePlaneVertexDataCount = planeVertexData.count * MemoryLayout<Float>.size
        leftImagePlaneVertexBuffer = mtlDevice.makeBuffer(
            bytes: planeVertexData,
            length: imagePlaneVertexDataCount,
            options: []
        )
        rightImagePlaneVertexBuffer = mtlDevice.makeBuffer(
            bytes: planeVertexData,
            length: imagePlaneVertexDataCount,
            options: []
        )
        createDisplayLink()
    }
    
    public func updateAsset(fileName:String, ext:String, audioFileName:String) {
        playerItem = AVPlayerItem(asset: AVAsset(url: Bundle.main.url(forResource: fileName, withExtension: ext)!))
        player.replaceCurrentItem(with: playerItem)
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: Bundle.main.url(forResource: audioFileName, withExtension: "aac")!, fileTypeHint: "aac")
        } catch {
            print(error)
        }
    }
    
    @MainActor
    public func play() async throws {
        initializeRenderPipelineState()
        audioPlayer = try AVAudioPlayer(contentsOf: Bundle.main.url(forResource: audioFileName, withExtension: "aac")!, fileTypeHint: "aac")
        assetReader = try AVAssetReader(asset: playerItem.asset)
        let outputSettings =  [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA]
        trackOutput = try await AVAssetReaderTrackOutput(track: assetReader!.asset.loadTracks(withMediaType: .video).first!, outputSettings:outputSettings as [String : Any])
        assetReader?.add(trackOutput!)
        assetReader?.startReading()
        if leftTextureResource == nil {
            let cgImage = try await imageGenerator.image(at: .zero)
            leftTextureResource = try await TextureResource.generate(from: cgImage.image, options: .init(semantic: .hdrColor))
        }

        leftTextureResource?.replace(withDrawables: leftQueue)
        
        if rightTextureResource == nil{
            let cgImage = try await imageGenerator.image(at: .zero)
            rightTextureResource = try await TextureResource.generate(from: cgImage.image, options: .init(semantic: .hdrColor))
        }
        rightTextureResource?.replace(withDrawables: rightQueue)
        
        let videoOutput = AVPlayerVideoOutput(specification:AVVideoOutputSpecification(tagCollections:[.monoscopicForVideoOutput()]))
        player.videoOutput = videoOutput
        
        var cvret:CVReturn = 0
        // 1. Create a Metal Core Video texture cache from the pixel buffer.
        CVMTLTextureCache.initialize(to: nil)
        CVMTLTexture.initialize(to: nil)
        cvret = CVMetalTextureCacheCreate(
                        kCFAllocatorDefault,
                        nil,
                        mtlDevice!,
                        nil,
                        CVMTLTextureCache);

        guard cvret == kCVReturnSuccess else {
         print("Failed to create Metal texture cache")
            return
        }
        
        player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.03333, preferredTimescale:  CMTimeScale(NSEC_PER_SEC)), queue:.main) { [weak self] time in
            guard let strongSelf = self else {
                return
            }
            Task {
                try await strongSelf.updateFrame()
            }
        }

        
        player.play()
        //audioPlayer.play()
        //createDisplayLink()
        //dateStarted = Date.now
        frameReady = true
    }
    
    public func stop() {
        frameReady = false
        audioPlayer.pause()
        player.pause()
    }
    
    private func pixelBufferToMTLTexture(pixelBuffer:CVPixelBuffer) -> MTLTexture?
    {
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)

        CVMTLTexture.initialize(to: nil)
        var cvret:CVReturn = 0
        // 2. Create a CoreVideo pixel buffer backed Metal texture image from the texture cache.
        
        cvret = CVMetalTextureCacheCreateTextureFromImage(
                        kCFAllocatorDefault,
                        CVMTLTextureCache.pointee!,
                        pixelBuffer, nil,
                        .bgra8Unorm,
                        CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer),
                        0,
                        CVMTLTexture);
        
        
        guard cvret == kCVReturnSuccess else {
         print(cvret == kCVReturnInvalidPixelBufferAttributes)
            print(cvret == kCVReturnInvalidPixelFormat)
            print(cvret == kCVReturnInvalidSize)
print(cvret == kCVReturnPixelBufferNotMetalCompatible)
            

         print("Failed to create CoreVideo Metal texture from image")
            return nil
        }
        
        // 3. Get a Metal texture using the CoreVideo Metal texture referen ce.
        if let pointee = CVMTLTexture.pointee {
            
            let metalTexture = CVMetalTextureGetTexture(pointee);
            CVMTLTexture.deinitialize(count: 1)
            CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)

            return metalTexture
        }
    
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)
        return nil
    }
}


extension ImmersiveViewModel {
    private func createDisplayLink() {
        displayLink = CADisplayLink(target: self, selector:#selector(onFrame(link:)))
        displayLink.add(to: .main, forMode: .default)
    }
}


extension ImmersiveViewModel {
    @MainActor
    func updateFrame() async throws {
            if !frameReady {
                print("frame not ready")
                return
            }
            //let playerTime = CMTime(seconds: abs(strongSelf.dateStarted.timeIntervalSinceNow), preferredTimescale: 1000000)
//                guard let taggedBuffers = videoOutput.taggedBuffers(
//                    forHostTime: CMClockGetTime(.hostTimeClock)
//                ) else { return }
            
            let strongSelf = self
            let commandQueue = mtlDevice?.makeCommandQueue()

            let sampleBuffer = strongSelf.trackOutput?.copyNextSampleBuffer()
            guard let sampleBuffer = sampleBuffer else {
                print("image buffer")
                return
            }
            
            guard let imageBuffer = sampleBuffer.imageBuffer else {
                print("no image buffer")
                return
            }
            
            CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
            
            guard let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer) else {
                print("no base address")
                return
            }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
            let cropWidth = 8192/2
            let cropHeight = 4320
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bytesPerPixel = 4
            let startPoint = [ "x": cropWidth, "y": 0 ]
            let leftStartAddress = baseAddress
            let rightStartAddress = baseAddress + startPoint["y"]! * bytesPerRow + startPoint["x"]! * bytesPerPixel

            let leftContext = CGContext(data: leftStartAddress, width: cropWidth, height: cropHeight, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            
            let rightContext = CGContext(data: rightStartAddress, width: cropWidth, height: cropHeight, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            
            guard let leftContext = leftContext, let rightContext = rightContext else {
                print("no context")
                return
            }
            
            let leftCVPixelBuffer = UnsafeMutablePointer<CVPixelBuffer?>.allocate(capacity: 1)
            leftCVPixelBuffer.initialize(to: nil)
                        
            CVPixelBufferCreateWithBytes(kCFAllocatorDefault, 8192/2, 4320, kCVPixelFormatType_32BGRA, leftContext.data!, bytesPerRow, nil, nil, nil, leftCVPixelBuffer)
            
            let rightCVPixelBuffer = UnsafeMutablePointer<CVPixelBuffer?>.allocate(capacity: 1)
            rightCVPixelBuffer.initialize(to: nil)

            CVPixelBufferCreateWithBytes(kCFAllocatorDefault, 8192/2, 4320, kCVPixelFormatType_32BGRA, rightContext.data!, bytesPerRow, nil, nil, nil, rightCVPixelBuffer)
            
            CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly)
            
            guard let leftImage = leftContext.makeImage(), let rightImage = rightContext.makeImage() else {
                print("no image")
                return
            }
                
            
            let textureLoader = MTKTextureLoader(device:mtlDevice!)
            let leftMtlTexture = try await textureLoader.newTexture(cgImage: leftImage)
            let rightMtlTexture = try await textureLoader.newTexture(cgImage: rightImage)
                            
            if  strongSelf.leftTextureResource != nil{
                let leftDrawable = try strongSelf.leftQueue.nextDrawable()
                let leftTexture = leftDrawable.texture
                guard
                    let leftCommandBuffer = commandQueue?.makeCommandBuffer(),
                    let renderPipelineState =  strongSelf.renderPipelineState
                else {
                    print("Something is missing")
                    return
                }
                
                
                let leftRenderPassDescriptor = MTLRenderPassDescriptor()
                leftRenderPassDescriptor.colorAttachments[0].texture = leftTexture
                leftRenderPassDescriptor.colorAttachments[0].loadAction = .load
                leftRenderPassDescriptor.colorAttachments[0].storeAction = .store
                leftRenderPassDescriptor.renderTargetHeight = 4320
                leftRenderPassDescriptor.renderTargetWidth = 8192
                
                guard let leftRenderEncoder = leftCommandBuffer.makeRenderCommandEncoder(descriptor: leftRenderPassDescriptor) else {
                    return
                }

                // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
                leftRenderEncoder.pushDebugGroup("DrawCapturedLeftImage")
                leftRenderEncoder.setRenderPipelineState(renderPipelineState)
                leftRenderEncoder.setVertexBuffer(strongSelf.leftImagePlaneVertexBuffer, offset: 0, index: 0)
                leftRenderEncoder.setFragmentTexture(leftMtlTexture, index: 0)
                leftRenderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                leftRenderEncoder.endEncoding()
                
                
                leftCommandBuffer.commit()
                leftCommandBuffer.waitUntilCompleted()
                leftDrawable.present()
            }
            
            if strongSelf.rightTextureResource != nil {
                let rightDrawable = try strongSelf.rightQueue.nextDrawable()
                let rightTexture = rightDrawable.texture
                guard
                    let rightCommandBuffer = commandQueue?.makeCommandBuffer(),
                    let renderPipelineState = strongSelf.renderPipelineState
                else {
                    print("Something is missing")
                    return
                }
                let rightRenderPassDescriptor = MTLRenderPassDescriptor()
                rightRenderPassDescriptor.colorAttachments[0].texture = rightTexture
                rightRenderPassDescriptor.colorAttachments[0].loadAction = .load
                rightRenderPassDescriptor.colorAttachments[0].storeAction = .store
                rightRenderPassDescriptor.renderTargetHeight = 4320
                rightRenderPassDescriptor.renderTargetWidth = 8192
                
                guard let rightRenderEncoder = rightCommandBuffer.makeRenderCommandEncoder(descriptor: rightRenderPassDescriptor) else {
                    return
                }
                
                // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
                rightRenderEncoder.pushDebugGroup("DrawCapturedRightImage")
                rightRenderEncoder.setRenderPipelineState(renderPipelineState)
                rightRenderEncoder.setVertexBuffer(strongSelf.rightImagePlaneVertexBuffer, offset: 0, index: 0)
                rightRenderEncoder.setFragmentTexture(rightMtlTexture, index: 0)
                rightRenderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                rightRenderEncoder.endEncoding()
                
                rightCommandBuffer.commit()
                rightCommandBuffer.waitUntilCompleted()
                
                rightDrawable.present()
                print(displayLinkTimestamp)

            } else {
                print("Texture resource is nil")
            }

    }
    
    @objc func onFrame(link:CADisplayLink) {

        displayLinkTimestamp = link.timestamp
    }
    
    func pixelBufferFromCGImage(image: CGImage) -> CVPixelBuffer {
        var pxbuffer: CVPixelBuffer? = nil
        let options: NSDictionary = [:]

        let width =  image.width
        let height = image.height
        let bytesPerRow = image.bytesPerRow

        let dataFromImageDataProvider = CFDataCreateMutableCopy(kCFAllocatorDefault, 0, image.dataProvider!.data)
        let x = CFDataGetMutableBytePtr(dataFromImageDataProvider)

        CVPixelBufferCreateWithBytes(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            x!,
            bytesPerRow,
            nil,
            nil,
            options,
            &pxbuffer
        )
        return pxbuffer!;
    }
}


extension Data {
    public static func from(pixelBuffer:CVPixelBuffer)->Self{
        CVPixelBufferLockBaseAddress(pixelBuffer, [.readOnly])
                defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, [.readOnly]) }
        
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let totalSize = height * bytesPerRow
        
        guard let rawFrame = malloc(totalSize) else { fatalError() }
        let dest = rawFrame
        
        let source = CVPixelBufferGetBaseAddress(pixelBuffer)
        memcpy(dest, source, totalSize)
        
        return Data(bytesNoCopy: rawFrame, count: totalSize, deallocator: .free)
    }
}
