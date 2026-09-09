'use strict';
// Read-only ISO research tool. Emits settings/identity tags, never modifies the ISO or profiles.
const fs = require('node:fs'), assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {archive} = require('./socom_geometry/archive.cjs');
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
function isoFile(file, names) {
  const fd = fs.openSync(file, 'r');
  try {
    const read = (at, n) => { assert(n > 0 && n < 8e6); const b=Buffer.alloc(n);
      assert.equal(fs.readSync(fd,b,0,n,at),n,'short ISO read'); return b; };
    const pvd=read(16*2048,2048); assert.equal(pvd.toString('ascii',1,6),'CD001');
    let lba=pvd.readUInt32LE(158), size=pvd.readUInt32LE(166);
    for (let level=0;level<names.length;level++) {
      const b=read(lba*2048,size), matches=[];
      for(let p=0;p<b.length;) {const n=b[p]; if(!n){p=(Math.floor(p/2048)+1)*2048;continue;}
        assert(n>=34 && p+n<=b.length); const len=b[p+32]; assert(33+len<=n);
        const name=b.toString('ascii',p+33,p+33+len).replace(/;\d+$/,'');
        if(name===names[level]) matches.push({lba:b.readUInt32LE(p+2),size:b.readUInt32LE(p+10),dir:!!(b[p+25]&2)});
        p+=n;
      }
      assert.equal(matches.length,1,'missing/ambiguous ISO path');
      assert.equal(matches[0].dir,level<names.length-1); ({lba,size}=matches[0]);
    }
    return read(lba*2048,size);
  } finally {fs.closeSync(fd);}
}
// Compiled reader layout already established by the local animation reader.
function reader(b) {
  assert(b.length>=12 && b.readUInt32LE(0)===1,'unsupported reader');
  const end=12+b.readUInt32LE(4),base=b.readUInt32LE(8),seen=new Set(),active=new Set();
  assert(end<=base && base+8<=b.length);
  function node(offset,depth=0) {
    assert(depth<128 && offset>=0 && offset%8===0 && base+offset+8<=b.length);
    assert(!active.has(offset),'cyclic reader'); seen.add(offset);
    const p=base+offset,bits=b.readUInt32LE(p),type=bits&255,value=b.readUInt32LE(p+4),count=bits>>>16;
    if(type===0)return null;
    if(type===1)return b.readInt32LE(p+4);
    if(type===2){const v=b.readFloatLE(p+4);assert(Number.isFinite(v));return v;}
    if(type===3){const start=12+value,last=b.indexOf(0,start);assert(start>=12&&last>=start&&last<end);return b.toString('utf8',start,last);}
    assert.equal(type,4);assert(base+value+count*8<=b.length);active.add(offset);
    const a=Array.from({length:count},(_,i)=>node(value+i*8,depth+1)); active.delete(offset); return a;
  }
  const result=node(0);assert.equal(seen.size*8,b.length-base,'unvisited reader bytes');return result;
}
function pairs(a) {
  assert(Array.isArray(a)&&a.length%2===0);const out={};
  for(let i=0;i<a.length;i+=2){assert(typeof a[i]==='string'&&!Object.hasOwn(out,a[i]),'duplicate/non-string key');out[a[i]]=a[i+1];}return out;
}
function taggedFields(row, unparsed, context) {
  assert(Array.isArray(row)); const fields={};
  for(let i=0;i<row.length;i++){
    if(typeof row[i]==='string'&&Array.isArray(row[i+1])){assert(!Object.hasOwn(fields,row[i]));fields[row[i]]=row[++i];}
    else unparsed.push({context,value:row[i]});
  }
  return fields;
}
function extract(iso) {
  const b=isoFile(iso,['RUN','ZWEAPON.ZAR']);const e=archive(b).entries.filter(e=>e.name==='zweapon.rdr');assert.equal(e.length,1);
  const raw=b.subarray(e[0].offset,e[0].offset+e[0].size),root=pairs(reader(raw));
  const weapons=[];
  for(const row of root.ZWEAPON){
    // Two shipped records include bare prose ("from", 40, ...). Only explicit
    // tag/list pairs are fields. Keep all other atoms for review, never shift pairs.
    const unparsed_atoms=[],stances={},r=taggedFields(row,unparsed_atoms,'weapon');
    for(const [name,fields] of Object.entries(pairs(r.Reticule_Modifiers||[]))){
      stances[name]={};for(const [key,value] of Object.entries(taggedFields(fields,unparsed_atoms,name))){if(Array.isArray(value)&&value.length===1&&typeof value[0]==='number')stances[name][key]=value[0];}
    }
    const numeric={};for(const [key,value] of Object.entries(r)){if(Array.isArray(value)&&value.length===1&&typeof value[0]==='number')numeric[key]=value[0];}
    const mode_flags=['SingleMode','BurstMode','AutoMode'].filter(key=>Object.hasOwn(r,key));
    for(const key of mode_flags)assert.deepEqual(r[key],[],'mode tag must be empty');
    weapons.push({name:r.InternalName[0],display_name:r.DisplayName[0],mode_flags,numeric,stances,...(unparsed_atoms.length?{unparsed_atoms}:{})});
  }
  return {schema_version:1,source:{game:'SOCOM II USA',archive:'RUN/ZWEAPON.ZAR',entry:'zweapon.rdr',archive_sha256:sha(b),reader_sha256:sha(raw)},
    status:'Exact numeric settings; executable equations and screen-unit conversion are not recovered',weapons};
}
if(require.main===module){assert(process.argv[2],'usage: node tools/socom2_weapon_reference.cjs path/to/game.iso');console.log(JSON.stringify(extract(process.argv[2]),null,2));}
module.exports={extract,reader,pairs};
