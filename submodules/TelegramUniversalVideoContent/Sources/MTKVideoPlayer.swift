import UIKit
import Metal
import MetalKit
import FFMpegBinding

class HlsPlayerView: MTKView {
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var texture: MTLTexture?
    private var vertices: MTLBuffer?
    private var textureCoordinates: MTLBuffer?
    private var sizeRect:CGRect?
    private var previousWidth:Int = 0;
    private var previousHeight:Int = 0;
    private var numVertices:Int = 0;
    private var viewPortSize:vector_uint2 = vector_uint2(0, 0);
    
    private let metalCode = """
   #include <metal_stdlib>
   #include <simd/simd.h>

   using namespace metal;

   typedef struct
   {
       vector_float2 position;
       vector_float2 textureCoordinate;
   } AAPLVertex;
   struct RasterizerData
   {
       float4 position [[position]];
       float2 textureCoordinate;
   };

   vertex RasterizerData
   vertexShader(uint vertexID [[ vertex_id ]],
                constant AAPLVertex *vertexArray [[ buffer(0) ]],
                constant vector_uint2 *viewportSizePointer  [[ buffer(1) ]])

   {

       RasterizerData out;

       float2 pixelSpacePosition = vertexArray[vertexID].position.xy;

       float2 viewportSize = float2(*viewportSizePointer);
       out.position = vector_float4(0.0, 0.0, 0.0, 1.0);
       out.position.xy = pixelSpacePosition / (viewportSize / 2.0);
       out.textureCoordinate = vertexArray[vertexID].textureCoordinate;

       return out;
   }

   fragment float4
   samplingShader(RasterizerData in [[stage_in]],
                  texture2d<half> colorTexture [[ texture(0)]])
   {
       constexpr sampler textureSampler (mag_filter::linear,
                                         min_filter::linear);

       const half4 colorSample = colorTexture.sample(textureSampler, in.textureCoordinate);
       return float4(colorSample);
   }
   """
    
    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        self.device = device ?? MTLCreateSystemDefaultDevice()
        self.sizeRect = frameRect
        self.configureMetalView()
        self.createRenderPipeline()
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    public func updateFrame(frame frameRect:CGRect){
        self.sizeRect = frameRect;
        super.frame = frameRect;
        
    }
    
    private func configureMetalView() {
        self.colorPixelFormat = .bgra8Unorm
        self.framebufferOnly = true
    }
    
    private func createRenderPipeline() {
        guard let device = self.device else { return }
        
        let library = try! device.makeLibrary(source: metalCode, options: nil)
        let vertexFunction = library.makeFunction(name: "vertexShader")
        let fragmentFunction = library.makeFunction(name: "samplingShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        
        pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        commandQueue = device.makeCommandQueue()
    }
    
    
    
    func updateFrame(with pixelData: UnsafePointer<UInt8>, width: Int, height: Int) {
        guard let device = self.device else { return }

        if (width != previousWidth || height != previousHeight){
            let f_width = Float(width)
            let f_height = Float(height)
            // reset the vertices
            let quadVertices:[Float] =
          [
              // Pixel positions, Texture coordinates
                f_width,-f_height, 1.0, 1.0 ,
               -f_width,-f_height, 0.0, 1.0,
               -f_width, f_height, 0.0, 0.0 ,
                f_width,-f_height, 1.0, 1.0 ,
               -f_width, f_height, 0.0, 0.0 ,
                f_width, f_height, 1.0, 0.0 ,
          ]
            vertices = device.makeBuffer(bytes: quadVertices, length: quadVertices.count * MemoryLayout<Float>.size, options: [])
            
            // Calculate the number of vertices by dividing the byte length by the size of each vertex
            numVertices = 6;
        }
        previousWidth=width;
        previousHeight=height;
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        
        texture = device.makeTexture(descriptor: textureDescriptor)
        
        
        guard let texture = texture else {
            print("Failed to create texture")
            return
        }
        
        let bytesPerRow = width * 4
        
        
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.replace(region: region,
                        mipmapLevel: 0,
                        withBytes: pixelData,
                        bytesPerRow: bytesPerRow)
        
        self.draw()
    }
    
    override func draw(_ rect: CGRect) {
        if (self.currentDrawable == nil){
            return;
        }
        guard let drawable = self.currentDrawable,
              let pipelineState = pipelineState,
              let vertices = vertices,
              let sizeRect = self.sizeRect,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let renderPassDescriptor = self.currentRenderPassDescriptor,
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        commandBuffer.label="CommandBuffer";
        renderEncoder.label = "RenderEncoder";
        
        renderEncoder.setRenderPipelineState(pipelineState);
        renderEncoder.setVertexBuffer(vertices, offset: 0, index: 0);
        viewPortSize.x = UInt32(sizeRect.width);
        viewPortSize.y = UInt32(sizeRect.height);
        renderEncoder.setVertexBytes(&viewPortSize, length:MemoryLayout<vector_uint2>.size , index: 1);
        // set the texture
        renderEncoder.setFragmentTexture(texture, index: 0);
        // draw the triangle
        renderEncoder.drawPrimitives(type:MTLPrimitiveType.triangle , vertexStart:0, vertexCount: numVertices);
        
        renderEncoder.endEncoding();
        commandBuffer.present(drawable);
        commandBuffer.commit();
        
        
        
        
        
    }
}


