import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { CloudScene, DURATION, HANDOFF_INTERVAL, wrap } from '../windows/web/cloud-scene.js';
const tracks=JSON.parse(readFileSync(new URL('../assets/rectangle-tracks.json',import.meta.url)));
const scene=new CloudScene(tracks);

test('rectangle tracks reject malformed, inverted and non-finite geometry',()=>{
  for(const invalid of [null,[],tracks.slice(1),tracks.map(t=>t.slice(1))])assert.throws(()=>new CloudScene(invalid),TypeError);
  for(const r of [[0,0,985,718],[0,0,984,719],[2,0,1,10],[0,3,10,2],[NaN,0,10,10],[0,0,Infinity,10]]){
    const copy=structuredClone(tracks);copy[0][0]=r;assert.throws(()=>new CloudScene(copy),TypeError);
  }
});
test('input tracks are copied and every frame is periodic',()=>{
  const input=structuredClone(tracks),copy=new CloudScene(input);input[0][0][0]=999;
  assert.deepEqual(copy.frameAt(0),scene.frameAt(0));
  for(const t of [0,4,29,58,115])assert.deepEqual(scene.frameAt(t),scene.frameAt(t+DURATION));
  assert.deepEqual(scene.frameAt(-1),scene.frameAt(115));
  assert.deepEqual(scene.frameAt(NaN),scene.frameAt(0));
  assert.equal(wrap(Infinity),0);
});
test('staging, expansion and handoff use the native transition sequence',()=>{
  assert.equal(scene.frameAt(0).background,0);
  assert.deepEqual(scene.frameAt(0).windows.map(w=>w.before),[1,2,3,4,1,5,6]);
  const staged=scene.frameAt(3.5);assert.equal(staged.coverage.length,0);assert.ok(staged.windows[1].weight>0&&staged.windows[1].weight<1);assert.equal(staged.windows[1].after,1);
  const active=scene.frameAt(5);assert.equal(active.takeoverTarget,1);assert.equal(active.coverage.length,9);assert.equal(active.background,0);
  const complete=scene.frameAt(6.08);assert.equal(complete.background,1);assert.equal(complete.takeoverTarget,null);assert.equal(complete.coverage.length,0);
  assert.equal(scene.frameAt(4+HANDOFF_INTERVAL).takeoverTarget,2);
  assert.equal(scene.frameAt(115.99).background,0);
});
test('all samples retain bounded valid geometry, blend factors and colour bytes',()=>{
  for(let t=0;t<116;t+=.137){
    const f=scene.frameAt(t);assert.equal(f.windows.length,7);assert.equal(f.luts.length,512);
    for(const w of f.windows){const [l,top,r,b]=w.rectangle;assert.ok(l>=0&&l<r&&r<=984&&top>=0&&top<b&&b<=718);assert.ok(w.weight>=0&&w.weight<=1);assert.ok(w.before>=0&&w.before<=6&&w.after>=0&&w.after<=6);}
    for(const rgb of f.luts)for(const c of rgb)assert.ok(Number.isInteger(c)&&c>=0&&c<=255);
    assert.deepEqual(f.luts[0],[3,7,23]);
  }
});
const fixture=new URL('./fixtures/windows-cloud-scene.json',import.meta.url);
test('JavaScript frames match native Swift snapshots', ()=>{
  const snapshots=JSON.parse(readFileSync(fixture));
  function compare(actual,expected,path='frame'){
    if(typeof expected==='number'){assert.ok(Math.abs(actual-expected)<1e-9,`${path}: ${actual} != ${expected}`);return;}
    if(expected===null||typeof expected!=='object'){assert.equal(actual,expected,path);return;}
    assert.deepEqual(Object.keys(actual).sort(),Object.keys(expected).sort(),`${path} keys`);
    for(const key of Object.keys(expected))compare(actual[key],expected[key],`${path}.${key}`);
  }
  for(const entry of snapshots)compare(scene.frameAt(entry.seconds),entry.frame);
});


test('fatal renderer errors stop playback and invalidate host health only once', async()=>{
  const { createFatalErrorHandler }=await import('../windows/web/fatal-error.js');
  const events=[];
  const failure=createFatalErrorHandler({stop:()=>events.push('stop'),display:message=>events.push(message),post:message=>events.push(message)});
  assert.equal(failure.failed,false);
  failure.fail('decode failed after ready');
  assert.equal(failure.failed,true);
  failure.fail('another pending stream failed');
  assert.deepEqual(events,['stop','decode failed after ready','error']);
});
