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
        _ColorHighPosition ("Position", Range(0.001,10)) = 3
        [HDR] _ColorMedium ("Medium", Color) = (1,0,0,1)
        _ColorMediumPosition ("Position", Range(0.001,9.999)) = .5
        [HDR] _ColorLow ("Low", Color) = (1,0,0,1)
        _ColorLowPosition ("Position", Range(0,9.998)) = 0
        _ColorOffset ("Falloff", Range(0, 2)) = 1
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
        [NoScaleOffset]_NoiseTex ("Noise", 3D) = "white" {}
        _NoiseTexTilling ("Tilling", Vector) = (1,1,1,0)
        _Velocity ("Speed", Vector) = (0,1,0,0)
        _ShapeNoiseWeights ("RGBA Weights", Vector) = (1,1,1,1)

        [Space(20)]
        [Header(Volumetric Settings)]
        [Enum(Resolution)] _Resolution ("Resolution", float) = 2
        [PowerSlide(3)] _ResolutionMultiplier ("Resolution Multiplier", Range(0.01, 10)) = 1
        _MinimumResolution ("Minimum Resolution", Range(0, 512)) = 8
        _DensityLowerThreshold ("Lower threshold", Range(0,9.999)) = 0
        _DensityUpperThreshold ("Upper threshold", Range(0.001,10)) = 5
        _DensityLowerClip ("Lower Clip", Range(0,9.999)) = 0
        _DensityUpperClip ("Upper Clip", Range(0.001,10)) = 5
        _DensityMultiplier ("Density multiplier", float) = 1
    }
    SubShader
    {
        Tags {
            "RenderType"="Transparent"
            "Queue"="Transparent"
            "IgnoreProjector" = "True"
        }
        
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
            
            sampler2D _CameraDepthTexture;
            float3 boundsMin;
            float3 boundsMax;
            float3 scale;
            float3 rotation;
            float _TimeOffset;
 
            // Returns (dstToBox, dstInsideBox). If ray misses box, dstInsideBox will be zero
            float2 rayBoxDst(float3 boundsMin, float3 boundsMax, float3 rayOrigin, float3 invRaydir) {
                // Adapted from: http://jcgt.org/published/0007/03/04/
                // From Sebastian Lague's Clouds

                float3 t0 = (boundsMin - rayOrigin) * invRaydir;
                float3 t1 = (boundsMax - rayOrigin) * invRaydir;
                float3 tmin = min(t0, t1);
                float3 tmax = max(t0, t1);
                
                float dstA = max(max(tmin.x, tmin.y), tmin.z);
                float dstB = min(tmax.x, min(tmax.y, tmax.z));

                // CASE 1: ray intersects box from outside (0 <= dstA <= dstB)
                // dstA is dst to nearest intersection, dstB dst to far intersection

                // CASE 2: ray intersects box from inside (dstA < 0 < dstB)
                // dstA is the dst to intersection behind the ray, dstB is dst to forward intersection

                // CASE 3: ray misses box (dstA > dstB)

                float dstToBox = max(0, dstA);
                float dstInsideBox = max(0, dstB - dstToBox);
                return float2(dstToBox, dstInsideBox);
            }

            float SampleDensity(float3 position){
                fixed3 size = boundsMax - boundsMin;
                fixed3 boundsCentre = (boundsMin+boundsMax) * .5;
                fixed3 objectPos = mul(unity_WorldToObject,position);
                fixed2 objectNormal = normalize(objectPos.xz);
                fixed yPos = (objectPos.y-.5);
                fixed radius = _Radius/2;

                fixed3 samplePos = objectPos;
                fixed3 tiling = _NoiseTexTilling * scale;
                fixed3 speed = _Velocity/tiling;
                samplePos.y += (_Time.y + _TimeOffset) * speed.y;
                samplePos.xz += (_Time.y + _TimeOffset) * speed.xz;
                
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

                //Get all 4 channels of the texture
                float4 noise = lerp(.5,_NoiseTex.SampleLevel(sampler_NoiseTex, (samplePos) * tiling, 0),_Noise);

                //Apply noise to mask
                noise*=mask;

                
                //Get weighted noise
                float4 normalizedShapeWeights = _ShapeNoiseWeights / dot(_ShapeNoiseWeights, 1);
                float noiseFBM = dot(noise, normalizedShapeWeights);

                float density = noiseFBM;
                density = max(density, max(_DensityLowerClip, _DensityLowerThreshold));
                density = min(density, _DensityUpperClip);
                //density = min(density, min(_DensityUpperClip, _DensityUpperThreshold));
                density *= pow((distanceToRadius - distanceToNewRim)/max(0.001,(radius-newRim)), _RadialFalloff);


                if(density < _DensityLowerThreshold)
                    density = min(0, density * (1/density));

                if(density > _DensityUpperThreshold)
                    density = min(0, density * pow(density,2));
                    

                //Apply falloffs
                density *= pow(1-min(max(objectPos.y+.5-(1-_StartPosition), 0),1), _StartFalloff);
                density *= pow(min(max(objectPos.y+.5+(1-_EndPosition), 0),1), _Falloff);


                //Make density higher (or lower) depending on the distance from the radius
                if(length(newPos.xz) > radius)
                    density += density * -pow(distanceFromRadius,2);
                else
                    density += density * pow(distanceFromRadius,2);
                    
                //Apply Color's alpha
                //density *= lerp(_ColorA.a, _ColorB.a, density);
                density *= _DensityMultiplier;

                return density;
            }

            float3 ToObjectPos(float3 WorldPos){
                return mul(unity_WorldToObject, WorldPos);
                }

            fixed4 frag(v2f i) : SV_Target {
                if(_Opacity == 0)
                    return 0;

                float3 size = boundsMax - boundsMin;
                float3 boundsCentre = (boundsMin+boundsMax) * .5;
                float3 rayPos = _WorldSpaceCameraPos;
                float viewLength = length(i.viewVector);
                float3 rayDir = normalize(i.worldPos - rayPos);

                float2 rayToContainerInfo = rayBoxDst(boundsMin, boundsMax, rayPos, 1/(rayDir));
                float dstToBox = rayToContainerInfo.x;
                float dstInsideBox = rayToContainerInfo.y;

                // point of intersection with the cloud container
                float3 entryPoint = rayPos + rayDir * dstToBox;
                float3 exitPoint = rayPos + rayDir * dstInsideBox;

                float dstTravelled = 0;
                float dstLimit = dstInsideBox;

                int stepCount = (1+_Resolution)*32;
                stepCount *= _ResolutionMultiplier;

                stepCount = max(_MinimumResolution, stepCount);
                float stepSize = dstInsideBox/stepCount;

                float density = 0;
                float2 screeSpaceUV = i.screenPos.xy / i.screenPos.w;
                float opaqueDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, screeSpaceUV);
                float depthSolid = LinearEyeDepth(opaqueDepth) * viewLength;

                while(dstTravelled < dstLimit){
                    //Current position of the ray (given distance travelled)
                    float3 currentPos = entryPoint + rayDir * dstTravelled;

                    fixed3 oPos = mul(unity_WorldToObject, currentPos);
                    fixed4 clipCurPos = UnityWorldToClipPos(float4(currentPos, 1));
                    fixed depthCurPos = LinearEyeDepth(clipCurPos.z/clipCurPos.w) * viewLength;

                    dstTravelled += stepSize;

                    //Custom ZTest to occlude hidden positions
                    if(depthCurPos >= depthSolid)
                        continue;
                       
                    density += SampleDensity((currentPos - boundsCentre)) * (stepSize / (length(size)/27));
                }

                fixed4 col = density;
                if(density < _ColorLowPosition && !_SaturateColor){
                    col *= lerp(0, _ColorLow, pow(density/_ColorLowPosition, _ColorOffset));
                    }
                else if(density < _ColorMediumPosition){
                    col *= lerp(_ColorLow, _ColorMedium, pow((density - _ColorLowPosition)/(_ColorMediumPosition - _ColorLowPosition), _ColorOffset));
                    }
                else if(density < _ColorHighPosition){
                    col *= lerp(_ColorMedium, _ColorHigh, pow((density - _ColorMediumPosition)/(_ColorHighPosition-_ColorMediumPosition), _ColorOffset));
                    }
                else if(!_SaturateColor){
                    col *= lerp(_ColorHigh, pow(fixed4(_ColorHigh),2), pow(density/_ColorHighPosition, _ColorOffset));
                    col.a = max(1, col.a);
                    }

                col.a = saturate(col.a);
                //col *= lerp(_ColorB, _ColorA, saturate(pow(density, _ColorOffset)));

                col *= _Brightness;

                col.a *= _Opacity;

                return col;
            }
            ENDCG
        }
    }
}
