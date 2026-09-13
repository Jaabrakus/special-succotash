'use strict';
// Original bounded instructions, synthetic state only. No runtime changes.
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {image,disassemble}=require('./source_loader_analysis.cjs');
const {moduleImage,disasm}=require('./source_fire_spread_analysis.cjs');
const {CrossFixtureMachine,equation}=require('./source_fire_direction_analysis.cjs');
const {isoFile,reader:readReader,pairs}=require('./socom2_weapon_reference.cjs');
const {archive}=require('./socom_geometry/archive.cjs');
const ROOT=path.resolve(__dirname,'..'),MASK=(1n<<64n)-1n,MULT=0x5851f42d4c957f2dn;
const GLOBAL=0x1cc750,CONTEXT=0x1cc460,STACK=0x10000000,SP=STACK+0x8000;
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const hex=n=>'0x'+n.toString(16);

function next(state){
  assert(typeof state==='bigint'&&state>=0n&&state<=MASK,'unsigned 64-bit state');
  const advanced=(state*MULT+1n)&MASK;
  return{state:advanced,draw:Number((advanced>>32n)&0x7fffffffn)};
}

class RngFixtureMachine extends CrossFixtureMachine {
  constructor(){super();this.hi1=0n;this.lo1=0n;this.rngCalls=0;}
  step(){
    const pc=this.pc,w=Number(this.load(pc,4,false,'execute'));
    if(pc===0x197740)this.rngCalls++;
    if(w>>>26!==28)return super.step();
    // The only new opcode is exact original MULT1 a0,a0,v0 in __muldi3.
    assert(pc===0x19eb4c&&w===0x70822018,'unsupported MMI outside exact multiply helper');
    assert(this.steps<this.maxSteps,'instruction step cap');
    const product=this.s32(4)*this.s32(2);
    this.lo1=BigInt.asUintN(64,BigInt.asIntN(32,product));
    this.hi1=BigInt.asUintN(64,BigInt.asIntN(32,product>>32n));
    this.set64(4,this.lo1);
    const pending=this.nextPC;this.pc=pending;this.nextPC=(pending+4)>>>0;
    this.inDelaySlot=false;this.steps++;this.lastPCs.push(pc);
    if(this.lastPCs.length>16)this.lastPCs.shift();
  }
}

function machine(boot){
  const m=new RngFixtureMachine();
  for(const[start,end]of[[0x197728,0x1977a4],[0x19eb18,0x19eb8c],[0x1bfc78,0x1bfc94]])
    m.map(start,boot.bytes.subarray(boot.offset(start),boot.offset(end-4)+4),{execute:true,name:'original boot slice'});
  const pointer=Buffer.alloc(4);pointer.writeUInt32LE(CONTEXT);
  m.map(GLOBAL,pointer,{name:'fixture context pointer matching source static value'});
  const context=m.map(CONTEXT,Buffer.alloc(256),{write:true,name:'synthetic RNG context'});
  m.map(STACK,Buffer.alloc(65536),{write:true,name:'synthetic stack'});
  return{m,context};
}

function runRng(boot){
  const seeds=[0n,1n,2n,0x12345678n,0x7fffffffn,0x80000000n,0xffffffffn,0x123456789abcdef0n,MASK];
  const rows=[];let checks=0;
  for(const seed of seeds){
    const{m,context}=machine(boot);
    m.run(0x197728,{args:[seed],stackPointer:SP});
    let state=seed&0xffffffffn;
    assert.equal(context.readBigUInt64LE(168),state,'source seed zero-extends low32');checks++;
    const sequence=[];
    for(let index=0;index<128;index++){
      const expected=next(state),result=m.run(0x197740,{stackPointer:SP});
      assert.equal(result.value,BigInt(expected.draw),'original RNG output');
      assert.equal(context.readBigUInt64LE(168),expected.state,'original RNG stored state');checks+=2;
      state=expected.state;
      if(index<8)sequence.push({index,state:hex(state),draw:expected.draw,steps:result.steps});
    }
    assert.equal(m.rngCalls,128);
    rows.push({seed:hex(seed),seeded_state:hex(seed&0xffffffffn),sequence,checked_draws:128});
  }
  // Test true 64-bit initial states too, not only the 32-bit seeding API.
  for(const state of[0n,1n,0x8000000000000000n,0x7fffffffffffffffn,0x123456789abcdef0n,MASK]){
    const{m,context}=machine(boot);context.writeBigUInt64LE(state,168);
    const expected=next(state),actual=m.run(0x197740,{stackPointer:SP});
    assert.equal(actual.value,BigInt(expected.draw));assert.equal(context.readBigUInt64LE(168),expected.state);checks+=2;
  }
  return{checks,sequences:rows};
}

function runWholeDirection(boot,core,seal){
  const rows=[];
  for(const seed of[0,1,0x12345678,0xffffffff])for(const direction of[[0,0,-1],[0,Math.fround(.6),Math.fround(-.8)]]){
    const{m,context}=machine(boot),BASE=0x11000000;
    m.map(core.base,core.bytes,{execute:true,name:'original core'});
    m.map(seal.base,seal.bytes,{execute:true,name:'original seal'});
    const records=m.map(BASE,Buffer.alloc(4096),{write:true,name:'synthetic actor direction inputs'});
    records.writeUInt32LE(BASE+256,4);
    const accuracy=[0,0,Math.fround(.1)];accuracy.forEach((v,i)=>records.writeFloatLE(v,256+1492+4*i));
    m.run(0x197728,{args:[seed],stackPointer:SP});
    let state=BigInt(seed);
    for(let pellet=0;pellet<4;pellet++){
      direction.forEach((v,i)=>records.writeFloatLE(v,32+4*i));
      const first=next(state),second=next(first.state);state=second.state;
      const expected=equation({direction,raw:[first.draw,second.draw],accuracy});
      const before=m.rngCalls,result=m.run(0x592260,{args:[BASE,BASE+32],stackPointer:SP});
      const actual=[0,1,2].map(i=>records.readFloatLE(32+4*i));
      assert.deepEqual(actual,expected.raw_direction,'whole original direction including RNG');
      assert.equal(m.rngCalls-before,2,'two original draws per direction');
      assert.equal(context.readBigUInt64LE(168),state,'exact consumed RNG state');
      rows.push({seed,pellet,direction,accuracy,raw:[first.draw,second.draw],state_after:hex(state),
        output:actual,steps:result.steps});
    }
  }
  return rows;
}

function audit(iso){
  const boot=image(iso),core=moduleImage('FTSCore.bin'),seal=moduleImage('ZSealEtc.bin');
  assert.equal(hash(boot.bytes),'0172dc0bec19c83d1fe2d0fec0a290f41cc5d32efa14ed6859ca92773c05346c','audited boot hash');
  assert.equal(boot.bytes.readUInt32LE(boot.offset(GLOBAL)),CONTEXT,'static context pointer');
  assert.equal(boot.bytes.readBigUInt64LE(boot.offset(CONTEXT+168)),1n,'static initial seed');
  for(const[pc,word]of[[0x5bf4a8,0x0c0f5138],[0x5bf4e0,0x0071082a],[0x5bf540,0x0320f809],
    [0x5bf55c,0x0320f809],[0x5bf594,0x0c1714d0],[0x5bf854,0x24630001],[0x5bf860,0x0071182a],
    [0x5bf864,0x1460ff24],[0x5c6318,0x0320f809],[0x5c63ec,0x0320f809]])
    assert.equal(seal.bytes.readUInt32LE(seal.offset(pc)),word,'projectile loop anchor '+hex(pc));
  assert.equal(core.bytes.readUInt32LE(core.offset(0x3d44e4)),0x8c820020,'ammo count getter');
  assert.equal(core.bytes.readUInt32LE(core.offset(0x3d44f4)),0xac850020,'ammo count setter');
  const readerPath=path.join(ROOT,'art_source/socom2_ballistics_reference_20260912/weapon_reader_full.json');
  const reader=JSON.parse(fs.readFileSync(readerPath,'utf8'));
  const zar=isoFile(iso,['RUN','ZWEAPON.ZAR']);
  const entry=archive(zar).entries.find(e=>e.name==='zweapon.rdr');assert(entry,'original weapon reader');
  const rdr=zar.subarray(entry.offset,entry.offset+entry.size),decoded=pairs(readReader(rdr));
  assert.equal(hash(zar),reader.source.archive_sha256,'ISO original archive matches audit');
  assert.equal(hash(rdr),reader.source.reader_sha256,'ISO reader matches audit');
  assert.deepEqual(decoded.ZAMMO,reader.ammunition.map(r=>r.raw_row),'all source ammo rows identical');
  const explicit=reader.ammunition.filter(r=>r.fields.some(f=>f.tag==='NumProjectilesFired'))
    .map(r=>({name:r.name,index:r.index,count:r.fields.find(f=>f.tag==='NumProjectilesFired').values[0]}));
  assert.deepEqual(explicit,[{name:'12 Gauge',index:12,count:4}]);
  const rng=runRng(boot),direction=runWholeDirection(boot,core,seal);
  assert.throws(()=>next(-1n),/unsigned/);assert.throws(()=>next(1),/unsigned/);assert.throws(()=>next(1n<<64n),/unsigned/);
  const invalid=new RngFixtureMachine(),invalidCode=Buffer.alloc(4);invalidCode.writeUInt32LE(0x70822018);
  invalid.map(0x1000,invalidCode,{execute:true});assert.throws(()=>invalid.run(0x1000),/unsupported MMI/);
  return{schema_version:1,status:'PASS',scope:'original RNG and whole direction function; pellet dispatch loop static anchors, not whole game execution',
    external_stubs:0,rng_checks:rng.checks,whole_direction_vectors:direction.length,
    source:[{name:boot.boot,sha256:hash(boot.bytes)},... [core,seal].map(m=>({name:m.name,sha256:hash(m.bytes)}))],
    algorithm:{state_bits:64,multiplier:hex(MULT),increment:1,return:'(state >> 32) & 0x7fffffff',
      seed:'low32 unsigned, stored in64bits',context_pointer:hex(GLOBAL),state_offset:168,static_initial_state:1},
    rng_vectors:rng.sequences,direction_vectors:direction,projectile_count:{default:1,explicit},
    source_ranges:{seed:disassemble(boot,0x197728,0x197740),rng:disassemble(boot,0x197740,0x1977a4),
      multiply:disassemble(boot,0x19eb18,0x19eb8c),seed_caller:disasm(core,0x34fd80,0x34fdf0),
      count_reader:disasm(core,0x3ceff8,0x3cf02c),count_accessors:disasm(core,0x3d44e0,0x3d4500),
      loop_entry:disasm(seal,0x5bf4a0,0x5bf5a8),loop_tail:disasm(seal,0x5bf850,0x5bf870),
      dispatch:disasm(seal,0x5c62c8,0x5c63f4)},
    limitations:['Synthetic initial state; original time/input/global RNG consumption schedule not reproduced',
      'Whole direction runs use fixed cached accuracy fields and finite-normal float32 observer domain',
      'Four direction calls mirror proven loop count but do not execute full weapon allocation/damage fire loop',
      'Do not label deterministic per-shot seed resetting equivalent to original continuous global/context stream']};
}

if(require.main===module){
  const[iso,output]=process.argv.slice(2);assert(iso,'ISO path required');const result=audit(iso);
  if(output){const p=path.resolve(output);assert(path.isAbsolute(output)&&(p.startsWith('/private/tmp/')||p===path.join(ROOT,'config/reference/socom2_fire_rng_vectors.json')),'new temporary/reference output only');
    fs.writeFileSync(p,JSON.stringify(result,null,2)+'\n',{flag:'wx'});}
  console.log('SOURCE_FIRE_RNG_AUDIT PASS rng_checks='+result.rng_checks+' whole_direction_vectors='+result.whole_direction_vectors+' external_stubs=0');
}
module.exports={next,audit,RngFixtureMachine};
