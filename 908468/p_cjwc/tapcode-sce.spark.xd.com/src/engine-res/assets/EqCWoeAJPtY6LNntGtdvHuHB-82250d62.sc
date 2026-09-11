vec4 vScreenPos     : TEXCOORD0 = vec4(0.0, 0.0, 0.0, 0.0);
hvec2 vReflectUV     : TEXCOORD1 = hvec2_init(0.0, 0.0);
hvec2 vWaterUV       : TEXCOORD2 = hvec2_init(0.0, 0.0);
hvec3 vNormal        : NORMAL    = hvec3_init(0.0, 0.0, 1.0);
hvec4 vEyeVec        : TEXCOORD4 = hvec4_init(0.0, 0.0, 0.0, 0.0);

hvec4 a_position  : POSITION;
hvec3 a_normal    : NORMAL;
hvec2 a_texcoord0 : TEXCOORD0;

hvec4 i_data0     : TEXCOORD3;
hvec4 i_data1     : TEXCOORD4;
hvec4 i_data2     : TEXCOORD5;
hvec4 i_data3     : TEXCOORD6;
hvec4 i_data4     : TEXCOORD7;
hvec4 i_data5     : TEXCOORD8;
hvec4 i_data6     : TEXCOORD1;
hvec4 i_data7     : TEXCOORD2;
