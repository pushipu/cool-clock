import { createText } from './language.js';

// Exact timeline and colour grading used by macOS CloudScene.swift.
export const DURATION = 116;
export const SOURCE_DURATION = 29;
export const HANDOFF_INTERVAL = DURATION / 14;
const motionScale = (DURATION / 3) / 30;
const initial = [1, 2, 3, 4, 1, 5, 6];
const colors = [[65,122,240],[215,225,242],[100,171,255],[41,66,135],[114,186,255],[51,79,151]];
const exposure = [1, 1.16, 1.12, .72, 1.15, .72];
const light = Array.from({length:256}, (_,i) => Math.pow(Math.min(1, Math.max(0,(i-20)/215)),1.3));
const patterns = [
  [1,[0,1,3,4,6],[3,2,4,0,6,5,2]],
  [2,[1,3,6],[6,5,1,0,3,4,1]],
  [1,[1,2,3,6],[3,2,4,0,6,5,2]],
  [0,[1,3,6],initial],
];
const events = [0,1,2,3,0,1,2,3,0,1,2,3,0,3].map((pattern,index) => ({
  start:4+index*HANDOFF_INTERVAL, end:6.08+index*HANDOFF_INTERVAL,
  target:patterns[pattern][0], participants:patterns[pattern][1], following:patterns[pattern][2],
}));
const clamp = value => Math.min(1,Math.max(0,value));
const ease = value => {const x=clamp(value); return x*x*(3-2*x);};
export function wrap(seconds) {
  if (!Number.isFinite(seconds)) return 0;
  const value=seconds%DURATION;
  return value<0?value+DURATION:value;
}
function phase(seconds) {
  const position=(wrap(seconds)*3/DURATION%1)*6;
  return [Math.floor(position),ease(position-Math.floor(position))];
}
function lut(seconds,inner) {
  const [ci,cw]=phase(seconds+(inner?motionScale:0));
  const white=colors[ci].map((v,i)=>v+(colors[(ci+1)%6][i]-v)*cw);
  const [ei,ew]=phase(seconds);
  const brightness=exposure[ei]+(exposure[(ei+1)%6]-exposure[ei])*ew;
  return light.map(value=>[3,7,23].map((black,i)=>Math.trunc(black+clamp(value*brightness)*(white[i]-black))));
}
export class CloudScene {
  constructor(tracks,language='en') {
    if (!Array.isArray(tracks)||tracks.length!==7||!tracks.every(track=>Array.isArray(track)&&track.length===6&&track.every(r=>
      Array.isArray(r)&&r.length===4&&r.every(Number.isFinite)&&r[0]>=0&&r[0]<r[2]&&r[2]<=984&&r[1]>=0&&r[1]<r[3]&&r[3]<=718))) {
      throw new TypeError(createText(language)('Invalid rectangle tracks', 'Неверные данные анимации прямоугольников'));
    }
    this.tracks=tracks.map(track=>track.map(r=>Object.freeze([...r])));
  }
  rectangle(track,seconds) {
    const [index,weight]=phase(seconds), values=this.tracks[track];
    return values[index].map((v,i)=>v+(values[(index+1)%6][i]-v)*weight);
  }
  coverage(event,seconds) {
    const progress=clamp((seconds-event.start)/(event.end-event.start));
    const seeds=[1,3,6].map(i=>this.rectangle(i,event.start));
    const rows=[0,(seeds[0][3]+seeds[1][1])/2,(seeds[1][3]+seeds[2][1])/2,718];
    const columns=[0,244,739,984], result=[];
    for(let column=0;column<3;column++) {
      const left=columns[column],right=columns[column+1];
      seeds.forEach((seed,row)=>{
        const initial=[Math.min(right,Math.max(left,seed[0])),seed[1],Math.min(right,Math.max(left,seed[2])),seed[3]];
        const destination=[left,rows[row],right,rows[row+1]];
        const delay=.07*((column+2*row)%5),weight=ease((progress-delay)/(1-delay));
        result.push(initial.map((v,i)=>v*(1-weight)+destination[i]*weight));
      });
    }
    return result;
  }
  frameAt(seconds) {
    const time=wrap(seconds);
    let background=0,sources=initial,windows=[],active=null;
    const makeWindows=(before,after,weight)=>Array.from({length:7},(_,i)=>({rectangle:this.rectangle(i,time),before:before[i],after:after[i],weight:typeof weight==='function'?weight(i):weight}));
    for(const event of events) {
      if(time<event.start-.65*1.3) break;
      const staged=sources.map((source,i)=>event.participants.includes(i)?event.target:source);
      if(time<event.start) {windows=makeWindows(sources,staged,ease((time-event.start+.65*1.3)/(.65*1.3)));break;}
      if(time<event.end) {windows=makeWindows(staged,staged,0);active=event;break;}
      background=event.target;
      if(time<event.end+.25*1.3+1.2*1.3) {
        windows=makeWindows(staged,event.following,i=>ease((time-event.end-.25*1.3-.06*1.3*i)/(.84*1.3)));break;
      }
      sources=event.following;
    }
    if(!windows.length) windows=makeWindows(sources,sources,0);
    return {background,windows,takeoverTarget:active?.target??null,coverage:active?this.coverage(active,time):[],luts:[...lut(time,false),...lut(time,true)]};
  }
}
export const frameAt = (tracks,seconds) => new CloudScene(tracks).frameAt(seconds);
