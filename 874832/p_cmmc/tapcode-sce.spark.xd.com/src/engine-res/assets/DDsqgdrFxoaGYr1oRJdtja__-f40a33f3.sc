vec2 vTexCoord : TEXCOORD0 = vec2(0.0, 0.0);
hvec4 vWorldPos : TEXCOORD1 = hvec4_init(0.0, 0.0, 0.0, 0.0);
hvec4 vNodePos  : TEXCOORD11 = hvec4_init(0.0, 0.0, 0.0, 0.0);

hvec4 a_position  : POSITION;
hvec3 a_normal    : NORMAL;
hvec2 a_texcoord0 : TEXCOORD0;
hvec4 a_color0    : COLOR0;
hvec2 a_texcoord1 : TEXCOORD1;
hvec4 a_tangent   : TANGENT;
hvec4 a_weight    : BLENDWEIGHT;
hvec4 a_indices   : BLENDINDICES;

hvec4 i_data0     : TEXCOORD3;
hvec4 i_data1     : TEXCOORD4;
hvec4 i_data2     : TEXCOORD5;
hvec4 i_data3     : TEXCOORD6;
hvec4 i_data4     : TEXCOORD7;
hvec4 i_data5     : TEXCOORD8;
hvec4 i_data6     : TEXCOORD1;
hvec4 i_data7     : TEXCOORD2;
