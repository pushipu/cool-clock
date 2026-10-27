import { CloudScene, wrap } from './cloud-scene.js';
import { createCloudRenderer } from './cloud-renderer.js';
import { createDial } from './dial.js';
import { createFatalErrorHandler } from './fatal-error.js';

const query=new URLSearchParams(location.search);
// Deterministic local visual checks; never enabled by the screensaver host.
const testTime=query.has('testTime')&&Number.isFinite(Number(query.get('testTime')))?wrap(Number(query.get('testTime'))):null;
const testClockTime=query.has('testClockTime')&&Number.isFinite(Number(query.get('testClockTime')))?Number(query.get('testClockTime')):8*3600+58*60+22.12+(testTime??0);
const mode=['screen','preview','window'].includes(query.get('mode'))?query.get('mode'):'window';
let sound=mode!=='preview'&&query.get('sound')==='1';
document.body.dataset.mode=mode;
const bridge=window.chrome?.webview;
const post=message=>{if(['ready','exit','sound:on','sound:off','error'].includes(message))bridge?.postMessage(message);};
const errorElement=document.querySelector('#error');
const diagnostics={mode,ready:false,fatal:false,paused:true,sound,backgroundFrames:0,dialFrames:0,videoFrames:[0,0,0],textureUploads:[0,0,0],seekCounts:[0,0,0],audioSeeks:0,errors:[]};
Object.defineProperty(window,'__clockDiagnostics',{get:()=>Object.freeze({...diagnostics,videoFrames:Object.freeze([...diagnostics.videoFrames]),textureUploads:Object.freeze([...diagnostics.textureUploads]),seekCounts:Object.freeze([...diagnostics.seekCounts]),errors:Object.freeze([...diagnostics.errors])})});
function showError(message){diagnostics.errors.push(String(message));errorElement.textContent=String(message);errorElement.hidden=false;}
const failure=createFatalErrorHandler({
  stop(){
    diagnostics.fatal=true;diagnostics.ready=false;hostPaused=true;setRunning();
    // Also stop partially initialized or deterministic playback.
    cancelAnimationFrame(raf);videos.forEach(video=>video.pause());audio.pause();
  },
  display:showError,
  post,
});
const fail=message=>failure.fail(message);
const localTime=()=>{const d=new Date();return d.getHours()*3600+d.getMinutes()*60+d.getSeconds()+d.getMilliseconds()/1000;};
let hostPaused=false,initialized=false,running=false,raf=0,generation=0;
let animationElapsed=0,animationStarted=performance.now(),lastBackground=-Infinity,lastDial=-Infinity,lastAudioCheck=-Infinity;
const sceneTime=()=>wrap(animationElapsed+(running?(performance.now()-animationStarted)/1000:0));
const videos=[],dirty=[false,false,false],callbacks=[null,null,null],lastVideoTime=[-1,-1,-1];
const offsets=[0,7,13];
const audio=document.createElement('audio');audio.src='assets/audio/clock-minute.wav';audio.loop=true;audio.preload='auto';audio.volume=sound?1:0;document.body.append(audio);
let audioReady=false;
audio.addEventListener('loadedmetadata',()=>{
  if(Math.abs(audio.duration-60)>.02){fail('Минутная аудиодорожка повреждена.');return;}
  audioReady=true;if(running)startAudio(generation);
});
audio.addEventListener('error',()=>fail('Не удалось загрузить минутную аудиодорожку.'));
async function startAudio(token){
  if(!audioReady||!running)return;
  audio.currentTime=localTime()%60;diagnostics.audioSeeks++;
  try{await audio.play();if(!running)audio.pause();}
  catch(error){
    if(token!==generation||error.name==='AbortError')return;
    if(error.name==='NotAllowedError'){
      // A standalone browser may require a click; the native host grants autoplay.
      if(sound){setSound(false,true);showError('Браузер заблокировал звук. Нажмите на часы, чтобы включить его.');}
    }else fail('Не удалось воспроизвести минутную аудиодорожку.');
  }
}
function setSound(enabled,notify=false){
  sound=mode!=='preview'&&enabled;audio.volume=sound?1:0;diagnostics.sound=sound;
  if(running&&audioReady&&audio.paused)startAudio(generation);
  if(notify)post(sound?'sound:on':'sound:off');
}
function requestVideo(index){
  const video=videos[index];
  if(!running||!video.requestVideoFrameCallback)return;
  callbacks[index]=video.requestVideoFrameCallback(()=>{
    callbacks[index]=null;dirty[index]=true;diagnostics.videoFrames[index]++;
    requestVideo(index);
  });
}
function setRunning(){
  const active=initialized&&!failure.failed&&testTime===null&&!document.hidden&&!hostPaused;
  if(active===running)return;
  generation++;
  if(!active){
    animationElapsed=sceneTime();running=false;diagnostics.paused=true;cancelAnimationFrame(raf);
    videos.forEach((video,i)=>{video.pause();if(callbacks[i]!==null)video.cancelVideoFrameCallback?.(callbacks[i]);callbacks[i]=null;});audio.pause();return;
  }
  running=true;diagnostics.paused=false;animationStarted=performance.now();lastBackground=lastDial=-Infinity;
  const token=generation;
  videos.forEach((video,i)=>{
    video.currentTime=(animationElapsed+offsets[i])%29;diagnostics.seekCounts[i]++;requestVideo(i);
    video.play().then(()=>{if(!running)video.pause();}).catch(error=>{if(token===generation&&error.name!=='AbortError')fail('Не удалось воспроизвести видео облаков.');});
  });
  startAudio(token);raf=requestAnimationFrame(render);
}
bridge?.addEventListener('message',event=>{
  if(event.data==='pause'){hostPaused=true;setRunning();}
  else if(event.data==='resume'){hostPaused=false;setRunning();}
  else if(event.data==='sound:on')setSound(true);
  else if(event.data==='sound:off')setSound(false);
});
document.addEventListener('visibilitychange',setRunning);
window.addEventListener('pagehide',()=>{hostPaused=true;setRunning();});
window.addEventListener('pageshow',()=>{hostPaused=false;setRunning();});
window.addEventListener('pointerdown',()=>{if(mode==='screen')post('exit');else if(mode==='window')setSound(!sound,true);});
window.addEventListener('keydown',event=>{if(mode==='screen'||event.key==='Escape'){event.preventDefault();post('exit');}});
let pointerOrigin=null;
window.addEventListener('pointermove',event=>{
  if(mode!=='screen')return;
  if(!pointerOrigin){pointerOrigin=[event.clientX,event.clientY];return;}
  if(Math.hypot(event.clientX-pointerOrigin[0],event.clientY-pointerOrigin[1])>5)post('exit');
});
window.addEventListener('wheel',()=>{if(mode==='screen')post('exit');},{passive:true});
const background=document.querySelector('#clouds'),dialCanvas=document.querySelector('#dial');
let renderer,drawDial,scene;
function resize(){
  const ratio=Math.min(devicePixelRatio||1,2);
  for(const canvas of [background,dialCanvas]){canvas.width=Math.max(1,Math.round(innerWidth*ratio));canvas.height=Math.max(1,Math.round(innerHeight*ratio));}
  lastBackground=lastDial=-Infinity;
}
new ResizeObserver(resize).observe(document.documentElement);
background.addEventListener('webglcontextlost',event=>{event.preventDefault();hostPaused=true;setRunning();fail('Графический контекст потерян. Перезапустите заставку.');});
function render(now){
  if(!running)return;
  try{
    if(now-lastBackground>=1000/60-.5){
      videos.forEach((video,i)=>{
        if(!video.requestVideoFrameCallback&&video.currentTime!==lastVideoTime[i]&&video.readyState>=2){dirty[i]=true;diagnostics.videoFrames[i]++;lastVideoTime[i]=video.currentTime;}
        if(dirty[i]&&video.readyState>=2&&!video.seeking){renderer.upload(i,video);dirty[i]=false;diagnostics.textureUploads[i]++;}
      });
      if(diagnostics.textureUploads.every(n=>n>0)){
        renderer.draw(scene.frameAt(sceneTime()));diagnostics.backgroundFrames++;
        // A decoded first frame alone cannot prove that all three videos are playing.
        if(!diagnostics.ready&&diagnostics.backgroundFrames>=30&&diagnostics.dialFrames>=5&&diagnostics.videoFrames.every(n=>n>=10)){diagnostics.ready=true;post('ready');}
      }
      lastBackground=now;
    }
    if(now-lastAudioCheck>=1000){
      lastAudioCheck=now;
      if(audioReady&&!audio.paused&&!audio.seeking){
        const drift=((audio.currentTime-localTime()%60+90)%60)-30;
        if(Math.abs(drift)>.5)startAudio(generation);
      }
    }
    if(now-lastDial>=1000/30-.5){
      const time=localTime(),phase=audioReady&&!audio.paused&&!audio.seeking?audio.currentTime:time;
      drawDial(time,phase,sceneTime());lastDial=now;diagnostics.dialFrames++;
    }
  }catch(error){fail(error.message);hostPaused=true;setRunning();return;}
  raf=requestAnimationFrame(render);
}
async function loadVideo(path,index){
  const video=document.createElement('video');video.muted=true;video.loop=true;video.playsInline=true;video.preload='auto';videos[index]=video;document.body.append(video);
  video.addEventListener('error',()=>fail(`Не удалось загрузить видео облаков ${index+1}.`));
  await new Promise((resolve,reject)=>{video.addEventListener('loadedmetadata',resolve,{once:true});video.addEventListener('error',()=>reject(new Error(`Видео ${index+1} недоступно.`)),{once:true});video.src=path;});
  if(Math.abs(video.duration-29)>.1||video.videoWidth===0)throw new Error(`Неверный формат видео ${index+1}.`);
}
try{
  const response=await fetch('assets/rectangle-tracks.json');if(!response.ok)throw new Error('Не удалось загрузить анимацию прямоугольников.');
  scene=new CloudScene(await response.json());renderer=createCloudRenderer(background);drawDial=createDial(dialCanvas,testTime!==null&&query.get('testReference')==='1');resize();
  await Promise.all(['assets/cloud-swift.mp4','assets/cloud-cirrus.mp4','assets/cloud-swift.mp4'].map(loadVideo));
  if(failure.failed)throw new Error('Инициализация остановлена после ошибки.');
  if(testTime!==null){
    await Promise.all(videos.map((video,i)=>new Promise((resolve,reject)=>{
      const target=(testTime+offsets[i])%29;
      video.addEventListener('seeked',resolve,{once:true});
      video.addEventListener('error',()=>reject(new Error('Не удалось получить контрольный кадр.')),{once:true});
      // A nonzero seek also handles the first frame of a source at time zero.
      video.currentTime=target===0?.000001:target;diagnostics.seekCounts[i]++;
    })));
    if(failure.failed)throw new Error('Контрольный кадр остановлен после ошибки.');
    videos.forEach((video,i)=>{renderer.upload(i,video);diagnostics.textureUploads[i]++;diagnostics.videoFrames[i]++;});
    renderer.draw(scene.frameAt(testTime));drawDial(testClockTime,testClockTime,testTime);
    diagnostics.backgroundFrames++;diagnostics.dialFrames++;diagnostics.ready=true;post('ready');
  }else{initialized=true;setRunning();}
}catch(error){fail(error.message);}
