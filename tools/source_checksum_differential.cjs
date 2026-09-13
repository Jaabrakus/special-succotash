'use strict';
// Execute only the original SHA-1 routine and its two pure helpers.
const assert=require('node:assert/strict');
const crypto=require('node:crypto');
const {image}=require('./source_loader_analysis.cjs');
const {DecoderMachine}=require('./source_mips_decoder_harness.cjs');
const {sourceSha1}=require('./source_payload_decode.cjs');
function check(iso){
  const img=image(iso,'OVERLAY/REL/DNAS.BIN'),rows=[];
  for(const length of [0,1,16,47,48,49,55,56,63,64,80,111,112,113,119,120,128,256]){
    const data=Buffer.from(Array.from({length},(_,i)=>(i*37+11)&255));
    const m=new DecoderMachine({maxSteps:100_000});
    m.map(0x4c5380,img.bytes,{execute:true,name:'original DNAS code/data'});
    m.map(0x1000000,data.length?data:Buffer.alloc(1),{name:'input'});
    const out=m.map(0x1001000,Buffer.alloc(20),{write:true,name:'digest'});
    m.map(0x1100000,Buffer.alloc(65536),{write:true,name:'stack'});
    const r=m.run(0x53f278,{args:[0x1000000,length,0x1001000,length,5],stackPointer:0x110fff0});
    assert(out.equals(sourceSha1(data)),`original digest length ${length}`);
    const standard=crypto.createHash('sha1').update(data).digest();
    assert.equal(out.equals(standard),!(length%64>=48&&length%64<56),'source nonstandard tail behavior');
    rows.push({length,steps:r.steps,originalEqualsTranslation:true,equalsStandardSha1:out.equals(standard)});
  }
  return{status:'PASS',entry:'0x53f278',helpers:['0x53ebb8','0x53ebf8'],syscallsOrStubs:0,rows};
}
if(require.main===module){assert(process.argv[2],'usage: local.iso');console.log(JSON.stringify(check(process.argv[2]),null,2));}
module.exports={check};
