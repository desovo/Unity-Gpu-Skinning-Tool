// SRP Batch: support
// GPU Instancing: not support
// 支持法线变换的骨骼动画 Shader
Shader "GPUSkin/GpuSkinningAnimationWithNormal" 
{
	Properties 
	{
		_BaseMap ("Albedo (RGB)", 2D) = "white" {}
		_Color ("Color", Color) = (1,1,1,1)
        _AnimationTex("Animation Texture", 2D) = "white" {}

		_BoneNum("Bone Num", Int) = 0
        _FrameIndex("Frame Index", Range(0.0, 196)) = 0.0
		_BlendFrameIndex("Blend Frame Index", Range(0.0, 282)) = 0.0
		_BlendProgress("Blend Progress", Range(0.0, 1.0)) = 0.0
	}

	SubShader 
	{
	    HLSLINCLUDE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            struct Attributes
		    {
			    float4 positionOS : POSITION;
                half3 normalOS : NORMAL;
				float2 texcoord : TEXCOORD0;
				float4 boneIndices : TEXCOORD1;
				float4 boneWeights : TEXCOORD2;
				UNITY_VERTEX_INPUT_INSTANCE_ID
		    };
		    struct Varyings
		    {
			    float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
                UNITY_VERTEX_OUTPUT_STEREO
		    };
		    
            CBUFFER_START(UnityPerMaterial)
                half4 _Color;
                float4 _AnimationTex_TexelSize;
                int _BoneNum;
                int _FrameIndex;
                int _BlendFrameIndex;
                float _BlendProgress;
            CBUFFER_END
            
            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

			sampler2D _AnimationTex;
		
			float4x4 QuaternionToMatrix(float4 vec)
			{
				float4x4 ret;
				ret._11 = 2.0 * (vec.x * vec.x + vec.w * vec.w) - 1;
				ret._21 = 2.0 * (vec.x * vec.y + vec.z * vec.w);
				ret._31 = 2.0 * (vec.x * vec.z - vec.y * vec.w);
				ret._41 = 0.0;
				ret._12 = 2.0 * (vec.x * vec.y - vec.z * vec.w);
				ret._22 = 2.0 * (vec.y * vec.y + vec.w * vec.w) - 1;
				ret._32 = 2.0 * (vec.y * vec.z + vec.x * vec.w);
				ret._42 = 0.0;
				ret._13 = 2.0 * (vec.x * vec.z + vec.y * vec.w);
				ret._23 = 2.0 * (vec.y * vec.z - vec.x * vec.w);
				ret._33 = 2.0 * (vec.z * vec.z + vec.w * vec.w) - 1;
				ret._43 = 0.0;
				ret._14 = 0.0;
				ret._24 = 0.0;
				ret._34 = 0.0;
				ret._44 = 1.0;
				return ret;
			}

			float4x4 DualQuaternionToMatrix(float4 m_dual, float4 m_real)
			{
				float4x4 rotationMatrix = QuaternionToMatrix(float4(m_dual.x, m_dual.y, m_dual.z, m_dual.w));
				float4x4 translationMatrix;
				translationMatrix._11_12_13_14 = float4(1, 0, 0, 0);
				translationMatrix._21_22_23_24 = float4(0, 1, 0, 0);
				translationMatrix._31_32_33_34 = float4(0, 0, 1, 0);
				translationMatrix._41_42_43_44 = float4(0, 0, 0, 1);
				translationMatrix._14 = m_real.x;
				translationMatrix._24 = m_real.y;
				translationMatrix._34 = m_real.z;
				float4x4 scaleMatrix;
				scaleMatrix._11_12_13_14 = float4(1, 0, 0, 0);
				scaleMatrix._21_22_23_24 = float4(0, 1, 0, 0);
				scaleMatrix._31_32_33_34 = float4(0, 0, 1, 0);
				scaleMatrix._41_42_43_44 = float4(0, 0, 0, 1);
				scaleMatrix._11 = m_real.w;
				scaleMatrix._22 = m_real.w;
				scaleMatrix._33 = m_real.w;
				scaleMatrix._44 = 1;
				float4x4 M = mul(translationMatrix, mul(rotationMatrix, scaleMatrix));
				return M;
			}

			float4 indexToUV(float index)
			{
				int iIndex = trunc(index + 0.5);
				int row = (int)(iIndex * _AnimationTex_TexelSize.x);
				float col = iIndex - row*_AnimationTex_TexelSize.z;
				return float4((col+0.5)*_AnimationTex_TexelSize.x, (row+0.5) *_AnimationTex_TexelSize.y, 0, 0);
			}

			Varyings Vertex(Attributes input)
			{
				UNITY_SETUP_INSTANCE_ID(input);
				Varyings output;

				float4 boneIndices = input.boneIndices;
				float4 boneWeights = input.boneWeights;
				
				int frameIndex = _FrameIndex;
				int blendFrameIndex = _BlendFrameIndex;
                float blendProgress = _BlendProgress;
                float4 boneUV1;
				float4 boneUV2;
				int frameDataPixelIndex;
				const int DEFAULT_PER_FRAME_BONE_DATASPACE = 2;

				// 正在播放的动画
				frameDataPixelIndex = _BoneNum * frameIndex * DEFAULT_PER_FRAME_BONE_DATASPACE;
				// bone0
				boneUV1 = indexToUV(frameDataPixelIndex + boneIndices[0] * DEFAULT_PER_FRAME_BONE_DATASPACE);
				boneUV2 = indexToUV(frameDataPixelIndex + boneIndices[0] * DEFAULT_PER_FRAME_BONE_DATASPACE + 1);
				float4x4 bone0_matrix = DualQuaternionToMatrix(tex2Dlod(_AnimationTex, boneUV1), tex2Dlod(_AnimationTex, boneUV2));
				// bone1
				boneUV1 = indexToUV(frameDataPixelIndex + boneIndices[1] * DEFAULT_PER_FRAME_BONE_DATASPACE);
				boneUV2 = indexToUV(frameDataPixelIndex + boneIndices[1] * DEFAULT_PER_FRAME_BONE_DATASPACE + 1);
				float4x4 bone1_matrix = DualQuaternionToMatrix(tex2Dlod(_AnimationTex, boneUV1), tex2Dlod(_AnimationTex, boneUV2));
				// bone2
				boneUV1 = indexToUV(frameDataPixelIndex + boneIndices[2] * DEFAULT_PER_FRAME_BONE_DATASPACE);
				boneUV2 = indexToUV(frameDataPixelIndex + boneIndices[2] * DEFAULT_PER_FRAME_BONE_DATASPACE + 1);
				float4x4 bone2_matrix = DualQuaternionToMatrix(tex2Dlod(_AnimationTex, boneUV1), tex2Dlod(_AnimationTex, boneUV2));
				// bone3
				boneUV1 = indexToUV(frameDataPixelIndex + boneIndices[3] * DEFAULT_PER_FRAME_BONE_DATASPACE);
				boneUV2 = indexToUV(frameDataPixelIndex + boneIndices[3] * DEFAULT_PER_FRAME_BONE_DATASPACE + 1);
				float4x4 bone3_matrix = DualQuaternionToMatrix(tex2Dlod(_AnimationTex, boneUV1), tex2Dlod(_AnimationTex, boneUV2));
				
				// 动画Blend
				frameDataPixelIndex = _BoneNum * blendFrameIndex * DEFAULT_PER_FRAME_BONE_DATASPACE;
                // bone0
				boneUV1 = indexToUV(frameDataPixelIndex + boneIndices[0]*DEFAULT_PER_FRAME_BONE_DATASPACE);
				boneUV2 = indexToUV(frameDataPixelIndex + boneIndices[0]*DEFAULT_PER_FRAME_BONE_DATASPACE + 1);
				float4x4 bone0_matrix_blend = DualQuaternionToMatrix(tex2Dlod(_AnimationTex, boneUV1), tex2Dlod(_AnimationTex, boneUV2));
				// bone1
				boneUV1 = indexToUV(frameDataPixelIndex + boneIndices[1]*DEFAULT_PER_FRAME_BONE_DATASPACE);
				boneUV2 = indexToUV(frameDataPixelIndex + boneIndices[1]*DEFAULT_PER_FRAME_BONE_DATASPACE + 1);
				float4x4 bone1_matrix_blend = DualQuaternionToMatrix(tex2Dlod(_AnimationTex, boneUV1), tex2Dlod(_AnimationTex, boneUV2));
				// bone2
				boneUV1 = indexToUV(frameDataPixelIndex + boneIndices[2]*DEFAULT_PER_FRAME_BONE_DATASPACE);
				boneUV2 = indexToUV(frameDataPixelIndex + boneIndices[2]*DEFAULT_PER_FRAME_BONE_DATASPACE + 1);
				float4x4 bone2_matrix_blend = DualQuaternionToMatrix(tex2Dlod(_AnimationTex, boneUV1), tex2Dlod(_AnimationTex, boneUV2));
				// bone3
				boneUV1 = indexToUV(frameDataPixelIndex + boneIndices[3]*DEFAULT_PER_FRAME_BONE_DATASPACE);
				boneUV2 = indexToUV(frameDataPixelIndex + boneIndices[3]*DEFAULT_PER_FRAME_BONE_DATASPACE + 1);
				float4x4 bone3_matrix_blend = DualQuaternionToMatrix(tex2Dlod(_AnimationTex, boneUV1), tex2Dlod(_AnimationTex, boneUV2));
				bone0_matrix = lerp(bone0_matrix, bone0_matrix_blend, blendProgress);
				bone1_matrix = lerp(bone1_matrix, bone1_matrix_blend, blendProgress);
				bone2_matrix = lerp(bone2_matrix, bone2_matrix_blend, blendProgress);
				bone3_matrix = lerp(bone3_matrix, bone3_matrix_blend, blendProgress);

				// 计算顶点位置
				float4 pos =
					mul(bone0_matrix, input.positionOS) * boneWeights[0] +
					mul(bone1_matrix, input.positionOS) * boneWeights[1] +
					mul(bone2_matrix, input.positionOS) * boneWeights[2] +
					mul(bone3_matrix, input.positionOS) * boneWeights[3];
				
				// *** 新增：计算法线变换 ***
				// 法线变换只需要旋转和缩放，不需要位移
				// 使用 3x3 矩阵部分来变换法线
				float3 normalOS = 
					mul((float3x3)bone0_matrix, input.normalOS) * boneWeights[0] +
					mul((float3x3)bone1_matrix, input.normalOS) * boneWeights[1] +
					mul((float3x3)bone2_matrix, input.normalOS) * boneWeights[2] +
					mul((float3x3)bone3_matrix, input.normalOS) * boneWeights[3];
				normalOS = normalize(normalOS);

				// 转换到世界空间
				output.positionWS = TransformObjectToWorld(pos.xyz);
				output.positionCS = TransformWorldToHClip(output.positionWS);
				output.normalWS = TransformObjectToWorldNormal(normalOS);
				output.uv = input.texcoord;

				return output;
			}

			half4 Fragment(Varyings input) : SV_Target
			{
				// 采样基础纹理
				half4 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
				albedo *= _Color;

				// 计算简单的 Lambert 光照
				Light mainLight = GetMainLight();
				float3 normalWS = normalize(input.normalWS);
				float NdotL = saturate(dot(normalWS, mainLight.direction));
				
				// 环境光 + 漫反射
				half3 ambient = half3(0.2, 0.2, 0.2);
				half3 diffuse = mainLight.color * NdotL;
				half3 lighting = ambient + diffuse;

				half4 finalColor = half4(albedo.rgb * lighting, albedo.a);
				return finalColor;
			}
            

	    ENDHLSL
	
		Tags { "RenderType"="Opaque" }
		LOD 100

		Pass
		{
		    Tags { "RenderPipeline" = "UniversalPipeline" "LightMode"="UniversalForward" }
			HLSLPROGRAM
                #pragma vertex Vertex
                #pragma fragment Fragment
                
                // URP 光照所需的多编译指令
                #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
                #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
                #pragma multi_compile _ _SHADOWS_SOFT
			ENDHLSL
		}
		
		// 阴影投射通道
		Pass
        {
            Name "ShadowCaster"
            Tags{"LightMode" = "ShadowCaster"}

            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            struct ShadowAttributes
            {
                float4 positionOS : POSITION;
                half3 normalOS : NORMAL;
                float4 boneIndices : TEXCOORD1;
                float4 boneWeights : TEXCOORD2;
            };

            struct ShadowVaryings
            {
                float4 positionCS : SV_POSITION;
            };

            float4 GetShadowPositionHClip(float3 positionWS, float3 normalWS)
            {
                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                    float3 lightDirectionWS = normalize(_LightPosition - positionWS);
                #else
                    float3 lightDirectionWS = _LightDirection;
                #endif

                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));

                #if UNITY_REVERSED_Z
                    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif

                return positionCS;
            }

            ShadowVaryings ShadowPassVertex(ShadowAttributes input)
            {
                ShadowVaryings output;

                float4 boneIndices = input.boneIndices;
                float4 boneWeights = input.boneWeights;
                
                int frameIndex = _FrameIndex;
                float4 boneUV1, boneUV2;
                int frameDataPixelIndex;
                const int DEFAULT_PER_FRAME_BONE_DATASPACE = 2;

                frameDataPixelIndex = _BoneNum * frameIndex * DEFAULT_PER_FRAME_BONE_DATASPACE;
                
                // 计算骨骼矩阵（与主Pass相同）
                boneUV1 = indexToUV(frameDataPixelIndex + boneIndices[0] * DEFAULT_PER_FRAME_BONE_DATASPACE);
                boneUV2 = indexToUV(frameDataPixelIndex + boneIndices[0] * DEFAULT_PER_FRAME_BONE_DATASPACE + 1);
                float4x4 bone0_matrix = DualQuaternionToMatrix(tex2Dlod(_AnimationTex, boneUV1), tex2Dlod(_AnimationTex, boneUV2));
                
                boneUV1 = indexToUV(frameDataPixelIndex + boneIndices[1] * DEFAULT_PER_FRAME_BONE_DATASPACE);
                boneUV2 = indexToUV(frameDataPixelIndex + boneIndices[1] * DEFAULT_PER_FRAME_BONE_DATASPACE + 1);
                float4x4 bone1_matrix = DualQuaternionToMatrix(tex2Dlod(_AnimationTex, boneUV1), tex2Dlod(_AnimationTex, boneUV2));
                
                boneUV1 = indexToUV(frameDataPixelIndex + boneIndices[2] * DEFAULT_PER_FRAME_BONE_DATASPACE);
                boneUV2 = indexToUV(frameDataPixelIndex + boneIndices[2] * DEFAULT_PER_FRAME_BONE_DATASPACE + 1);
                float4x4 bone2_matrix = DualQuaternionToMatrix(tex2Dlod(_AnimationTex, boneUV1), tex2Dlod(_AnimationTex, boneUV2));
                
                boneUV1 = indexToUV(frameDataPixelIndex + boneIndices[3] * DEFAULT_PER_FRAME_BONE_DATASPACE);
                boneUV2 = indexToUV(frameDataPixelIndex + boneIndices[3] * DEFAULT_PER_FRAME_BONE_DATASPACE + 1);
                float4x4 bone3_matrix = DualQuaternionToMatrix(tex2Dlod(_AnimationTex, boneUV1), tex2Dlod(_AnimationTex, boneUV2));

                // 计算位置和法线
                float4 pos =
                    mul(bone0_matrix, input.positionOS) * boneWeights[0] +
                    mul(bone1_matrix, input.positionOS) * boneWeights[1] +
                    mul(bone2_matrix, input.positionOS) * boneWeights[2] +
                    mul(bone3_matrix, input.positionOS) * boneWeights[3];

                float3 normalOS = 
                    mul((float3x3)bone0_matrix, input.normalOS) * boneWeights[0] +
                    mul((float3x3)bone1_matrix, input.normalOS) * boneWeights[1] +
                    mul((float3x3)bone2_matrix, input.normalOS) * boneWeights[2] +
                    mul((float3x3)bone3_matrix, input.normalOS) * boneWeights[3];
                normalOS = normalize(normalOS);

                float3 positionWS = TransformObjectToWorld(pos.xyz);
                float3 normalWS = TransformObjectToWorldNormal(normalOS);

                output.positionCS = GetShadowPositionHClip(positionWS, normalWS);
                return output;
            }

            half4 ShadowPassFragment(ShadowVaryings input) : SV_TARGET
            {
                return 0;
            }

            ENDHLSL
        }

	}
}
