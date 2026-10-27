const vertex = `#version 300 es
void main(){vec2 p=vec2((gl_VertexID<<1)&2,gl_VertexID&2);gl_Position=vec4(p*2.0-1.0,0,1);}`;
const fragment = `#version 300 es
precision highp float;
uniform sampler2D firstVideo,secondVideo,alternateVideo,grading;
uniform vec4 viewport;
uniform int background,rectangleCount;
uniform vec4 bounds[16],blends[16];
out vec4 outputColor;
vec3 cloud(int source,vec2 uv){
 if(source==3||source==5)uv.x=1.0-uv.x;
 if(source==4||source==6)uv.y=1.0-uv.y;
 vec3 rgb=source==0?texture(firstVideo,uv).rgb:(source==1||source==3||source==6)?texture(secondVideo,uv).rgb:texture(alternateVideo,uv).rgb;
 // Browser decoding expands limited-range BT.709 Y to full range. The native
 // NV12 shader expands Y the same way before indexing this 256-entry LUT.
 int gray=int(clamp(round(dot(rgb,vec3(.2126,.7152,.0722))*255.0),0.0,255.0));
 return texelFetch(grading,ivec2(gray,source==0?0:1),0).rgb;
}
void main(){
 vec2 position=vec2(gl_FragCoord.x,viewport.y-gl_FragCoord.y);
 vec4 choice=vec4(float(background),float(background),0,0);
 for(int i=0;i<16;i++){if(i>=rectangleCount)break;vec4 r=bounds[i];if(position.x>=r.x&&position.y>=r.y&&position.x<r.z&&position.y<r.w)choice=blends[i];}
 vec2 uv=(position/viewport.xy-.5)*viewport.zw+.5;
 vec3 color=cloud(int(choice.x),uv);
 if(choice.x!=choice.y&&choice.z>0.0)color=round(mix(color,cloud(int(choice.y),uv),choice.z)*255.0)/255.0;
 outputColor=vec4(color,1);
}`;
const roundEven = value => {const n=Math.floor(value),fraction=value-n;return fraction===.5?(n%2===0?n:n+1):Math.round(value);};
export function createCloudRenderer(canvas) {
  const gl=canvas.getContext('webgl2',{alpha:false,antialias:false,depth:false,stencil:false,preserveDrawingBuffer:false,powerPreference:'low-power'});
  if(!gl) throw new Error('Для облаков требуется WebGL 2.');
  function compile(type,source){const s=gl.createShader(type);gl.shaderSource(s,source);gl.compileShader(s);if(!gl.getShaderParameter(s,gl.COMPILE_STATUS))throw new Error(gl.getShaderInfoLog(s));return s;}
  const program=gl.createProgram();
  gl.attachShader(program,compile(gl.VERTEX_SHADER,vertex));gl.attachShader(program,compile(gl.FRAGMENT_SHADER,fragment));gl.linkProgram(program);
  if(!gl.getProgramParameter(program,gl.LINK_STATUS))throw new Error(gl.getProgramInfoLog(program));
  gl.useProgram(program);
  const uniforms=Object.fromEntries(['viewport','background','rectangleCount','bounds','blends'].map(name=>[name,gl.getUniformLocation(program,name)]));
  const textures=Array.from({length:4},(_,index)=>{
    const texture=gl.createTexture();gl.activeTexture(gl.TEXTURE0+index);gl.bindTexture(gl.TEXTURE_2D,texture);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,index===3?gl.NEAREST:gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,index===3?gl.NEAREST:gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
    gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,1,1,0,gl.RGBA,gl.UNSIGNED_BYTE,new Uint8Array([0,0,0,255]));
    gl.uniform1i(gl.getUniformLocation(program,['firstVideo','secondVideo','alternateVideo','grading'][index]),index);return texture;
  });
  const bounds=new Float32Array(64),blends=new Float32Array(64),luts=new Uint8Array(256*2*4);
  return {
    upload(index,video){gl.activeTexture(gl.TEXTURE0+index);gl.bindTexture(gl.TEXTURE_2D,textures[index]);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,video);},
    draw(frame){
      const width=canvas.width,height=canvas.height,aspect=width/height,sourceAspect=1968/1436;
      gl.viewport(0,0,width,height);gl.uniform4f(uniforms.viewport,width,height,Math.min(1,aspect/sourceAspect),Math.min(1,sourceAspect/aspect));
      gl.uniform1i(uniforms.background,frame.background);
      const rectangles=[...frame.coverage.map(rectangle=>({rectangle,before:frame.takeoverTarget,after:frame.takeoverTarget,weight:0})),...frame.windows];
      rectangles.forEach((r,i)=>{bounds.set(r.rectangle.map((v,j)=>roundEven(v*(j%2?height/718:width/984))),i*4);blends.set([r.before,r.after,r.weight,0],i*4);});
      gl.uniform1i(uniforms.rectangleCount,rectangles.length);gl.uniform4fv(uniforms.bounds,bounds);gl.uniform4fv(uniforms.blends,blends);
      frame.luts.forEach((rgb,i)=>luts.set([...rgb,255],i*4));
      gl.activeTexture(gl.TEXTURE3);gl.bindTexture(gl.TEXTURE_2D,textures[3]);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,256,2,0,gl.RGBA,gl.UNSIGNED_BYTE,luts);
      gl.drawArrays(gl.TRIANGLES,0,3);
    },
  };
}
