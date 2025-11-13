# Unity GPU Skinning Tool - Implementation Analysis

## 1. Project Overview

This project is a GPU skeletal skinning plugin implemented on Unity 2021.3.0f1 Universal RP. The core concept is to **transfer traditional CPU-based skeletal animation skinning calculations to the GPU**, thereby improving animation rendering performance for large numbers of identical models.

## 2. Core Implementation Principles

### 2.1 Basic Principle

Traditional skeletal animation calculates bone transformation matrices on the CPU each frame, then applies them to each vertex. The innovation of this project:

1. **Pre-calculation**: Calculate all bone matrices for all frames of skeletal animation in the editor phase
2. **Texture Storage**: Encode and store these bone matrix data in textures
3. **GPU Sampling**: Sample animation textures in shaders at runtime to retrieve bone matrices
4. **GPU Skinning**: Complete vertex skinning calculations in the Vertex Shader

### 2.2 Bone Matrix Calculation Formula

```
Bone Matrix = boneNode.localToWorldMatrix × boneBindPose
```

This formula involves two steps:
1. **Model Space → Bone Space**: Transform vertices from model space to bone node coordinate system using boneBindPose (bind pose stored in Mesh)
2. **Bone Space → Model Space**: Transform vertices back to model space using bone.localToWorldMatrix (records bone transformation during animation playback)

## 3. Technical Implementation Details

### 3.1 Data Structure Design

#### GpuSkinningAnimData (Animation Data)
```csharp
public class GpuSkinningAnimData : ScriptableObject
{
    public int texWidth;        // Animation texture width
    public int texHeight;       // Animation texture height
    public GpuSkinningAnimClip[] clips;  // Animation clip array
    public int totalFrame;      // Total frame count
    public int totalBoneNum;    // Bone count
    public float min;           // Data range minimum
    public float max;           // Data range maximum
}
```

#### GpuSkinningAnimClip (Animation Clip)
```csharp
public class GpuSkinningAnimClip
{
    public string name;         // Animation name
    public int startFrame;      // Start frame
    public int endFrame;        // End frame
    public float frameRate;     // Frame rate
}
```

### 3.2 Animation Texture Encoding Schemes

The project supports two animation types:

#### 1. Skeletal Animation
- **Stored Content**: Transformation matrices for each bone (rotation + translation + scale)
- **Texture Format**: RGBAHalf (16-bit float per channel)
- **Storage Method**:
  - Each bone per frame occupies 2 pixels
  - Pixel 1: Stores quaternion rotation (rotation.xyzw)
  - Pixel 2: Stores translation (translation.xyz) and scale (scale.magnitude)
- **Texture Size Calculation**:
  ```
  totalPixels = boneNum × 2 × totalFrames
  Calculate appropriate texture width/height based on totalPixels (starting from 32×32, incrementing by powers of 2)
  ```

#### 2. Vertex Animation
- **Stored Content**: World position and normal for each vertex at each frame
- **Texture Format**: RGBAHalf
- **Storage Method**:
  - Position texture: Each vertex per frame occupies 1 pixel storing position (xyz)
  - Normal texture: Each vertex per frame occupies 1 pixel storing normal (xyz)
- **Texture Size**:
  ```
  texWidth = vertexCount
  texHeight = totalFrames
  ```

### 3.3 Data Generation Workflow

#### Editor Tool Workflow (GpuSkinningInstGenerator)

1. **Bone Reordering** (resortBone)
   - Traverse all bones in SkinnedMeshRenderer
   - Build mapping from bone Transform to global bone ID

2. **Mesh Rebuilding** (rebuildAllMeshes)
   - Duplicate original Mesh
   - Store bone indices in UV1 channel (boneIndices)
   - Store bone weights in UV2 channel (boneWeights)
   - Record bindPose matrix for each bone

3. **Animation Sampling** (samplerAnimationClipBoneMatrices)
   - Sample each frame of each animation clip
   - Use AnimationClip.SampleAnimation to get bone transformations
   - Calculate bone matrix: `bone.localToWorldMatrix × bindPose`

4. **Texture Generation**
   - **Skeletal Animation** (generateTexAndMesh):
     - Extract bone matrix rotation (convert to quaternion)
     - Extract translation and scale
     - Encode into texture pixels
   
   - **Vertex Animation** (generateTexAndMesh_verticesAnim):
     - Apply bone transformation to each vertex:
       ```
       position = Σ(boneMatrix[i] × weight[i]) × vertex
       ```
     - Store calculated vertex positions and normals in texture
     - Optionally use an animation frame as static vertex data for Mesh

5. **Material and Prefab Generation**
   - Create material using corresponding Shader
   - Bind animation texture and main texture
   - Generate Prefab containing MeshFilter, MeshRenderer, and animation control components

### 3.4 Shader Implementation

#### Skeletal Animation Shader (GpuSkinningAnimation.shader)

**Vertex Shader Core Logic**:
```hlsl
// 1. Get bone indices and weights (from UV1 and UV2)
float4 boneIndices = input.boneIndices;
float4 boneWeights = input.boneWeights;

// 2. Calculate starting position of current frame's bone data in texture
int frameDataPixelIndex = _BoneNum * frameIndex * 2;

// 3. Process each bone affecting current vertex
for (int i = 0; i < 4; i++) {
    int boneIndex = boneIndices[i];
    float weight = boneWeights[i];
    
    // 4. Sample animation texture to get bone transformation data
    int pixelIndex = frameDataPixelIndex + boneIndex * 2;
    float4 rotation = tex2Dlod(_AnimationTex, indexToUV(pixelIndex));
    float4 translation = tex2Dlod(_AnimationTex, indexToUV(pixelIndex + 1));
    
    // 5. Convert quaternion to matrix
    float4x4 boneMatrix = DualQuaternionToMatrix(rotation, translation);
    
    // 6. Weighted accumulation
    finalMatrix += boneMatrix * weight;
}

// 7. Apply final transformation matrix
float4 positionOS = mul(finalMatrix, input.positionOS);
```

**Key Technical Points**:

1. **UV Coordinate Calculation** (indexToUV):
   ```hlsl
   float4 indexToUV(float index) {
       int iIndex = trunc(index + 0.5);
       int row = (int)(iIndex * _AnimationTex_TexelSize.x);
       float col = iIndex - row * _AnimationTex_TexelSize.z;
       // Add 0.5 offset to pixel center (required for Point filter mode)
       return float4((col+0.5)*_AnimationTex_TexelSize.x, 
                     (row+0.5)*_AnimationTex_TexelSize.y, 0, 0);
   }
   ```

2. **Quaternion to Matrix** (QuaternionToMatrix):
   - Convert stored quaternion rotation to 4×4 transformation matrix
   - Includes rotation, translation, and scale information

3. **Frame Blending** (optional):
   - Support blending between current and next frame (_BlendFrameIndex and _BlendProgress)
   - Enable smooth animation transitions

#### Vertex Animation Shader (GpuVerticesAnimation.shader)

```hlsl
// 1. Get vertex index (from UV1)
float vertexIndex = input.vertexIndex.x;

// 2. Sample animation texture
float2 uv = float2(vertexIndex / _AnimationTex_TexelSize.z, 
                   frameIndex / _AnimationTex_TexelSize.w);
float3 position = tex2Dlod(_AnimationTex, float4(uv, 0, 0)).xyz;
float3 normal = tex2Dlod(_AnimationNormalTex, float4(uv, 0, 0)).xyz;

// 3. Directly use sampled position and normal
output.positionCS = TransformObjectToHClip(float4(position, 1));
```

### 3.5 Runtime Animation Control

#### GPUSkinningAnimation Class

Manages animation playback logic:
```csharp
public class GPUSkinningAnimation
{
    private float currentTime;          // Current playback time
    private GpuSkinningAnimClip currentClip;  // Current animation clip
    private bool isLoop;                // Whether to loop
    
    public void Update(float deltaTime) {
        currentTime += deltaTime * timeScale;
        
        // Calculate current frame index
        float frameIndex = currentClip.startFrame + 
                          (currentTime / currentClip.getPerFrameDuration());
        
        // Loop or clamp
        if (frameIndex > currentClip.endFrame) {
            if (isLoop) {
                frameIndex = currentClip.startFrame + 
                            (frameIndex - currentClip.startFrame) % currentClip.Length();
            } else {
                frameIndex = currentClip.endFrame;
            }
        }
    }
}
```

#### Parameter Passing Methods

The project provides multiple ways to pass animation parameters to shaders:

1. **Direct Material Property Setting** (basic approach)
   ```csharp
   material.SetInt("_FrameIndex", frameIndex);
   ```

2. **Modify Model Matrix** (ModifyModelMatrixGPUSkinningAnimator)
   - Pass animation frame information via transform.localScale
   - Extract data from UNITY_MATRIX_M in shader
   - Advantage: Doesn't break GPU Instancing

3. **MaterialPropertyBlock** (GPUSkinningAnimator)
   ```csharp
   materialPropertyBlock.SetVector("_AnimatorData", 
       new Vector3(frameIndex, blendFrameIndex, blendProgress));
   meshRenderer.SetPropertyBlock(materialPropertyBlock);
   ```
   - Advantage: Doesn't break model matrix, supports SRP Batcher
   - Allows each instance to play different animations

4. **Noise Map Control** (NoiseGpuVerticesAnimation)
   - Use noise texture to have instances at different positions in different animation frames
   - Suitable for large-scale scenes (e.g., grass, particles)

## 4. Data Compression and Optimization

### 4.1 Float16 Encoding Scheme

To run on devices that don't support RGBAHalf, the project implements custom Float16 encoding:

- **Format**: 1 sign bit + 7 integer bits + 8 fractional bits
- **Range**: -127 to 127
- **Precision**: 1/256 ≈ 0.0039

**Encoding Process** (convertFloat32toFloat16Bytes):
```csharp
byte[] convertFloat32toFloat16Bytes(float srcValue) {
    int integer = (int)srcValue;
    float floats = srcValue - integer;
    
    // Sign bit
    data[0] = srcValue > 0 ? 0 : 1;
    
    // Integer bits (7 bits)
    // Convert integer to binary...
    
    // Fractional bits (8 bits)
    for (int i = 0; i < 8; i++) {
        floats *= 2;
        data[i] = (int)floats;
        floats -= (int)floats;
    }
    
    // Pack into 2 bytes
    return result;
}
```

**Decoding Process** (convertFloat16BytesToHalf in Shader):
```hlsl
float convertFloat16BytesToHalf(int data1, int data2) {
    int flag = data1 / 128;  // Sign bit
    float result = (data1 - flag * 128) + (data2 / 256.0);
    result = result - 2 * flag * result;  // Apply sign
    return result;
}
```

### 4.2 Frame Rate Compression

Supports reducing animation frame rate to save texture memory:

```csharp
// Compression rate of 0.5 means using half the frames
float compression = 0.5f;
int clipFrame = (int)(clip.frameRate * clip.length / compression);
```

Combined with frame blending in shader, even 15fps animations can remain smooth.

### 4.3 Texture Size Optimization

- **Skeletal Animation**: Texture size = f(bone count × frame count)
  - Example: 30 bones, 100 frames → 6000 pixels → 128×64 texture
  
- **Vertex Animation**: Texture size = vertex count × frame count
  - Example: 1000 vertices, 100 frames → 1000×100 texture
  - **Note**: Vertex animation textures are typically much larger than skeletal animation

## 5. Use Cases and Performance Characteristics

### 5.1 Six Example Scenes

1. **Scene 0**: Vertex animation + single model
2. **Scene 1**: Skeletal animation + single model
3. **Scene 2**: Skeletal animation + GPU Instancing (large number of identical models)
4. **Scene 3**: Vertex animation + noise map (different positions at different frames)
5. **Scene 4**: Vertex animation + modify Model matrix (supports frame blending and compression)
6. **Scene 5**: Vertex animation + MaterialPropertyBlock (most flexible approach)

### 5.2 Performance Advantages

| Traditional Approach | GPU Skinning |
|---------------------|-------------|
| CPU calculates bone matrices each frame | GPU samples pre-calculated textures |
| Each instance has independent Draw Call | Supports GPU Instancing |
| Low memory usage | Requires additional animation textures |
| Suitable for few complex models | Suitable for many identical models |

**Suitable Scenarios**:
- ✅ Large numbers of identical characters in battle scenes (e.g., RTS, MOBA)
- ✅ Grass, tree, and other vegetation animations
- ✅ Complex animations in particle systems
- ❌ Single high-precision character (traditional approach is better)

### 5.3 Limitations and Considerations

1. **Memory Usage**: Animation textures occupy VRAM, requiring trade-offs
2. **Animation Precision**: Depends on texture precision, may have slight errors
3. **Mesh Requirements**:
   - All sub-meshes must use the same main texture
   - UV1 and UV2 are used for bone data, cannot be used for other purposes
4. **No Hierarchy Preservation**: Generated Prefab is a flattened single Mesh
5. **Bone Mapping**: Need to correctly handle bone index mapping for different SkinnedMeshRenderers

## 6. Workflow

### 6.1 Export Process

1. Select "Window" → "GpuSkinningTool" from menu bar
2. Select FBX model to convert
3. Select animation clips to export
4. Choose generation type (skeletal or vertex animation)
5. Set compression rate (optional)
6. Check texture size preview
7. Click "Generate" button

### 6.2 Generated Assets

- **Animation Data**: `xxx_Data.asset` or `xxx_VertData.asset`
- **Animation Texture**: `xxx.animMap.asset`
- **Normal Texture**: `xxx.animNormalMap.asset` (vertex animation only)
- **Mesh**: `xxx_Mesh.asset` or `xxx_VertMesh.asset`
- **Material**: `xxx_Mat.mat`
- **Prefab**: `xxx_Pre.prefab`

### 6.3 Runtime Usage

```csharp
// Method 1: Using GpuSkinningInstance (simple)
GpuSkinningInstance instance = prefab.GetComponent<GpuSkinningInstance>();

// Method 2: Using GPUSkinningAnimator (advanced)
GPUSkinningAnimator animator = prefab.GetComponent<GPUSkinningAnimator>();
animator.PlayAnimation("Run", loop: true);
animator.animatorSpeed = 1.5f;  // Playback speed

// Method 3: Using ModifyModelMatrixGPUSkinningAnimator
ModifyModelMatrixGPUSkinningAnimator animator = 
    prefab.GetComponent<ModifyModelMatrixGPUSkinningAnimator>();
animator.PlayAnimation("Attack", onEndHandler: () => {
    Debug.Log("Attack animation finished!");
});
```

## 7. Technical Evolution History

The project has undergone several important updates reflecting continuous optimization:

1. **2019/11/27**: Changed from RGBAHalf to RGBA32, implemented custom Float16 to support OpenGL ES2.0
2. **2019/12/01**: Added vertex animation support to solve slow bone calculation on low-end devices
3. **2020/04/20**: Changed from MessagePack binary to direct texture export, reducing GC pressure
4. **2021/05/03**: Added Model matrix modification approach, supports frame blending and interpolation
5. **2021/06/03**: Added frame rate compression feature
6. **2022/09/04**: Added URP support, using MaterialPropertyBlock, upgraded to RGBAHalf

## 8. Summary

This project is a complete GPU Skinning solution with the core concept of **trading VRAM for performance**. By pre-baking animation data into textures and transferring skinning calculations from CPU to GPU, it's particularly suitable for scenes requiring rendering of large numbers of identical characters.

**Key Technical Points**:
- Pre-calculation and texture encoding of bone matrices
- Matrix sampling and vertex transformation in shaders
- Multiple parameter passing methods to adapt to different rendering pipelines
- Custom Float16 encoding for improved compatibility
- Frame rate compression and blending to optimize memory and visual effects

**Design Highlights**:
- Provides 6 different usage methods covering various scenarios
- Good compatibility, supporting OpenGL ES2.0 to modern URP
- Complete editor tools, easy to use
- Detailed comments and documentation, easy to understand and extend
