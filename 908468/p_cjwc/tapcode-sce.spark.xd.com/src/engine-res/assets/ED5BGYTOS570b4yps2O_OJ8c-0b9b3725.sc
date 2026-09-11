vec3 vTexCoord      : TEXCOORD0 = vec3(0.0, 0.0, 0.0);
hvec4 vWorldPos      : TEXCOORD2 = hvec4_init(0.0, 0.0, 0.0, 0.0);
vec3 vNormal        : TEXCOORD3 = vec3(0.0, 0.0, 0.0);
vec4 vScreenPos     : TEXCOORD5 = vec4(0.0, 0.0, 0.0, 0.0);
vec4 vColor         : COLOR0    = vec4(1.0, 1.0, 1.0, 1.0);

hvec4 a_position  : POSITION;
hvec3 a_normal    : NORMAL;
hvec2 a_texcoord0 : TEXCOORD0;
hvec4 a_color0    : COLOR0;
hvec2 a_texcoord1 : TEXCOORD1;
hvec4 a_tangent   : TANGENT;
hvec4 a_weight    : BLENDWEIGHT;
hvec4 a_indices  : BLENDINDICES;

hvec4 i_data0     : TEXCOORD3;
hvec4 i_data1     : TEXCOORD4;
hvec4 i_data2     : TEXCOORD5;
hvec4 i_data3     : TEXCOORD6;
hvec4 i_data4     : TEXCOORD7;
hvec4 i_data5     : TEXCOORD8;
hvec4 i_data6     : TEXCOORD1;
hvec4 i_data7     : TEXCOORD2;
