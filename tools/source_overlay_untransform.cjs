'use strict';
// Static translation of DNAS.BIN 0x5412a0/0x540938 and their eight word
// transforms. It never executes instructions; originals remain unchanged.
const assert=require('node:assert/strict');
const {image,disassemble}=require('./source_loader_analysis.cjs');
const rotate=(v,n)=>((v>>>n)|(v<<(32-n)))>>>0;
const permute=v=>(((v<<8)&0xff00)|((v>>>8)&0xff0000)|((v>>>16)&255)|((v<<16)&0xff000000))>>>0;
const transforms=[v=>v^0x09f8ed17,v=>v^0xa95128c3,v=>rotate(v,13),v=>rotate(v,8),permute,
  v=>rotate(v^0x09f8ed17,13),v=>rotate(permute(v)^0xa95128c3,8),v=>permute(rotate(rotate(v^0x09f8ed17,8),13))];
function untransform(iso) {
  const img=image(iso,'OVERLAY/REL/DNAS.BIN');
  img.bytes=Buffer.from(img.bytes); // do not mutate original read buffer either
  const read=a=>img.bytes.readUInt32LE(img.offset(a));
  const table=0x540a10,count=read(table); assert.equal(count,30,'only audited overlay build');
  const records=new Map();
  for(let i=0;i<count;i++) {
    const id=read(table+4+i*8),at=table+4+count*8+read(table+8+i*8);
    const relativeStart=read(at),n=read(at+4); assert(n<=256);
    records.set(id,{relativeStart,skip:new Set(Array.from({length:n},(_,j)=>read(at+8+4*j)))});
  }
  const blocks=[];
  // Header references are matched to the verified dispatcher table, then all
  // range invariants checked. Re-encryption descriptors (odd ids) are ignored.
  for(let p=0;p+20<img.bytes.length;p+=4) {
    const id=img.bytes.readUInt32LE(p+8);
    let record=records.get(id);
    // id=0 explicitly selects no relocation skips in 0x541378. Match the
    // complete forward stub (branch over 32-byte prefix +20-byte descriptor),
    // not arbitrary zero-looking data. A zero-length block is legal there.
    if(id===0 && p>=32 && img.bytes.readUInt32LE(p-32)===0x1000000c && img.bytes.readUInt32LE(p+16)===0)
      record={relativeStart:0,skip:new Set()};
    if(!record || id&1 || img.bytes.readUInt32LE(p)!==0)continue;
    const seed=img.bytes.readUInt32LE(p+4),length=(seed^img.bytes.readUInt32LE(p+12))>>>0;
    assert(length<=65536 && length%4===0 && p+20+length<=img.bytes.length,'bounded code block');
    const start=0x4c5380+p+20;
    const ops=[],n=((seed>>>28)&7)||5;
    for(let j=0;j<n;j++)ops.push((seed>>>(j*4))&7);
    let changed=0;
    for(let delta=0;delta<length;delta+=4) {
      if(record.skip.has(record.relativeStart+delta))continue;
      const at=p+20+delta;let word=img.bytes.readUInt32LE(at);
      for(const op of ops)word=transforms[op](word)>>>0;
      img.bytes.writeUInt32LE(word,at);changed++;
    }
    blocks.push({descriptor:'0x'+(start-20).toString(16),start:'0x'+start.toString(16),length,id:'0x'+id.toString(16),seed:'0x'+seed.toString(16),operations:ops,transformedWords:changed,skippedWords:record.skip.size});
  }
  assert.equal(blocks.filter(b=>b.id!=='0x0').length,30,'all thirty table-backed forward descriptors found exactly once');
  return{img,blocks};
}
if(require.main===module){const[iso,range]=process.argv.slice(2);const result=untransform(iso);if(range){const[start,end]=range.split(':').map(x=>parseInt(x,16));for(const r of disassemble(result.img,start,end))console.log(`${r.pc} ${r.word.padEnd(10)} ${r.assembly}`);}else console.log(JSON.stringify(result.blocks,null,2));}
module.exports={untransform,transforms,rotate,permute};
