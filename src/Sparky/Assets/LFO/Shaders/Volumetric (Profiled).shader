Shader "LFO/Volumetric (Profiled)"
{
    Properties
    {
        [Header(General)]
        _Opacity ("Opacity", Range(0,1)) = 1
        _Brightness ("Brightness", Range(0, 5)) = 1
        _LengthwiseBrightness ("Lengthwise Brightness", Range(0, 20)) = 1
        
        [Space(20)]
        [Header(Color)]
        [HDR] _ColorA ("High Density", Color) = (1,1,1,1)
        [HDR] _ColorB ("Low Density", Color) = (1,0,0,1)
        _ColorOffset ("Falloff", Range(0, 2)) = 1
        
        [Space(20)]
        [Header(Shape)]
        [Header(Falloff)]
        _StartFalloff ("Start", Range(0, 10)) = 0
        _StartFalloffPosition("Position", Range(0,1)) = .5
        _Falloff ("End", Range(0, 20)) = 1
        _EndFalloffPosition("Position", Range(0,1)) = .5
        
        [Space(20)]
        [Header(Profile)]
        [NoScaleOffset]_Profile ("Profile", 2D) = "gray"{}
        
        [Space(20)]
        [Header(Noise)]
        _Noise ("Contrast", Range(0,2)) = 1
        [NoScaleOffset]_NoiseTex ("Noise", 3D) = "gray" {}
        _NoiseTexTilling ("Tilling", Vector) = (1,1,1,0)
        _Velocity ("Speed", Vector) = (0,1,0,0)
        _ShapeNoiseWeights ("RGBA Weights", Vector) = (1,1,1,1)

        [Space(20)]
        [Header(Volumetric Settings)]
        [Enum(Resolution)] _Resolution ("Resolution", float) = 2
        [PowerSlide(3)] _ResolutionMultiplier ("Resolution Multiplier", Range(0.01, 10)) = 1
        _MinimumResolution ("Minimum Resolution", Range(0, 512)) = 8
        _DensityLowerThreshold ("Density Lower threshold", Range(0,1)) = 0
        _DensityUpperThreshold ("Density Upper threshold", Range(0,1)) = 1
        _DensityMultiplier ("Density multiplier", float) = 1
        [Toggle] _CustomZTest ("Custom ZTest?", int) = 1
    }
    SubShader
    {
        Tags {
            "RenderType"="Transparent"
            "Queue"="Transparent"
            "IgnoreProjector" = "True"
        }

        Lighting Off 
        Blend SrcAlpha One, One One
        ZWrite Off
        ZTest Always
        Cull Front

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
            };

            struct v2f {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float4 worldPos : TEXCOORD1;
                float4 objectPos : TEXCOORD2;
                float4 screenPos : TEXCOORD3;
                float3 normal : TEXCOORD4;
                float3 viewVector : TEXCOORD5;
            };
            
            sampler2D _CameraDepthTexture;
            float3 position;
            float3 scale;
            matrix rotation;
            matrix irotation;
            float _TimeOffset;
            
            v2f vert (appdata v) {
                v2f output;
                output.pos = UnityObjectToClipPos(v.vertex);
                output.uv = v.uv;
                output.worldPos = mul(unity_ObjectToWorld, v.vertex);
                output.objectPos = v.vertex;
                output.screenPos = ComputeScreenPos(output.pos);

                output.normal = UnityObjectToWorldNormal(v.normal);                
                float3 viewVector = mul(unity_CameraInvProjection, float4(v.uv * 2 - 1, 0, -1));
                output.viewVector = mul(unity_CameraToWorld, float4(viewVector,0));

                return output;
            }
            
            float _Opacity;
            float _Brightness;

            float4 _ColorA;
            float4 _ColorB;
            float _ColorOffset;
            
            float _Falloff;
            float _EndFalloffPosition;
            float _StartFalloff;
            float _StartFalloffPosition;
            
            Texture2D _Profile;
            SamplerState sampler_Profile;

            float _Noise;
            Texture3D<float4> _NoiseTex;
            SamplerState sampler_NoiseTex;
            float3 _Velocity;
            float3 _NoiseTexTilling;
            float4 _ShapeNoiseWeights;

            float _LengthwiseBrightness;

            int _Resolution;
            float _ResolutionMultiplier;
            int _MinimumResolution;
            int _StepCount;
            float _DensityMultiplier;
            float _DensityLowerThreshold;
            float _DensityUpperThreshold;
            
            bool _CustomZTest;

            //to Object Rotate to World (orw)
            fixed3 orw(fixed3 oPos, int w){
                return mul(rotation,fixed4(oPos,w)).xyz;
                }
            
            // cube() by Simon Green
            bool cube(float3 org, float3 dir, out float near, out float far)
            {
                float3 halfScale = scale/2;

            	// compute intersection of ray with all six bbox planes
            	float3 invR = (1.0/dir);
            	float3 tbot = invR * (-(halfScale) - org);
            	float3 ttop = invR * ((halfScale) - org);
            	
            	// re-order intersections to find smallest and largest on each axis
            	float3 tmin = min (ttop, tbot);
            	float3 tmax = max (ttop, tbot);
            	
            	// find the largest tmin and the smallest tmax
            	float2 t0 = max(tmin.xx, tmin.yz);
            	near = max(t0.x, t0.y);
            	t0 = min(tmax.xx, tmax.yz);
            	far = min(t0.x, t0.y);
                
            	// check for hit
            	return near < far && far > 0.0;
            }

            float SampleDensity(float3 position){
                fixed3 objectPos = mul(unity_WorldToObject,position);
                fixed2 objectNormal = normalize(objectPos.xz);
                fixed yPos = (objectPos.y-.5);
                
                fixed3 samplePos = objectPos;
                fixed3 tiling = _NoiseTexTilling * scale;
                fixed3 speed = _Velocity/tiling;
                samplePos.y += (_Time.y + _TimeOffset) * speed.y;
                samplePos.xz += (_Time.y + _TimeOffset) * speed.xz;
                
                if(length(objectPos.xz) >= 0.499)
                return 0;

                float2 uv = float2(length(objectPos.xz * 2), yPos);

                //Everything lower than radius
                float mask = _Profile.SampleLevel(sampler_Profile, uv,0);

                if(mask == 0)
                    return 0;

                float4 shape = lerp(.5,_NoiseTex.SampleLevel(sampler_NoiseTex, (samplePos) * tiling, 0),_Noise);
                shape*=mask;

                
                float4 normalizedShapeWeights = _ShapeNoiseWeights / dot(_ShapeNoiseWeights, 1);
                float shapeFBM = dot(shape, normalizedShapeWeights);


                float density = shapeFBM;

                if(density < _DensityLowerThreshold)
                    density = min(0, density * (1/density));

                if(density > _DensityUpperThreshold)
                    density = min(density, density * pow(density,2));

                density *= pow(1-min(max(objectPos.y+.5-(1-_StartFalloffPosition), 0),1), _StartFalloff);
                density *= pow(min(max(objectPos.y+.5+(1-_EndFalloffPosition), 0),1), _Falloff);

                density *= (1-yPos) * _LengthwiseBrightness;
                density *= _DensityMultiplier;

                density = saturate(density);
                density *= lerp(_ColorA.a, _ColorB.a, density);

                return density;
            }
            

            fixed4 frag(v2f i) : SV_Target {
                if(_Opacity == 0)
                    return 0;

                //return Linear01Depth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i.screenPos.xy/i.screenPos.w));
                float3 rayPos = _WorldSpaceCameraPos - position;
                float viewLength = length(i.viewVector);
                float3 rayDir = normalize(i.worldPos - rayPos - position);

                float dstToBox = 0;
                float dstToBoxFar = 0;
                if(!cube(orw(rayPos, 0), orw(rayDir,0), dstToBox, dstToBoxFar))
                    return 0;

                float dstInsideBox = dstToBoxFar - dstToBox;

                // point of intersection with the cloud container
                float3 entryPoint = rayPos + rayDir * dstToBox;
                float3 exitPoint = rayPos + rayDir * dstInsideBox;

                float dstTravelled = 0;
                float dstLimit = dstInsideBox;
                int stepCount = (1+_Resolution)*32;
                stepCount *= _ResolutionMultiplier;

                stepCount = max(_MinimumResolution, stepCount);
                float stepSize = dstInsideBox/(stepCount); //Create multiplier for step count to allow for modder customization
                int failSafeCount = stepCount;

                float density = 0;
                float4 entryClipPos = UnityWorldToClipPos(float4(entryPoint + position, 0));
                float4 exitClipPos = UnityWorldToClipPos(float4(exitPoint + position, 0));

                const int DEPTH_PROBE_RESOLUTION = 1;
                float depthValue[DEPTH_PROBE_RESOLUTION];
                    for(int i = 1; i <= DEPTH_PROBE_RESOLUTION; i++){
                        
                        float4 clipPos = lerp(entryClipPos, exitClipPos, (i-1)/DEPTH_PROBE_RESOLUTION);
                        float4 screenPos = ComputeScreenPos(clipPos);
                        float2 uv = screenPos.xy/screenPos.w;
                        float depthSolid = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv));
                        //float depthSolid = LinearEyeDepth(clipPos.z/clipPos.w);
                        depthValue[i-1] = depthSolid;
                        }
                while(dstTravelled < dstLimit){
                    failSafeCount -= 1;
                    if(failSafeCount < 0)
                        break;
                    
                    float3 currentPos = entryPoint + rayDir * dstTravelled;
                    dstTravelled += stepSize;

                    float4 clipCurPos = UnityWorldToClipPos(float4(currentPos + position, 1));
                    float depthCurPos = LinearEyeDepth(clipCurPos.z/clipCurPos.w);
                    float depthSolid = depthValue[(dstTravelled/dstLimit) * DEPTH_PROBE_RESOLUTION];

                    if(depthCurPos > depthSolid && _CustomZTest)
                        continue;
                    density += SampleDensity(currentPos)* (stepSize / (length(scale)/27));
                    }
                float4 col = saturate(density);

                col *= lerp(_ColorB, _ColorA, saturate(pow(density, _ColorOffset)));
                col *= _Brightness;
                col.a *= _Opacity;

                return col;
            }


            ENDCG
        }
    }
}
