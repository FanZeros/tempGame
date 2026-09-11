vec2 vTexCoord : TEXCOORD0 = vec2(0.0, 0.0);
hvec2 vScreenPos : TEXCOORD1 = hvec2_init(0.0, 0.0);
hvec4 vWorldPos : TEXCOORD2 = hvec4_init(0.0, 0.0, 0.0, 0.0);
hvec4 vDepthVec : TEXCOORD3 = hvec4_init(0.0, 0.0, 0.0, 0.0);
hvec2 vVignette : TEXCOORD4 = hvec2_init(0.0, 0.0);

hvec4 a_position  : POSITION;
hvec2 a_texcoord1 : TEXCOORD1;
hvec4 i_data0 : TEXCOORD3;
