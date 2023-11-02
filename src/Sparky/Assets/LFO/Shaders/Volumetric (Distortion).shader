Shader "LFO/Volumetric (Distortion)"
{
    Properties
    {
        [Header(General)]
        _Opacity ("Opacity", Range(0,1)) = 1
        _Brightness ("Brightness", Range(0, 5)) = 1

        [Space(20)]
        [Header(Color)]
        [HDR] _ColorHigh ("High", Color) = (1,1,1,1)
        _ColorHighPosition ("Position", Range(0.001,1)) = 1
        [HDR] _ColorMedium ("Medium", Color) = (1,0,0,1)
        _ColorMediumPosition ("Position", Range(0.001,0.999)) = .5
        [HDR] _ColorLow ("Low", Color) = (1,0,0,1)
        _ColorLowPosition ("Position", Range(0,0.998)) = 0
        _ColorOffset ("Falloff", Range(0, 2)) = 1
        //[Toggle] _SaturateColor ("Saturate color?", int) = 1

        [Space(20)]
        [Header(Shape)]
        _Radius ("Radius", Range(0.001,2)) = .5
        [Toggle(USE_HOLLOW)] _Hollow ("Is Hollow?", int) = 0
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
        _YAnchorOffset ("Anchor", Range (-1,1)) = 0

        [Space(20)]
        [Header(Noise)]
        _Noise ("Contrast", Range(0,2)) = 1
        _NoiseFresnel ("Noise Fresnel", Range(0,2)) = 1
        _NoiseScale ("Noise Scale", Range(0.001,5)) = 1
        [NoScaleOffset] _NoiseTex ("Noise", 3D) = "grey" {}
        _NoiseTexTilling ("Tilling", Vector) = (1,1,1,0)
        _Velocity ("Speed", Vector) = (0,1,0,0)
        _ShapeNoiseWeights ("RGBA Weights", Vector) = (1,1,1,1)

        [Space(20)]
        [Header(Volumetric Settings)]
        [Enum(Resolution)] _Resolution ("Resolution", float) = 2
        [PowerSlide(3)] _ResolutionMultiplier ("Resolution Multiplier", Range(0.01, 10)) = 1
        [IntRange] _MinimumResolution ("Minimum Resolution", Range(0, 512)) = 8
        _DensityLowerThreshold ("Lower threshold", Range(0,0.999)) = 0
        _DensityUpperThreshold ("Upper threshold", Range(0.001,1)) = 1
        _DensityLowerClip ("Lower Clip", Range(0,0.999)) = 0
        _DensityUpperClip ("Upper Clip", Range(0.001,1)) = 1
        _DensityMultiplier ("Density multiplier", float) = 1
        _ExpansionDensityInvMultiplier ("Inverse Expansion multiplier", Range(-2, 2)) = 1
        [Toggle(ABSOLUTE)] _Absolute ("Allow overlap?", int) = 1
        [Toggle(CUSTOM_ZTEST)] _CustomZTest ("Use custom ZTest?", int) = 1
        [Space()]
        [Header(Optimizations)]
        [Toggle(USE_LOG)] _UseLog ("Use LogBisect (instead of Bisect)?", int) = 0
        [Toggle(USE_BOUNDS)] _UseBounds ("Use bounds?", int) = 1
    }
    SubShader
    {
        Tags {"Queue"="Transparent" "RenderType"="Transparent"}
        Blend SrcAlpha One
        ZWrite On
        ZTest Always
        Cull Front

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 5.0

		    #pragma shader_feature ABSOLUTE
            #pragma shader_feature USE_LOG
            #pragma shader_feature USE_BOUNDS
            #pragma shader_feature CUSTOM_ZTEST
            #pragma shader_feature USE_HOLLOW

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
            bool _SaturateColor;
            
            float _Radius;
            float _BottomRadius;
            float _TopRadius;
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
            float _NoiseFresnel;
            float _NoiseScale;
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
            float _YAnchorOffset;
            
            sampler2D _CameraDepthTexture;
            float _TimeOffset;

             //to Object Rotate to World (orw)
            fixed3 orw(fixed3 oPos, int w){
                return mul(rotation,fixed4(oPos,w)).xyz;
                }

            #define PRECISION .0000005
            #define BASE_STRIDE .1
            #define FAR_STRIDE .3
            #define MIN_STEP .1
            #define FAR 1000
            #define ITR 100
            //#define USE_LOG false // log doesn't seem to work for some reason with this... The problem might be on abs(d) - [log(abs(d)+logvl)]
            #define EPSILON 0.00001
            #define INFINITY 1000000
            const float logvl = 1+MIN_STEP;

            //func Plume(y) = Radius + (y * LINEAR) + (y*y * QUADRATIC)
            float Plume(in float y){
                y -= scale.y;
                return _Radius + (y*-(_LinearExpansion)) + (pow(y,2)*-(_QuadraticExpansion/50));
            }

        #ifdef USE_BOUNDS
            float2 minmax;
        #endif

            //returns signed distance between current position and the function's root at said position
            float map(in float3 p)
            {
                float3 op = mul(unity_WorldToObject, p);
                float radius = Plume(p.y + (scale.y * _YAnchorOffset));
                #ifdef ABSOLUTE
                    radius = abs(radius);
                #endif
                float2 xz = normalize(p.xz) * radius;

                float3 PlumePosition = float3(xz.x, p.y, xz.y);
                float sgn = 1;
                float d = 0;

                if(p.y > (scale.y) || p.y < -(scale.y)){
                    sgn = 1;
                    d = length(PlumePosition - p) * sgn;
                }
                else{
                #ifndef USE_HOLLOW
                    sgn = (length(p.xz) < radius)? -1 : 1;
                #else
                    sgn = (length(p.xz) < radius && length(p.xz) > lerp(0, radius, _InnerRadius))? -1 : 1;
                #endif
                    d = length(PlumePosition - p) * sgn;
                }

                return d;
            }

            float bisect(in float3 ro, in float3 rd, in float near, in float far)
            {
                float mid = 0;
                float sgn = sign(map(rd*near+ro));
                for (int i = 0; i < 6; i++)
                { 
                    mid = (near + far)*.5;
                    float d = map(rd*mid+ro);
                    if (abs(d) < PRECISION)break;

                    if(d*sgn < 0)far = mid; else near = mid;
                }
                return (near+far) * .5;
            }

            float intersect(in float3 ro, in float3 rd)
            {
                //OPTIMIZE: Start t on the plume's bounding box
                float t = 0;
                const int itr = ITR;
                float d = map(rd*t+ro);
                bool sgn = (d > 0.0) ? true : false;
                float oldt = t;
                bool doBisect = false;
    
                for (int i=0;i<=itr;i++)
                {
                    if (abs(d) < PRECISION || t > FAR) //if distance to root is lower tha PRECISION or bigger than FAR
                        break; //We found the root or there's not root
                    else if (i == itr) //if its the last iteration
                        t = 100000; //set as furthest point
        
                    //if outside of bounds, continue
                    float3 curPos = rd*t+ro;
                    if(curPos.y > scale.y/2 || curPos.y < -scale.y/2)
                        continue;
            
                    //if we crossed but didn't detect, use bisection method
                    if ((d > 0.0) != sgn)
                    {
                        doBisect= true;
                        break;
                    }
        
                    oldt = t;

                #if 1
                    if (d > 1)
                        t += d*FAR_STRIDE;
                    else 
                        t += log(abs(d)+logvl)*BASE_STRIDE;
                #else
                    t += log(abs(d)+logvl)*BASE_STRIDE;
                #endif

                    if((rd * t+ro).y > .0 || (rd * t+ro).y < -scale.y)
                        continue;
                
                 d = map(rd*t+ro);
                }
    
                if (doBisect)t = bisect(ro,rd,oldt,t);
                return t;
            }

            bool LogBisect(in float3 rayOrigin,in float3 rayDirection, out float2 near, out float2 far){

                #ifdef USE_BOUNDS
                float t = minmax.x;
                float maxDist = minmax.y;
                #else
                float t = 0;
                float maxDist = FAR;
                #endif

                float oldt = t;
                float3 rayPos = rayDirection*t+rayOrigin;
                float d = map(rayPos);
                bool sgn = d > 0;
                bool oldsgn = sgn;

                float halfScale = scale/2;
                int itr = ITR;
                bool found = false;

                int intersectionCount = 0;
                if(!sgn)//is inside the shape
                {
                    near.x = t;
                    intersectionCount +=1;
                }

                for (int i=0;i<=itr;i++)
                {
                    rayPos = rayDirection*t+rayOrigin;
                    d = map(rayPos);
                    sgn = d > 0;
                    bool crossed = sgn != oldsgn;

                    if(t > maxDist){
                        break;
                    }
                    else if(i == itr){
                        t = FAR;
                    }

                    float edgeT= crossed * bisect(rayOrigin,rayDirection,oldt,t) + (1-crossed)*t;
                    if(abs(d) < PRECISION || crossed){
                        if(intersectionCount == 0){
                            near.x = edgeT;
                        }
                        else if(intersectionCount == 1){
                            far.x = edgeT;
                        }
                        else if(intersectionCount == 2){
                            near.y = edgeT;
                        }
                        else if(intersectionCount == 3){
                            far.y = edgeT;
                            break;
                        }
                        intersectionCount += 1;
                        found = true;
                    }

                oldsgn = sgn;
                oldt = t;

                #ifdef USE_LOG
                if (d > 1)t += d*FAR_STRIDE;
                else t += log(abs(d)+logvl)*BASE_STRIDE;
                #else
                #ifdef USE_BOUNDS
                t += (minmax.y - minmax.x)/ITR;
                #else
                t += BASE_STRIDE;
                #endif
                #endif
                }

                return found;
            }

            float SampleDensity(float3 position){
                //return .1;
                fixed3 objectPos = mul(unity_WorldToObject,position);
                fixed2 objectNormal = normalize(objectPos.xz);
                fixed yPos = (objectPos.y-.5);
                fixed radius = _Radius/2;
                
                fixed3 samplePos = objectPos;
                fixed3 tiling = _NoiseTexTilling * scale;
                fixed3 speed = _Velocity/tiling;
                samplePos += (_Time.y + _TimeOffset) * speed;
                float4 noise = lerp(.5,_NoiseTex.SampleLevel(sampler_NoiseTex, (samplePos) * tiling* _NoiseScale, 0),_Noise);
                float4 normalizedShapeWeights = _ShapeNoiseWeights / dot(_ShapeNoiseWeights, 1);
                float noiseFBM = (dot(noise, normalizedShapeWeights));

                float density = clamp(noiseFBM, _DensityLowerClip, _DensityUpperClip);

                
                float fadeIn = pow(1-clamp(objectPos.y+.5-(1-_StartPosition), 0,1), _StartFalloff);
                float fadeOut = pow(clamp(objectPos.y+.5+(1-_EndPosition), 0,1), _Falloff);
                float distanceFrom0 = length(position.xz);
                float radialFalloffPos = lerp(0, _Radius, _RadialFalloffPosition);
                float distanceFromR = _Radius - distanceFrom0;
                distanceFromR = 1+max(0, distanceFromR);
                float fadeRadial = pow(1/distanceFromR, _RadialFalloff);

                float fade = fadeIn * fadeOut * fadeRadial;

                float fadedDensity = lerp(density, .5, fade);

                density *= fade;
                density *= pow(fadedDensity, mad(noiseFBM, .5, 1-fadedDensity)*_NoiseFresnel) * fadedDensity;
                
                if(density < _DensityLowerThreshold)
                    density = min(0, density * (1/density));

                if(density > _DensityUpperThreshold)
                    density = min(0, density * pow(density,2));

                density *= _DensityMultiplier;
                return density;
            }

            float3 ToObjectPos(float3 WorldPos){
                return mul(unity_WorldToObject, WorldPos);
                }
        #ifdef USE_BOUNDS
            bool cylinder(float3 org, float3 dir, out float near, out float far)
            {
            	// quadratic x^2 + y^2 = 0.5^2 => (org.x + t*dir.x)^2 + (org.y + t*dir.y)^2 = 0.5
            	float a = dot(dir.xz, dir.xz);
            	float b = dot(org.xz, dir.xz);
            	float c = dot(org.xz, org.xz) - length(scale.xz*2);

            	float delta = b * b - a * c;
            	if( delta < 0.0 )
            		return false;

            	// 2 roots
            	float deltasqrt = sqrt(delta);
            	float arcp = 1.0 / a;
            	near = (-b - deltasqrt) * arcp;
            	far = (-b + deltasqrt) * arcp;

            	// order roots
            	float temp = min(far, near);
            	far = max(far, near);
            	near = temp;

            	float znear = org.y + near * dir.y;
            	float zfar = org.y + far * dir.y;

            	// top, bottom
            	float2 zcap = float2(scale.y +.1, -(scale.y + .1));
            	float2 cap = (zcap - org.y) / dir.y;

            	if ( znear < zcap.y )
            		near = cap.y;
            	else if ( znear > zcap.x )
            		near = cap.x;

            	if ( zfar < zcap.y )
            		far = cap.y;
            	else if ( zfar > zcap.x )
            		far = cap.x;

            	return far > 0.0 && far > near;
            }
        #endif
            fragOutput frag(v2f i) : SV_Target {
                if(_Opacity == 0)
                    discard;

                fragOutput o;
                o.depth = 1;
                o.color = 0;
                float3 rayPos = _WorldSpaceCameraPos - position;
                float viewLength = length(i.viewVector);
                float3 rayDir = normalize(i.worldPos - rayPos - position);
                #ifdef USE_BOUNDS
                minmax = 0;
                cylinder(orw(rayPos, 0), orw(rayDir,0),minmax.x, minmax.y);
                minmax += float2(-5, 5);
                minmax = max(0, minmax);
                #endif
                float2 dstToBox = 0;
                float2 dstToBoxFar = 0;
                //if(!LogBisect(orw(rayPos, 0), orw(rayDir,0), dstToBox, dstToBoxFar))
                //    return o;
                

                if(!LogBisect(orw(rayPos, 0), orw(rayDir,0), dstToBox, dstToBoxFar)){
                    return o;
                }

                dstToBox = max(0, dstToBox);

                float2 dstInsideBox = dstToBoxFar - dstToBox;
                dstInsideBox = max(0, dstInsideBox);

                // point of intersection with the cloud container
                float3 entryPoint = rayPos + position + rayDir * dstToBox.x;
                float3 exitPoint = rayPos +position + rayDir * dstInsideBox.x;

                float dstTravelled = 0;
                float dstLimit = dstInsideBox.x;
                int stepCount = (1+_Resolution)*32;
                stepCount *= _ResolutionMultiplier;

                stepCount = max(_MinimumResolution, stepCount);
                float stepSize = dstInsideBox.x/(stepCount); //Create multiplier for step count to allow for modder customization
                int failSafeCount = stepCount;

                float density = 0;
                float4 entryClipPos = UnityWorldToClipPos(float4(entryPoint, 1));
                float4 exitClipPos = UnityWorldToClipPos(float4(exitPoint, 1));
                float lastDepth;

                const int DEPTH_PROBE_RESOLUTION = 8;
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

                #ifdef CUSTOM_ZTEST
                    float4 clipCurPos = UnityWorldToClipPos(float4(currentPos, 1));
                    float depthCurPos = LinearEyeDepth(clipCurPos.z/clipCurPos.w);
                    float depthSolid = depthValue[(dstTravelled/dstLimit) * DEPTH_PROBE_RESOLUTION];

                    if(depthCurPos >= depthSolid)
                        continue;
                #endif      

                    float3 normalizedSize = scale / dot(scale, 1);
                    float sizeFBM = dot(rayDir, normalizedSize);
                    density += SampleDensity(currentPos - position)* (stepSize);
                }

                if(dstInsideBox.y > EPSILON){
                dstTravelled = 0;
                dstLimit = dstInsideBox.y;
                failSafeCount = stepCount;
                stepSize = dstInsideBox.y/stepCount;
                float3 entryPoint2 = rayPos + position + rayDir * dstToBox.y;

                while(dstTravelled < dstLimit){
                    failSafeCount -= 1;
                    if(failSafeCount < 0)
                        break;
                    
                    float3 currentPos = entryPoint2 + rayDir * dstTravelled;
                    dstTravelled += stepSize;
                    
                #ifdef CUSTOM_ZTEST
                    float4 clipCurPos = UnityWorldToClipPos(float4(currentPos, 1));
                    float depthCurPos = LinearEyeDepth(clipCurPos.z/clipCurPos.w);
                    float depthSolid = depthValue[(dstTravelled/dstLimit) * DEPTH_PROBE_RESOLUTION];

                    if(depthCurPos >= depthSolid)
                        continue;
                #endif

                    float3 normalizedSize = scale / dot(scale, 1);
                    float sizeFBM = dot(rayDir, normalizedSize);
                    density += SampleDensity(currentPos - position)* (stepSize);
                }
                }

                fixed4 col = density;
                if(density < _ColorLowPosition){
                    col *= _ColorLow;
                    //col *= lerp(0, _ColorLow, pow(density/_ColorLowPosition, _ColorOffset));
                    }
                else if(density < _ColorMediumPosition){
                    col *= lerp(_ColorLow, _ColorMedium, pow((density - _ColorLowPosition)/(_ColorMediumPosition - _ColorLowPosition), _ColorOffset));
                    }
                else if(density < _ColorHighPosition){
                    col *= lerp(_ColorMedium, _ColorHigh, pow((density - _ColorMediumPosition)/(_ColorHighPosition-_ColorMediumPosition), _ColorOffset));
                    }
                else{
                    col *= _ColorHigh;
                    //col *= saturate(lerp(_ColorHigh, saturate(pow(_ColorHigh,2)), density-_ColorHighPosition));
                    }

                col = saturate(col);

                col *= _Brightness;

                col.a *= _Opacity;

                o.color = col;

                return o;
            }
            ENDCG
        }
    }
}
