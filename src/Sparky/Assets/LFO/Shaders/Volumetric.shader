Shader "LFO/Volumetric"
{
    Properties
    {
        [Header(General)]
        _Opacity ("Opacity", Range(0,1)) = 1
        _Brightness ("Brightness", Range(0, 5)) = 1

        //Add Middle Color
        //Add Middle offset (towards high and low by -1 to 1)
        [Space(20)]
        [Header(Color)]
        [HDR] _ColorHigh ("High", Color) = (1,1,1,1)
        _ColorHighPosition ("Position", Range(0.002,1)) = 3
        [HDR] _ColorMedium ("Medium", Color) = (1,0,0,1)
        _ColorMediumPosition ("Position", Range(0.001,0.999)) = .5
        [HDR] _ColorLow ("Low", Color) = (1,0,0,1)
        _ColorLowPosition ("Position", Range(0,0.998)) = 0
        _ColorOffset ("Falloff", Range(0, 2)) = 1
        _ColorShift ("Shift", Range(-1, 1)) = 0
        [Toggle] _SaturateColor ("Saturate color?", int) = 1

        [Space(20)]
        [Header(Shape)]
        _Radius ("Radius", Range(0,1)) = .1
        [Toggle] _Hollow ("Is Hollow?", int) = 0
        _InnerRadius ("Inner Radius", Range(0,1)) = 0
        [Header(Falloff)]
        _StartFalloff ("Start", Range(0, 20)) = 0
        _StartPosition ("Position", Range(0,1)) = .2
        _Falloff ("End", Range(0, 20)) = 1
        _EndPosition ("Position", Range(0,1)) = .5
        _RadialFalloff ("Outter", Range(0, 5)) = 1
        _RadialFalloffPosition ("Position", Range(0, 1)) = .9
        [Header(Expansion)]
        _LinearExpansion ("Linear", Range(-2, 2)) = 0
        _QuadraticExpansion ("Quadratic", Range(-2, 2)) = 0

        [Space(20)]
        [Header(Noise)]
        _Noise ("Contrast", Range(0,2)) = 1
        [NoScaleOffset] _NoiseTex ("Noise", 3D) = "white" {}
        _NoiseTexTilling ("Tilling", Vector) = (1,1,1,0)
        _Velocity ("Speed", Vector) = (0,1,0,0)
        _ShapeNoiseWeights ("RGBA Weights", Vector) = (1,1,1,1)

        [Space(20)]
        [Header(Volumetric Settings)]
        [Enum(Resolution)] _Resolution ("Resolution", float) = 2
        [PowerSlide(3)] _ResolutionMultiplier ("Resolution Multiplier", Range(0.01, 10)) = 1
        _MinimumResolution ("Minimum Resolution", Range(0, 512)) = 8
        _DensityLowerThreshold ("Lower threshold", Range(0,0.999)) = 0
        _DensityUpperThreshold ("Upper threshold", Range(0.001,1)) = 1
        _DensityLowerClip ("Lower Clip", Range(0,0.999)) = 0
        _DensityUpperClip ("Upper Clip", Range(0.001,1)) = 1
        _DensityMultiplier ("Density multiplier", float) = 1
        _ExpansionDensityInvMultiplier ("Inverse Expansion multiplier", Range(-2, 2)) = 1
        [Toggle] _CustomZTest ("Custom ZTest?", int) = 1
    }
    SubShader
    {
        Tags {
            "RenderType"="Transparent"
            "Queue"="Transparent"
        }
        Blend SrcAlpha One
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

            struct fragOutput {
                fixed4 color : SV_Target;
                float depth : SV_Depth;
            };

            
            float3 position;
            float3 scale;
            matrix rotation;

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

            bool _Hollow;

            float4 _ColorHigh;
            float _ColorHighPosition;
            float4 _ColorMedium;
            float _ColorMediumPosition;
            float4 _ColorLow;
            float _ColorLowPosition;
            float _ColorOffset;
            float _ColorShift;
            bool _SaturateColor;
            
            float _Radius;
            float _InnerRadius;
            float _Falloff;
            float _EndPosition;
            float _StartFalloff;
            float _StartPosition;
            float _RadialFalloff;
            float _RadialFalloffPosition;
            float _LinearExpansion;
            float _QuadraticExpansion;
            
            float _Noise;
            Texture3D<float4> _NoiseTex;
            SamplerState sampler_NoiseTex;
            float3 _Velocity;
            float3 _NoiseTexTilling;
            float4 _ShapeNoiseWeights;
            
            int _Resolution;
            float _ResolutionMultiplier;
            int _MinimumResolution;
            int _StepCount;
            float _DensityMultiplier;
            float _DensityLowerThreshold;
            float _DensityUpperThreshold;
            float _DensityLowerClip;
            float _DensityUpperClip;
            float _ExpansionDensityInvMultiplier;
            
            sampler2D _CameraDepthTexture;
            float _TimeOffset;
            bool _CustomZTest;

             //to Object Rotate to World (orw)
            fixed3 orw(fixed3 oPos, int w){
                return mul(rotation,fixed4(oPos,w)).xyz;
                }

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
            
            float remap(float In, float2 InMinMax, float2 OutMinMax)
            {
                return OutMinMax.x + (In - InMinMax.x) * (OutMinMax.y - OutMinMax.x) / (InMinMax.y - InMinMax.x);
            }
            float4 remap(float4 In, float2 InMinMax, float2 OutMinMax)
            {
                return OutMinMax.x + (In - InMinMax.x) * (OutMinMax.y - OutMinMax.x) / (InMinMax.y - InMinMax.x);
            }

            float SampleDensity(float3 position){
                fixed3 objectPos = mul(unity_WorldToObject,position);
                fixed2 objectNormal = normalize(objectPos.xz);
                fixed yPos = (objectPos.y-.5);
                fixed radius = _Radius/2;

                
                //change in position
                fixed3 extraPos = 0;
                extraPos.xz += (yPos) * _LinearExpansion * objectNormal;
                extraPos.xz += (pow(yPos,2)) * _QuadraticExpansion * objectNormal;

                fixed distanceFromRadius = length(extraPos.xz);
                fixed innerRadius = (1-_InnerRadius)/2;
                fixed2 radiusPos = radius * objectNormal;
                fixed2 radiusMaxPos = radiusPos + extraPos;


                fixed3 newPos = (objectPos + extraPos);
                newPos.xz -= radiusPos;

                fixed dot2 = dot(objectNormal, newPos.xz);
                fixed dot3 = dot(objectNormal, lerp(objectNormal, newPos.xz, _InnerRadius));
                
                fixed distanceToRadius = length(newPos.xz);
                fixed distanceToRadiusNormalized = distanceToRadius/ radius;

                //Everything lower than radius
                fixed mask = dot2<0;

                //Everything higher than the Inner Radius
                if(_Hollow)
                mask *= dot3 >= 0;

                //return ((1-(length(newPos.xz)/radius)) > _RadialFalloffPosition) * mask;

                fixed newRim = _RadialFalloffPosition * radius;
                fixed distanceToNewRim = (distanceToRadius * newRim);

                //Distance to the rim

                //return mask;

                //exti earlier to save performance
                if(mask == 0)
                    return 0;
                    
                fixed3 samplePos = objectPos;
                fixed3 tiling = _NoiseTexTilling * scale;
                fixed3 speed = _Velocity/tiling;
                samplePos.y += (_Time.y + _TimeOffset) * speed.y;
                samplePos.xz += (_Time.z + _TimeOffset) * speed.xz;
                float4 noise = lerp(.5,_NoiseTex.SampleLevel(sampler_NoiseTex, (samplePos) * tiling, 0),_Noise);

                //Apply noise to mask
                noise*=mask;


                
                //Get weighted noise
                float4 normalizedShapeWeights = _ShapeNoiseWeights / dot(_ShapeNoiseWeights, 1);
                float noiseFBM = dot(noise, normalizedShapeWeights);

                float density = noiseFBM;
                density = max(density, _DensityLowerClip);
                density = min(density, _DensityUpperClip);
                
                
                float extra = (yPos) * _LinearExpansion;
                extra += (pow(yPos,2)) * _QuadraticExpansion;

                float distanceToRadius2 = length((objectPos).xz) - length(radius * objectNormal) * _ExpansionDensityInvMultiplier;

                //Make density higher (or lower) depending on the distance from the radius
                if(distanceToRadius2 > 0)
                {
                    density = density/(1+distanceToRadius2 * 2);
                }
                else{
                    density = pow(density, 1+abs(distanceToRadius2) * 2);
                }
                //if(-extra > 0)
                //    density -= -extra*_ExpansionDensityInvMultiplier;
                //Apply falloffs
                float fadeIn = pow(1-min(max(objectPos.y+.5-(1-_StartPosition), 0),1), _StartFalloff);
                float fadeOut = pow(min(max(objectPos.y+.5+(1-_EndPosition), 0),1), _Falloff);
                float fadeRadial = pow(min((distanceToRadius - distanceToNewRim)/max(0.001,(radius-newRim)), 1), _RadialFalloff);

                density = lerp(0, density, fadeIn * fadeOut * fadeRadial);

                if(density < _DensityLowerThreshold)
                    density = min(0, density * (1/density));

                if(density > _DensityUpperThreshold)
                    density = min(0, density * pow(density,2));

                //Apply Color's alpha
                //density *= lerp(_ColorA.a, _ColorB.a, density);
                density *= _DensityMultiplier;

                return density;
            }

            float3 ToObjectPos(float3 WorldPos){
                return mul(unity_WorldToObject, WorldPos);
                }

            fragOutput frag(v2f i) : SV_Target {
                fragOutput o;
                o.depth = 0;

                if(_Opacity == 0)
                    discard;

                //return Linear01Depth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i.screenPos.xy/i.screenPos.w));
                float3 rayPos = _WorldSpaceCameraPos - position;
                float viewLength = length(i.viewVector);
                float3 rayDir = normalize(i.worldPos - rayPos - position
                    );

                float dstToBox = 0;
                float dstToBoxFar = 0;
                if(!cube(orw(rayPos, 0), orw(rayDir,0), dstToBox, dstToBoxFar))
                    return o;

                dstToBox = max(0, dstToBox);

                float dstInsideBox = dstToBoxFar - dstToBox;
                dstInsideBox = max(0, dstInsideBox);

                // point of intersection with the cloud container
                float3 entryPoint = rayPos + position + rayDir * dstToBox;
                float3 exitPoint = rayPos +position + rayDir * dstInsideBox;

                float dstTravelled = 0;
                float dstLimit = dstInsideBox;
                int stepCount = (1+_Resolution)*32;
                stepCount *= _ResolutionMultiplier;

                stepCount = max(_MinimumResolution, stepCount);
                float stepSize = dstInsideBox/(stepCount); //Create multiplier for step count to allow for modder customization
                int failSafeCount = stepCount;

                float density = 0;
                float4 entryClipPos = UnityWorldToClipPos(float4(entryPoint, 0));
                float4 exitClipPos = UnityWorldToClipPos(float4(exitPoint, 0));

                float depth = 1;
                bool hasDepth = false;

                const int DEPTH_PROBE_RESOLUTION = 64;
                float depthValue[DEPTH_PROBE_RESOLUTION];

                for(int i = 1; i <= DEPTH_PROBE_RESOLUTION; i++){
                    
                    float4 clipPos = lerp(entryClipPos, exitClipPos, (i-1)/DEPTH_PROBE_RESOLUTION);
                    float4 screenPos = ComputeScreenPos(clipPos);
                    float2 uv = screenPos.xy/screenPos.w;
                    float depthSolid = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv));
                    depthValue[i-1] = depthSolid;
                }

                while(dstTravelled < dstLimit){
                    failSafeCount -= 1;
                    if(failSafeCount < 0)
                        break;
                    
                    float3 currentPos = entryPoint + rayDir * dstTravelled;
                    dstTravelled += stepSize;

                    float4 clipCurPos = UnityWorldToClipPos(float4(currentPos, 1));
                    float depthCurPos = LinearEyeDepth(clipCurPos.z/clipCurPos.w);
                    float depthSolid = depthValue[(dstTravelled/dstLimit) * DEPTH_PROBE_RESOLUTION];

                    if(depthCurPos > depthSolid && _CustomZTest)
                        continue;
                    density += SampleDensity(currentPos - position)* (stepSize / (length(scale)/27));
                    }

                fixed4 col = density;
                if(density < _ColorLowPosition){
                    col *= _ColorLow;
                    }
                else if(density < _ColorMediumPosition){
                    col *= lerp(_ColorLow, _ColorMedium, pow((density - _ColorLowPosition)/(_ColorMediumPosition - _ColorLowPosition), _ColorOffset));
                    }
                else if(density < _ColorHighPosition){
                    col *= lerp(_ColorMedium, _ColorHigh, pow((density - _ColorMediumPosition)/(_ColorHighPosition-_ColorMediumPosition), _ColorOffset));
                    }
                else{
                    col *= _ColorHigh;
                    }

                col *= _Brightness;

                col.a *= _Opacity;
                o.color = col;
                o.depth = 1;

                return o;
            }
            ENDCG
        }
    }
}
