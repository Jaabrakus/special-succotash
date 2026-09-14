'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const vm = require('node:vm');
const {range, hashRange, directory, inventory, freshOutput, policy} = require('./source_asset_inventory.cjs');
const {archive} = require('./socom_geometry/archive.cjs');
const {zdbEntries} = require('./source_runtime_module_inventory.cjs');
const {openIso} = require('./extract_iso_camera_reference.cjs');
const {selection, recover} = require('./recover_source_assets.cjs');
const {candidates, validateMotion} = require('./decode_source_motion_library.cjs');
const {html} = require('./build_source_asset_library_index.cjs');
let checks = 0;
function check(fn) {fn(); checks++;}
function reader(b) {return {size:b.length, readRange(offset,size) {range(offset,size,b.length); return b.subarray(offset,offset+size);}};}
function bank() {
  const names = Buffer.from('../../outside\0same.raw\0'), count = 3;
  const table = 100 + names.length, payload = Math.ceil((table + count * 16) / 16) * 16;
  const b = Buffer.alloc(payload + 4);
  b.writeUInt32LE(count,4); b.writeUInt32LE(names.length,8); b.writeUInt32LE(16,16); b.writeUInt32LE(0x20002,96);
  names.copy(b,100); b.writeUInt32LE(2,table + 12);
  for(let i=1;i<count;i++){b.writeUInt32LE(i===1?0:14,table+i*16);b.writeUInt32LE(4,table+i*16+8);}
  b.write('DATA',payload);
  return {b,table,payload};
}
function isoRecord(name, sector, size, isDir = false) {
  const b = Buffer.alloc(Math.max(34, 33 + name.length + ((33+name.length)%2)));
  b[0]=b.length; b.writeUInt32LE(sector,2);b.writeUInt32BE(sector,6);
  b.writeUInt32LE(size,10);b.writeUInt32BE(size,14);b[25]=isDir?2:0;b[32]=name.length;name.copy(b,33);return b;
}
const temp = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()),'socom-source-library-test-'));
const {b,table,payload} = bank();
check(()=>assert.equal(archive(b).entries.length,3));
check(()=>assert.deepEqual(archive(b.subarray(0,table+48),b.length),archive(b)));
check(()=>assert.equal(directory(reader(b),0,b.length).format,'ZAR_KEY_TREE'));
check(()=>assert.throws(()=>archive(b.subarray(0,99))));
check(()=>assert.throws(()=>archive(b.subarray(0,table+47),b.length)));
check(()=>assert.throws(()=>archive(b,b.length-1)));
check(()=>{const bad=Buffer.from(b);bad.writeUInt32LE(0xffffffff,table+16+4);assert.throws(()=>archive(bad));});
check(()=>{const bad=Buffer.from(b);bad.writeUInt32LE(0xffffffff,8);assert.throws(()=>directory(reader(bad),0,bad.length));});
check(()=>{const bad=Buffer.from(b);bad.writeUInt32LE(0xffffffff,table+16);assert.throws(()=>archive(bad));});
check(()=>{const bad=Buffer.from(b);bad.writeUInt32LE(3,table+12);assert.throws(()=>archive(bad));});
check(()=>assert.throws(()=>range(-1,4,10)));
check(()=>assert.throws(()=>range(0,11,10)));
check(()=>assert.throws(()=>range(0,1.1,10)));
check(()=>assert.throws(()=>range(Number.MAX_SAFE_INTEGER+1,0,Number.MAX_SAFE_INTEGER+1)));
check(()=>assert.equal(directory(reader(Buffer.alloc(8)),0,8),null));
check(()=>{
  const z=Buffer.alloc(256);z.writeUInt32LE(252,0);z.writeUInt32LE(1,4);z.writeUInt32LE(1,152);z.writeUInt32LE(92,156);
  z.writeUInt32LE(92,160);z.write('DATA.RAW',164);z.writeUInt32LE(252,228);z.writeUInt32LE(4,232);
  assert.deepEqual(zdbEntries(z.subarray(0,252),256),zdbEntries(z));
  assert.equal(directory(reader(z),0,256).format,'ZDB_92');
  z.writeUInt32LE(8,232);assert.throws(()=>zdbEntries(z));
});
check(()=>{
  const sizes=[];hashRange({size:policy.chunk_bytes*2+3,readRange(o,s){sizes.push(s);return Buffer.alloc(s);}},0,policy.chunk_bytes*2+3);
  assert.deepEqual(sizes,[policy.chunk_bytes,policy.chunk_bytes,3]);
});
const image=Buffer.alloc(24*2048), pvd=16*2048;
image[pvd]=1;image.write('CD001',pvd+1);image[pvd+6]=1;image.write('TEST',pvd+40);image.writeUInt16LE(2048,pvd+128);
isoRecord(Buffer.from([0]),20,2048,true).copy(image,pvd+156);
let cursor=20*2048;
for(const record of [isoRecord(Buffer.from([0]),20,2048,true),isoRecord(Buffer.from([1]),20,2048,true),isoRecord(Buffer.from('ASSET.ZAR;1'),21,b.length)]) {record.copy(image,cursor);cursor+=record.length;}
b.copy(image,21*2048);
const isoFile=path.join(temp,'fixture.iso');fs.writeFileSync(isoFile,image,{flag:'wx'});
check(()=>{const iso=openIso(isoFile);try{assert.equal(iso.list().length,1);assert.throws(()=>iso.readRange(image.length,1));assert.throws(()=>iso.readRange(0,65*1024*1024));assert.equal(iso.find('ASSET.ZAR').size,b.length);}finally{iso.close();}});
const catalog=inventory(isoFile);
check(()=>assert.equal(catalog.summary.disc_files,1));
check(()=>assert.equal(catalog.summary.records,3));
check(()=>assert.equal(catalog.summary.unique_nonmovie_raw_payloads,1));
check(()=>assert.equal(catalog.records[1].name,'../../outside'));
check(()=>{
  const hierarchical=Buffer.from(image);const start=21*2048;
  hierarchical.writeUInt32LE(1,start+table+12);hierarchical.writeUInt32LE(1,start+table+16+12);
  const file=path.join(temp,'hierarchical.iso');fs.writeFileSync(file,hierarchical,{flag:'wx'});
  const c=inventory(file);assert.equal(c.records.length,1);
  assert.equal(c.records[0].status,'structured_key_tree_preserved_not_decoded');
  assert.equal(c.records[0].property_key_count,2);assert.equal(selection(c).length,1);
});
check(()=>{
  const renamed=Buffer.from(image);const label=Buffer.from('ASSET.ZAR;1');
  const at=renamed.indexOf(label,20*2048);assert(at>0);renamed.write('ASSET.ZED;1',at);
  const file=path.join(temp,'property-tree.iso');fs.writeFileSync(file,renamed,{flag:'wx'});
  const c=inventory(file);assert.equal(c.records.length,1);assert.equal(c.records[0].container,null);
});
check(()=>assert.equal(selection(catalog).length,1));
check(()=>{
  const c=structuredClone(catalog);c.records[1].name='</script><img src=x onerror=alert(1)>';
  const doc=html(c,{summary:{recovered_files:0,verified_existing_files:0},files:[]},{summary:{unique_decoded_clips:0},entries:[]},{output:path.join(temp,'index.html'),recovery:path.join(temp,'raw.json'),motion:path.join(temp,'motion.json')});
  assert(!doc.includes('</script><img'));assert(doc.includes('\\u003c/script>'));assert(doc.includes('textContent=value'));assert(doc.includes('not a completed Godot port'));
  const element=()=>({value:'',children:[],replaceChildren(){this.children=[];},append(child){this.children.push(child);}});
  const nodes=Object.fromEntries(['search','filter','count','rows','back','next'].map(k=>[k,element()]));nodes.filter.value='all';
  vm.runInNewContext(doc.match(/<script>([\s\S]*)<\/script>/)[1],{document:{getElementById:id=>nodes[id],createElement:element}});
  assert.equal(nodes.rows.children.length,3);nodes.search.value='</script>';nodes.search.oninput();assert.equal(nodes.rows.children.length,1);
  nodes.filter.value='motion';nodes.filter.onchange();assert.equal(nodes.rows.children.length,0);
});
check(()=>assert.throws(()=>selection(catalog,'unbounded')));
check(()=>assert.equal(selection(catalog,'motions').length,0));
check(()=>{
  const c=structuredClone(catalog);c.records[0].name='RUN/MOTION_P.ZAR';
  assert.equal(candidates(c).clips.length,2);assert.equal(selection(c,'motions').length,1);
});
check(()=>{
  const m={version:5,duration:1,frames:1,samples:2,bone_count:1,tracks:[{name:'root',positions_raw:[[0,0,0]],rotations_raw:[[0,0,0,32767]]}]};
  validateMotion(m);m.duration=NaN;assert.throws(()=>validateMotion(m));m.duration=1;
  m.tracks[0].rotations_raw[0][3]=32768;assert.throws(()=>validateMotion(m));
});
check(()=>{const c=structuredClone(catalog);c.records[1].sha256='../../outside';assert.throws(()=>selection(c));});
check(()=>{const c=structuredClone(catalog);c.records[1].offset=image.length;assert.throws(()=>selection(c));});
check(()=>{const c=structuredClone(catalog);c.records.push({...c.records[1],sha256:'a'.repeat(64),top_file:'MOVIE.PSS'});assert.equal(selection(c).length,1);});
const catalogFile=path.join(temp,'catalog.json');fs.writeFileSync(catalogFile,JSON.stringify(catalog),{flag:'wx'});
const recovered=path.join(temp,'recovered');
check(()=>{
  const r=recover(catalogFile,recovered);assert.equal(r.summary.recovered_files,1);assert.equal(r.summary.recovered_bytes,4);
  assert.equal(fs.readFileSync(path.join(recovered,r.files[0].file),'utf8'),'DATA');
  assert(fs.existsSync(path.join(recovered,'.gdignore')));assert(!fs.existsSync(path.join(temp,'outside')));
});
check(()=>assert.throws(()=>recover(catalogFile,recovered)));
check(()=>assert.throws(()=>freshOutput(path.join(temp,'low-space'),Number.MAX_SAFE_INTEGER)));
check(()=>assert(!fs.existsSync(path.join(temp,'low-space'))));
check(()=>{
  const link=path.join(temp,'alias');fs.symlinkSync(temp,link,'dir');assert.throws(()=>freshOutput(path.join(link,'no-write')));
});
check(()=>{
  const changed=structuredClone(catalog);changed.records[1].sha256='b'.repeat(64);
  const file=path.join(temp,'bad-catalog.json');fs.writeFileSync(file,JSON.stringify(changed),{flag:'wx'});
  const out=path.join(temp,'bad-output');assert.throws(()=>recover(file,out));assert(!fs.existsSync(out));
});
check(()=>{
  const changed=structuredClone(catalog);changed.source.sha256='b'.repeat(64);
  const file=path.join(temp,'wrong-iso.json');fs.writeFileSync(file,JSON.stringify(changed),{flag:'wx'});
  const out=path.join(temp,'wrong-output');assert.throws(()=>recover(file,out));assert(!fs.existsSync(out));
});
if (process.argv[2]) {
  const {motion}=require(path.resolve(process.argv[2]));
  const b=Buffer.alloc(76);b.writeUInt32LE(5,0);b.writeFloatLE(1,4);b.writeUInt32LE(1,8);b.writeUInt32LE(1,12);
  b.writeUInt32LE(48,24);b.writeUInt32LE(56,28);b.write('root',48);b.writeUInt32LE(0x3c,56);
  b.writeInt16LE(-123,60);b.writeInt16LE(456,62);b.writeInt16LE(-789,64);b.writeInt16LE(32767,74);
  check(()=>{const d=motion(b);validateMotion(d);assert.equal(d.duration,1);assert.equal(d.samples,2);assert.equal(d.tracks[0].name,'root');assert.deepEqual(d.tracks[0].positions_raw,[[-123,456,-789]]);assert.deepEqual(d.tracks[0].rotations_raw,[[0,0,0,32767]]);});
  check(()=>assert.throws(()=>motion(b.subarray(0,75))));
  check(()=>{const invalid=Buffer.from(b);invalid.writeUInt32LE(99,0);assert.throws(()=>motion(invalid));});
  check(()=>{const invalid=Buffer.from(b);invalid.writeUInt32LE(0xffffffff,56);assert.throws(()=>motion(invalid));});
}
console.log(`SOURCE_ASSET_LIBRARY_TEST PASS: ${checks} checks; disposable fixture files: ${temp}`);
