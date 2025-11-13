// SRP Batch: support
// GPU Instancing: not support
// 支持法线纹理的顶点动画 Shader
Shader "GPUSkin/GpuVerticesAnimationWithNormal" 
{
	Properties
	{
		_BaseMap("Albedo (RGB)", 2D) = "white" {}
		_Color("Color", Color) = (1,1,1,1)
		_AnimationTex("Animation Texture", 2D) = "white" {}
		_AnimationNormalTex("Animation Normal Texture", 2D) = "white" {}

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
                float2 vertIndex : TEXCOORD1;
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
				float4 _AnimationNormalTex_TexelSize;
                int _FrameIndex;
                int _BlendFrameIndex;
                float _BlendProgress;
            CBUFFER_END
            
            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

			// 动画纹理
			sampler2D _AnimationTex;
            // 动画法线纹理
            sampler2D _AnimationNormalTex;

            Varyings Vertex(Attributes input)
			{
				UNITY_SETUP_INSTANCE_ID(input);
                Varyings output;

                // 采样要做半个像素的偏移到像素中心
                float vertexIndex = input.vertIndex[0] + 0.5;
                
                // *** 采样当前帧的顶点位置和法线 ***
                float4 vertexUV = float4((vertexIndex) * _AnimationTex_TexelSize.x, 
                                         (_FrameIndex + 0.5) * _AnimationTex_TexelSize.y, 0, 0);
                float3 pos = tex2Dlod(_AnimationTex, vertexUV).xyz;
                float3 normal = tex2Dlod(_AnimationNormalTex, vertexUV).xyz;

                // *** 如果启用混合，采样下一帧并插值 ***
                if (_BlendProgress > 0.001)
                {
                    float4 blendVertexUV = float4(vertexIndex * _AnimationTex_TexelSize.x, 
                                                  (_BlendFrameIndex + 0.5) * _AnimationTex_TexelSize.y, 0, 0);
                    float3 blendPos = tex2Dlod(_AnimationTex, blendVertexUV).xyz;
                    float3 blendNormal = tex2Dlod(_AnimationNormalTex, blendVertexUV).xyz;
                    
                    pos = lerp(pos, blendPos, _BlendProgress);
                    normal = lerp(normal, blendNormal, _BlendProgress);
                }

                // 归一化法线
                normal = normalize(normal);

                // 转换到世界空间
                output.positionWS = TransformObjectToWorld(pos);
                output.positionCS = TransformWorldToHClip(output.positionWS);
                output.normalWS = TransformObjectToWorldNormal(normal);
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
    
        Tags { "RenderType" = "Opaque" }
        LOD 100

        Pass
        {
            Tags { "RenderPipeline" = "UniversalPipeline" "LightMode"="UniversalForward" }
			HLSLPROGRAM
                #pragma target 3.0
                #pragma multi_compile_instancing
                
                // URP 光照所需的多编译指令
                #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
                #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
                #pragma multi_compile _ _SHADOWS_SOFT
                
                #pragma vertex Vertex
                #pragma fragment Fragment
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
                float2 vertIndex : TEXCOORD1;
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

                float vertexIndex = input.vertIndex[0] + 0.5;
                float4 vertexUV = float4((vertexIndex) * _AnimationTex_TexelSize.x, 
                                         (_FrameIndex + 0.5) * _AnimationTex_TexelSize.y, 0, 0);
                float3 pos = tex2Dlod(_AnimationTex, vertexUV).xyz;
                float3 normal = tex2Dlod(_AnimationNormalTex, vertexUV).xyz;

                // 如果启用混合
                if (_BlendProgress > 0.001)
                {
                    float4 blendVertexUV = float4(vertexIndex * _AnimationTex_TexelSize.x, 
                                                  (_BlendFrameIndex + 0.5) * _AnimationTex_TexelSize.y, 0, 0);
                    float3 blendPos = tex2Dlod(_AnimationTex, blendVertexUV).xyz;
                    float3 blendNormal = tex2Dlod(_AnimationNormalTex, blendVertexUV).xyz;
                    
                    pos = lerp(pos, blendPos, _BlendProgress);
                    normal = lerp(normal, blendNormal, _BlendProgress);
                }

                normal = normalize(normal);
                
                float3 positionWS = TransformObjectToWorld(pos);
                float3 normalWS = TransformObjectToWorldNormal(normal);

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
