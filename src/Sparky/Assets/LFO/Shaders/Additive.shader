Shader "LFO/Additive"
{
    Properties
    {
        [Header(General)]
        _Opacity("Opacity", Range(0, 1)) = 1
        _Brightness("Brightness", Range(0, 10)) = 1
        _LenghtwiseBrightness("LenghtwiseBrightness", Float) = 1
        [Space()]

        [Header(Color)]
        [HDR] _StartTint("Start", Color) = (1, 1, 1, 1)
        [HDR] _EndTint("End", Color) = (1, 0, 0, 1)
        _TintFalloff("Falloff", Range(0, 2)) = 2
        [Space()]

        [Header(Noise)]
        _Noise("Noise", Range(0, 1)) = 1
        [NoScaleOffset] _NoiseTex("Texture", 2D) = "white" {}
        _NoiseContrast("Contrast", Range(1, 5)) = 1
        _NoiseFresnel("NoiseFresnel", Range(0, 1)) = 0
        _Tilling("Tilling", Vector) = (1, 1, 0, 0)
        _Speed("Speed", Vector) = (.5, 1, 0, 0)
        [Space()]

        [Header(Mask)]
        _Fresnel("Fresnel", Range(0, 10)) = 2
        _FresnelInverted("FresnelInverted", Range(0, 10)) = 0
        [Space()]
        _Falloff("Falloff", Range(0.5, 5)) = 1
        [Space()]
        _FalloffStart("FalloffStart", Range(0, 10)) = 0
        _StartFadeIn("StartFadeIn", Range(0, 10)) = 1
        _FalloffStartPosition("FalloffStartPosition", Range(-1, 1)) = 0
        [Space()]

        _LenghtwisePosition("LenghtwisePosition", Range(-1, 5)) = 0
        //_SpeedRandomMultiplier("SpeedRandomMultiplier", Float) = 0.1
        //_ScaleRandomizer("ScaleRandomizer", Range(0, 0.5)) = 0.05

        [Header(Shape)]
        _LinearExpansion("LinearExpansion", Range(-1, 1)) = 0
        _QuadraticExpansion("QuadraticExpansion", Range(-1, 1)) = 0

        [Header(Others)]
        _Seed("Seed", Range(-10, 10)) = 0
    }
    SubShader
    {
		Tags{ "Queue" = "Transparent" "RenderType" = "Transparent" "IgnoreProjector" = "True" }
		//LOD 100

		ZWrite Off
		ZTest LEqual
		Blend SrcAlpha One, One One
		Cull OFF

        CGPROGRAM		
        #include "UnityCG.cginc"
        #pragma surface surf Standard noshadow noambient novertexlights nolightmap keepalpha vertex:vert
        #pragma target 3.0

        sampler2D _NoiseTex;
        float4 _Tilling;
        float4 _Speed;
        float _Seed;

        float _NoiseContrast;
        float _Noise;

        float _Falloff;
        float _FalloffStart;
        float _FalloffStartPosition;
        float _StartFadeIn;
        
        float _Fresnel;
        float _FresnelInverted;
        float _NoiseFresnel;

        float _LenghtwiseBrightness;
        float _Brightness;
        float _Opacity;
        
        float4 _StartTint;
        float4 _EndTint;
        float _TintFalloff;

        float _LinearExpansion;
        float _QuadraticExpansion;
        bool _InvertQuadratic;

        float _LenghtwisePosition;

        fixed4 contrast(fixed4 col, float value){
            float midpoint = pow(0.5, 2.2);
            return (col - midpoint) * value + midpoint;
        }

        void vert(inout appdata_full v){
            v.vertex.xy += ((_LinearExpansion*10) * (1-v.texcoord.y)*2) * v.normal;
            v.vertex.xy += (pow(1-v.texcoord.y,2)) *5 * _QuadraticExpansion * 5 * v.normal;
            v.vertex.z += _LenghtwisePosition;
        }

	    struct Input
	    {
	    	float2 uv_NoiseTex;
	    	float3 viewDir;
	    	float4 color : COLOR; 
	    	float3 worldNormal;
	    };

	    void surf(Input IN, inout SurfaceOutputStandard o){
               fixed4 noise = tex2D(_NoiseTex, (IN.uv_NoiseTex * _Tilling.xy) + ((_Speed.xy * _Time.y) + _Seed));
               noise = contrast(noise, _NoiseContrast);
               noise = lerp(.5, noise, _Noise);

               float fadeOut = pow(IN.uv_NoiseTex.y, _Falloff);
               float fadeIn = saturate(pow(pow(mad(1-IN.uv_NoiseTex.y, .25, .75), _FalloffStart), _StartFadeIn));
               float fade = fadeOut * fadeIn;

               float viewDot = dot(IN.viewDir, IN.worldNormal);

               if(viewDot < 0)
                   viewDot *= -1;

               float fresnelOut =saturate(pow(smoothstep(0,1,viewDot), _Fresnel));
               float fresnelIn =  saturate(pow(smoothstep(1,0,viewDot), _FresnelInverted));
               float fresnel = fresnelOut * fresnelIn;
               float fadedNoise = lerp(noise, .5, fade);

               float4 col = fresnel;
               col *= fade;

               col *= pow(fadedNoise, mad(_Noise, .5, 1-fadedNoise)*_NoiseFresnel) * fadedNoise;
               col *= _LenghtwiseBrightness * IN.uv_NoiseTex.y;
               col *= _Brightness;

               float4 tint = lerp(_EndTint,_StartTint, pow(mad(fresnelOut,.5,.5) * fade, _TintFalloff));
               
               col *= tint;

               col *= _Opacity;
               col = saturate(col);

               o.Emission = col * IN.color.rgb;
               o.Albedo = 0;
               o.Metallic = 0;
               o.Smoothness = 0;
               o.Alpha = col.a;
           }


        ENDCG
    }
}
