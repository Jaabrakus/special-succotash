'use strict';
// Offline original-instruction execution. No cache hooks or unknown-call stubs.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {image, disassemble} = require('./source_loader_analysis.cjs');
const {untransform} = require('./source_overlay_untransform.cjs');
const {DecoderMachine} = require('./source_mips_decoder_harness.cjs');
const hash = b => crypto.createHash('sha256').update(b).digest('hex');
const hex = n => '0x' + (n >>> 0).toString(16);
const BASE = 0x4c5380, STACK = 0x1ff0000, STACK_BYTES = 0x10000;
const INNER = {name:'inner', table:0x539e78, count:18, lookup:0x53a430, transform:0x53acb8,
  missingIds:[0xa810ccf2,0xa810ce56,0xa810cf22,0xa810cfd4,0xa810d084]};
const OUTER = {name:'outer', table:0x540a10, count:30, lookup:0x541378, transform:0x540938};

function descriptors(img, spec) {
  const read = a => img.bytes.readUInt32LE(img.offset(a));
  assert.equal(read(spec.table), spec.count, 'audited table count');
  const ids = new Set();
  for(let i=0;i<spec.count;i++) {
    const id=read(spec.table+4+i*8); assert(id>0 && !(id&1), 'forward table ID');
    assert(!ids.has(id), 'duplicate table ID'); ids.add(id);
  }
  const rows=[];
  for(let p=0;p+20<=img.bytes.length;p+=4) {
    const id=img.bytes.readUInt32LE(p+8);
    if(!ids.has(id) || img.bytes.readUInt32LE(p)!==0 || p<32 ||
      img.bytes.readUInt32LE(p-32)!==0x1000000c || img.bytes.readUInt32LE(p-28)!==0) continue;
    const seed=img.bytes.readUInt32LE(p+4), length=(seed^img.bytes.readUInt32LE(p+12))>>>0;
    assert(length<=65536 && length%4===0 && p+20+length<=img.bytes.length, 'bounded descriptor');
    rows.push({descriptor:hex(BASE+p), start:hex(BASE+p+20), length, id:hex(id), seed:hex(seed)});
  }
  assert.equal(new Set(rows.map(r=>r.id)).size,rows.length,'one descriptor per ID');
  const missing=[...ids].filter(id=>!rows.some(r=>Number(r.id)===id));
  assert.deepEqual(missing,spec.missingIds||[],'only explicitly reported absent descriptors');
  assert.equal(rows.length+missing.length,spec.count,'table descriptor accounting');
  return rows;
}

function executeBlock(input, row, spec) {
  const start=Number(row.start), end=start+row.length, id=Number(row.id), seed=Number(row.seed);
  const m = new DecoderMachine({maxSteps:10_000_000});
  const mapped=m.map(BASE,input,{name:'original overlay copy',write:true,execute:true});
  m.map(STACK,Buffer.alloc(STACK_BYTES),{name:'synthetic stack',write:true});
  const store=m.store.bind(m);
  m.store=(address,size,value)=>{
    assert((address>=start && address+size<=end) ||
      (address>=STACK && address+size<=STACK+STACK_BYTES), 'write outside current body/stack');
    store(address,size,value);
  };
  const lookup=m.run(spec.lookup,{args:[id>>>1,STACK,STACK+4,STACK+8],stackPointer:STACK+STACK_BYTES-256});
  const relativeStart=Number(m.load(STACK,4)), count=Number(m.load(STACK+4,4)), pointer=Number(m.load(STACK+8,4));
  assert(count<=256, 'bounded skip count');
  if(count)m.region(pointer,count*4,'read');
  if(id===0)assert.equal(relativeStart+count+pointer,0,'ID zero has no relocation skips');
  const result=m.run(spec.transform,{args:[start,end,(start-relativeStart)>>>0,seed,count,pointer],stackPointer:STACK+STACK_BYTES-256});
  assert.equal(result.value,0n,'original transform return');
  const p=start-BASE;
  assert.deepEqual(mapped.subarray(0,p),input.subarray(0,p),'prefix unchanged');
  assert.deepEqual(mapped.subarray(p+row.length),input.subarray(p+row.length),'suffix unchanged');
  return {bytes:mapped, report:{...row,lookup:hex(spec.lookup),transform:hex(spec.transform),
    relative_start:hex(relativeStart),skip_count:count,skip_pointer:hex(pointer),
    lookup_steps:lookup.steps,transform_steps:result.steps,writes:result.writes,
    input_body_sha256:hash(input.subarray(p,p+row.length)),output_body_sha256:hash(mapped.subarray(p,p+row.length))}};
}

function innerUntransform(iso) {
  const img=image(iso,'OVERLAY/REL/DNAS.BIN');
  assert.equal(Number(img.segments[0].virtual_address),BASE,'audited overlay load address');
  const original=Buffer.from(img.bytes), rows=descriptors(img,INNER), reports=[];
  let decoded=Buffer.from(original);
  for(const row of rows){const r=executeBlock(original,row,INNER);const p=Number(row.start)-BASE;
    r.bytes.copy(decoded,p,p,p+row.length);reports.push(r.report);}
  assert.equal(hash(img.bytes),hash(original),'source buffer unchanged');
  img.bytes=decoded;
  return {img,blocks:reports,missing_descriptor_ids:INNER.missingIds.map(hex),
    input_sha256:hash(original),output_sha256:hash(decoded)};
}

function differential(iso) {
  const original=image(iso,'OVERLAY/REL/DNAS.BIN'), expected=untransform(iso), reports=[];
  let decoded=Buffer.from(original.bytes);
  for(const row of expected.blocks){const r=executeBlock(original.bytes,row,OUTER);const p=Number(row.start)-BASE;
    assert.deepEqual(r.bytes.subarray(p,p+row.length),expected.img.bytes.subarray(p,p+row.length),'outer block mismatch '+row.descriptor);
    r.bytes.copy(decoded,p,p,p+row.length);reports.push(r.report);}
  assert.deepEqual(decoded,expected.img.bytes,'full outer decoded image matches static translation');
  return {blocks:reports,input_sha256:hash(original.bytes),output_sha256:hash(decoded),matched:true};
}

if(require.main===module) {
  const [iso,mode='--inner',destination]=process.argv.slice(2);
  assert(iso && ['--inner','--outer','--both'].includes(mode),'usage: ISO [--inner|--outer|--both] [NEW_REPORT.json]');
  const report={version:1,observer_only:true,no_stubs:true,original_inputs_unchanged:true};
  if(mode!=='--inner')report.outer=differential(iso);
  if(mode!=='--outer'){const r=innerUntransform(iso);report.inner={...r,img:undefined};
    report.inner.key_getter_disassembly=disassemble(r.img,0x53c648,0x53c7a0);}
  if(destination){assert(path.isAbsolute(destination) && path.resolve(destination).startsWith('/private/tmp/'),
    'reports restricted to explicit temporary file');fs.writeFileSync(destination,JSON.stringify(report,null,2)+'\n',{flag:'wx'});}
  console.log(JSON.stringify({status:'PASS',outer_blocks:report.outer?.blocks.length,inner_blocks:report.inner?.blocks.length,report:destination||null}));
}
module.exports={innerUntransform,differential,executeBlock,descriptors,INNER,OUTER};
