//
//  ViewController.swift
//  SceneKitOffscreen
//
//  Created by Lachlan Hurst on 24/10/2015.
//  Copyright © 2015 Lachlan Hurst. All rights reserved.
//

import UIKit
import SceneKit
import Metal

class ViewController: UIViewController, SCNSceneRendererDelegate {
    @IBOutlet var scnView1: SCNView!
    @IBOutlet var scnView2: SCNView!

    var scene1:SCNScene!
    var scene2:SCNScene!
    
    var plane:SCNGeometry!
    
    var device:MTLDevice!
    var commandQueue: MTLCommandQueue!
    var renderer: SCNRenderer!
    
    var offscreenTexture:MTLTexture!
    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerPixel = Int(4)
    let bitsPerComponent = Int(8)
    let bitsPerPixel:Int = 32
    var textureSizeX:Int = 1024
    var textureSizeY:Int = 1024
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        setupMetal()
        setupTexture()

        // setup scene 1 - the main scene
        scene1 = SCNScene()
        
        // setup camera
        let camera = SCNCamera()
        camera.zNear = 0.01
        camera.zFar = 10000.0
        camera.fieldOfView = 60

        let cameraNode = SCNNode()
        cameraNode.camera = camera
        
        cameraNode.position = SCNVector3Make(0.0, 30, 100)
        cameraNode.eulerAngles = SCNVector3Make(GLKMathDegreesToRadians(-10), GLKMathDegreesToRadians(0), GLKMathDegreesToRadians(0))
        scene1.rootNode.addChildNode(cameraNode)
        
        // setup ambient light
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = UIColor(white: 1.0, alpha: 1.0)
        let ambientLightNode = SCNNode()
        ambientLightNode.light = ambientLight
        scene1.rootNode.addChildNode(ambientLightNode)

        // set up directional light
        let directLight = SCNLight()
        directLight.type = .directional
        directLight.color = UIColor.white
        directLight.castsShadow = true
        directLight.shadowColor = UIColor.black.withAlphaComponent(0.8)
        directLight.shadowMode = .deferred
        let directLightNode = SCNNode()
        directLightNode.light = directLight
        directLightNode.eulerAngles = SCNVector3Make(GLKMathDegreesToRadians(-90), GLKMathDegreesToRadians(60), GLKMathDegreesToRadians(60))
        scene1.rootNode.addChildNode(directLightNode)
        
        // setup floor
        let floorMaterial = SCNMaterial()
        floorMaterial.diffuse.contents = UIColor.white
        let floor = SCNFloor()
        floor.materials = [floorMaterial]
        floor.reflectivity = 0.5
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(x: 0, y: 0, z: 0)
        scene1.rootNode.addChildNode(floorNode)
        
        // setup box
        let box = SCNBox(width: 10, height: 10, length: 10, chamferRadius: 0)
        box.firstMaterial?.diffuse.contents = UIColor.red
        let boxNode = SCNNode(geometry: box)
        boxNode.position = SCNVector3(x: 0, y: 5, z: 0)
        scene1.rootNode.addChildNode(boxNode)
        
        // setup scene2: just a plane with offscreen texture rendered scene1
        scene2 = SCNScene()
        plane = SCNPlane(width: 10, height: 10)
        let planeNode = SCNNode(geometry: plane)
        plane.materials.first?.diffuse.contents = offscreenTexture
        scene2.rootNode.addChildNode(planeNode)

        // setup scene view 1
        scnView1.scene = scene1
        scnView1.pointOfView = cameraNode
        scnView1.backgroundColor = UIColor.green
        scnView1.allowsCameraControl = true
        scnView1.isPlaying = true
        scnView1.delegate = self // receive events from view 1

        // setup scene view 2
        scnView2.scene = scene2
        scnView2.backgroundColor = UIColor.green
        scnView2.autoenablesDefaultLighting = true
        scnView2.isPlaying = true
    }

    func renderer(_ renderer: SCNSceneRenderer, willRenderScene scene: SCNScene, atTime time: TimeInterval) {
        // scnView1 updated, do offscreen render
        doRender()
    }
    
    func doRender() {
        //rendering to a MTLTexture, so the viewport is the size of this texture
        let viewport = CGRect(x: 0, y: 0, width: CGFloat(textureSizeX), height: CGFloat(textureSizeY))
        
        //write to offscreenTexture, clear the texture before rendering using green, store the result
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = offscreenTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        let commandBuffer = commandQueue.makeCommandBuffer()!
        
        // reuse scene1 and the current point of view
        renderer.scene = scene1
        renderer.pointOfView = scnView1.pointOfView
        renderer.autoenablesDefaultLighting = true
        renderer.render(atTime: 0, viewport: viewport, commandBuffer: commandBuffer, passDescriptor: renderPassDescriptor)

        commandBuffer.commit()
    }
    
    func setupMetal() {
        if let defaultMtlDevice = MTLCreateSystemDefaultDevice() {
            device = defaultMtlDevice
            commandQueue = device.makeCommandQueue()
            renderer = SCNRenderer(device: device, options: nil)
        } else {
            fatalError("no metal device found!")
        }
    }
    
    func setupTexture() {
        var rawData0 = [UInt8](repeating: 0, count: Int(textureSizeX) * Int(textureSizeY) * 4)
        
        let bytesPerRow = 4 * Int(textureSizeX)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        
        let context = CGContext(data: &rawData0, width: Int(textureSizeX), height: Int(textureSizeY), bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: rgbColorSpace, bitmapInfo: bitmapInfo)!
        context.setFillColor(UIColor.green.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(textureSizeX), height: CGFloat(textureSizeY)))

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: MTLPixelFormat.rgba8Unorm, width: Int(textureSizeX), height: Int(textureSizeY), mipmapped: false)
        
        textureDescriptor.usage = MTLTextureUsage(rawValue: MTLTextureUsage.renderTarget.rawValue | MTLTextureUsage.shaderRead.rawValue)
        
        let texture = device.makeTexture(descriptor: textureDescriptor)!
        
        let region = MTLRegionMake2D(0, 0, Int(textureSizeX), Int(textureSizeY))
        texture.replace(region: region, mipmapLevel: 0, withBytes: &rawData0, bytesPerRow: Int(bytesPerRow))

        offscreenTexture = texture
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

}

