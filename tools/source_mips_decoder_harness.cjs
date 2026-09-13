'use strict';
// Offline, integer-only, fail-closed decoder research. Not a PS2 emulator.
const assert = require('node:assert/strict');
const U32 = 0xffffffffn, U64 = 0xffffffffffffffffn;
const hex = v => '0x' + Number(v).toString(16);
class DecoderMachine {
  constructor({maxSteps = 2_000_000, maxMappedBytes = 64 * 1024 * 1024} = {}) {
    assert(Number.isSafeInteger(maxSteps) && maxSteps > 0 && maxSteps <= 100_000_000);
    assert(Number.isSafeInteger(maxMappedBytes) && maxMappedBytes > 0 && maxMappedBytes <= 128 * 1024 * 1024);
    this.maxSteps = maxSteps; this.maxMappedBytes = maxMappedBytes;
    this.reg = Array(32).fill(0n); this.hi = 0n; this.lo = 0n;
    this.regions = []; this.steps = 0; this.writes = 0; this.lastPCs = [];
  }
  map(start, bytes, {name = 'region', read = true, write = false, execute = false} = {}) {
    assert(Buffer.isBuffer(bytes) && bytes.length > 0);
    assert(Number.isSafeInteger(start) && start >= 0 && start + bytes.length <= 0x100000000);
    assert(!this.regions.some(r => start < r.end && start + bytes.length > r.start), 'overlapping mapping');
    assert(this.regions.reduce((n,r) => n+r.bytes.length,bytes.length) <= this.maxMappedBytes, 'mapping cap');
    const region = {start, end:start+bytes.length, bytes:Buffer.from(bytes), name, read, write, execute};
    this.regions.push(region); return region.bytes;
  }
  region(address, size, permission) {
    assert(Number.isSafeInteger(address) && address >= 0 && address + size <= 0x100000000, 'address bounds');
    const r = this.regions.find(r => address >= r.start && address + size <= r.end && r[permission]);
    assert(r, `${permission} denied at ${hex(address)} size ${size}`); return r;
  }
  load(address, size, signed = false, permission = 'read') {
    const r = this.region(address,size,permission); let value = 0n;
    for(let i=size-1;i>=0;i--) value = (value<<8n)|BigInt(r.bytes[address-r.start+i]);
    return signed ? BigInt.asIntN(size*8,value) : value;
  }
  store(address, size, value) {
    const r = this.region(address,size,'write'); value = BigInt.asUintN(size*8,value);
    for(let i=0;i<size;i++){r.bytes[address-r.start+i]=Number(value&255n);value>>=8n;} this.writes++;
  }
  u(i){return this.reg[i]&U64;}
  s(i){return BigInt.asIntN(64,this.u(i));}
  u32(i){return this.reg[i]&U32;}
  s32(i){return BigInt.asIntN(32,this.u32(i));}
  set64(i,value){if(i)this.reg[i]=(this.reg[i]&~U64)|BigInt.asUintN(64,value);}
  set32(i,value){this.set64(i,BigInt.asIntN(32,value));}
  set128(i,value){if(i)this.reg[i]=BigInt.asUintN(128,value);}
  address(rs,imm){return Number(BigInt.asUintN(32,this.u(rs)+BigInt(imm)));}
  aligned(address,size){assert(address%size===0, `unaligned ${size}-byte access at ${hex(address)}`);return address;}
  mergeLoad(rt,address,size,left){
    const off=address%size, base=address-off, bits=BigInt(size*8), all=(1n<<bits)-1n;
    const word=this.load(base,size), old=this.reg[rt]&all;
    const shift=BigInt(left?(size-1-off)*8:off*8);
    const mask=left?all^((1n<<shift)-1n):all>>shift;
    const value=(old&~mask)|((left?word<<shift:word>>shift)&mask);
    if(size===4)this.set32(rt,value);else this.set64(rt,value);
  }
  mergeStore(rt,address,size,left){
    // Partial stores check/write only the architecturally touched bytes.
    const off=address%size, base=address-off;
    const count=left?off+1:size-off, start=left?base:address;
    const value=left?this.reg[rt]>>BigInt((size-count)*8):this.reg[rt];
    this.store(start,count,value);
  }
  step(){
    assert(this.steps<this.maxSteps,'instruction step cap');
    const pc=this.pc,w=Number(this.load(this.aligned(pc,4),4,false,'execute'));
    const op=w>>>26,rs=(w>>>21)&31,rt=(w>>>16)&31,rd=(w>>>11)&31,sa=(w>>>6)&31,fn=w&63;
    const imm=(w<<16)>>16,uimm=w&65535;
    const control=op===1||op===2||op===3||[4,5,6,7,20,21,22,23].includes(op)||(op===0&&(fn===8||fn===9));
    assert(!(this.inDelaySlot&&control),'control transfer in a delay slot is unsupported');
    this.inDelaySlot=control;
    const delayPC=this.nextPC;this.pc=delayPC;this.nextPC=(delayPC+4)>>>0;
    this.steps++;this.lastPCs.push(pc);if(this.lastPCs.length>16)this.lastPCs.shift();
    const branch=(condition,likely=false)=>{if(condition)this.nextPC=(pc+4+imm*4)>>>0;else if(likely){this.pc=this.nextPC;this.nextPC=(this.nextPC+4)>>>0;this.inDelaySlot=false;}};
    const addr=()=>this.address(rs,imm);
    const unsupported=()=>{throw Error(`unsupported opcode ${hex(w)} at ${hex(pc)}`);};
    if(op===0){
      if([0,2,3,56,58,59,60,62,63].includes(fn))assert(rs===0,'reserved shift encoding');
      if([4,6,7,10,11,20,22,23,24,25,33,35,36,37,38,39,42,43,45,47].includes(fn))assert(sa===0,'reserved ALU encoding');
      if(fn===8)assert(rt===0&&rd===0&&sa===0,'reserved JR encoding');
      if(fn===9)assert(rt===0&&sa===0,'reserved JALR encoding');
      if(fn===16||fn===18)assert(rs===0&&rt===0&&sa===0,'reserved MF encoding');
      if(fn===17||fn===19)assert(rt===0&&rd===0&&sa===0,'reserved MT encoding');
      if(fn===26||fn===27)assert(rd===0&&sa===0,'reserved DIV encoding');
      switch(fn){
        case 0:this.set32(rd,this.u32(rt)<<BigInt(sa));return;
        case 2:this.set32(rd,this.u32(rt)>>BigInt(sa));return;
        case 3:this.set32(rd,this.s32(rt)>>BigInt(sa));return;
        case 4:this.set32(rd,this.u32(rt)<<BigInt(Number(this.u32(rs)&31n)));return;
        case 6:this.set32(rd,this.u32(rt)>>BigInt(Number(this.u32(rs)&31n)));return;
        case 7:this.set32(rd,this.s32(rt)>>BigInt(Number(this.u32(rs)&31n)));return;
        case 8:this.nextPC=Number(this.u32(rs));return;
        case 9:{const target=Number(this.u32(rs));this.set64(rd,BigInt(pc+8));this.nextPC=target;return;}
        case 10:if(this.u(rt)===0n)this.set64(rd,this.u(rs));return;
        case 11:if(this.u(rt)!==0n)this.set64(rd,this.u(rs));return;
        case 16:this.set64(rd,this.hi);return;
        case 17:this.hi=this.u(rs);return;
        case 18:this.set64(rd,this.lo);return;
        case 19:this.lo=this.u(rs);return;
        case 20:this.set64(rd,this.u(rt)<<(this.u(rs)&63n));return;
        case 22:this.set64(rd,this.u(rt)>>(this.u(rs)&63n));return;
        case 23:this.set64(rd,this.s(rt)>>(this.u(rs)&63n));return;
        case 24:case 25:{const p=fn===24?this.s32(rs)*this.s32(rt):this.u32(rs)*this.u32(rt);this.lo=BigInt.asUintN(64,BigInt.asIntN(32,p));this.hi=BigInt.asUintN(64,BigInt.asIntN(32,p>>32n));this.set64(rd,this.lo);return;}
        case 26:case 27:{const a=fn===26?this.s32(rs):this.u32(rs),b=fn===26?this.s32(rt):this.u32(rt);assert(b!==0n,'division by zero not supported');this.lo=BigInt.asUintN(64,BigInt.asIntN(32,a/b));this.hi=BigInt.asUintN(64,BigInt.asIntN(32,a%b));return;}
        case 33:this.set32(rd,this.u32(rs)+this.u32(rt));return;
        case 35:this.set32(rd,this.u32(rs)-this.u32(rt));return;
        case 36:this.set64(rd,this.u(rs)&this.u(rt));return;
        case 37:this.set64(rd,this.u(rs)|this.u(rt));return;
        case 38:this.set64(rd,this.u(rs)^this.u(rt));return;
        case 39:this.set64(rd,~(this.u(rs)|this.u(rt)));return;
        case 42:this.set64(rd,this.s(rs)<this.s(rt)?1n:0n);return;
        case 43:this.set64(rd,this.u(rs)<this.u(rt)?1n:0n);return;
        case 45:this.set64(rd,this.u(rs)+this.u(rt));return;
        case 47:this.set64(rd,this.u(rs)-this.u(rt));return;
        case 56:this.set64(rd,this.u(rt)<<BigInt(sa));return;
        case 58:this.set64(rd,this.u(rt)>>BigInt(sa));return;
        case 59:this.set64(rd,this.s(rt)>>BigInt(sa));return;
        case 60:this.set64(rd,this.u(rt)<<BigInt(sa+32));return;
        case 62:this.set64(rd,this.u(rt)>>BigInt(sa+32));return;
        case 63:this.set64(rd,this.s(rt)>>BigInt(sa+32));return;
        default:unsupported();
      }
    }
    switch(op){
      case 1:{const c=this.s(rs)<0n;if(rt===0||rt===2)branch(c,rt===2);else if(rt===1||rt===3)branch(!c,rt===3);else unsupported();return;}
      case 2:case 3:if(op===3)this.set64(31,BigInt(pc+8));this.nextPC=(((pc+4)&0xf0000000)|((w&0x3ffffff)<<2))>>>0;return;
      case 4:case 20:branch(this.u(rs)===this.u(rt),op===20);return;
      case 5:case 21:branch(this.u(rs)!==this.u(rt),op===21);return;
      case 6:case 22:assert(rt===0,'invalid blez rt');branch(this.s(rs)<=0n,op===22);return;
      case 7:case 23:assert(rt===0,'invalid bgtz rt');branch(this.s(rs)>0n,op===23);return;
      case 9:this.set32(rt,this.u(rs)+BigInt(imm));return;
      case 10:this.set64(rt,this.s(rs)<BigInt(imm)?1n:0n);return;
      case 11:this.set64(rt,this.u(rs)<BigInt.asUintN(64,BigInt(imm))?1n:0n);return;
      case 12:this.set64(rt,this.u(rs)&BigInt(uimm));return;
      case 13:this.set64(rt,this.u(rs)|BigInt(uimm));return;
      case 14:this.set64(rt,this.u(rs)^BigInt(uimm));return;
      case 15:assert(rs===0,'invalid lui rs');this.set32(rt,BigInt(uimm)<<16n);return;
      case 25:this.set64(rt,this.u(rs)+BigInt(imm));return;
      case 26:this.mergeLoad(rt,addr(),8,true);return;
      case 27:this.mergeLoad(rt,addr(),8,false);return;
      case 30:this.set128(rt,this.load(this.aligned(addr(),16),16));return;
      case 31:this.store(this.aligned(addr(),16),16,this.reg[rt]);return;
      case 32:this.set64(rt,this.load(addr(),1,true));return;
      case 33:this.set64(rt,this.load(this.aligned(addr(),2),2,true));return;
      case 34:this.mergeLoad(rt,addr(),4,true);return;
      case 35:this.set64(rt,this.load(this.aligned(addr(),4),4,true));return;
      case 36:this.set64(rt,this.load(addr(),1));return;
      case 37:this.set64(rt,this.load(this.aligned(addr(),2),2));return;
      case 38:this.mergeLoad(rt,addr(),4,false);return;
      case 39:this.set64(rt,this.load(this.aligned(addr(),4),4));return;
      case 40:this.store(addr(),1,this.u(rt));return;
      case 41:this.store(this.aligned(addr(),2),2,this.u(rt));return;
      case 42:this.mergeStore(rt,addr(),4,true);return;
      case 43:this.store(this.aligned(addr(),4),4,this.u(rt));return;
      case 44:this.mergeStore(rt,addr(),8,true);return;
      case 45:this.mergeStore(rt,addr(),8,false);return;
      case 46:this.mergeStore(rt,addr(),4,false);return;
      case 55:this.set64(rt,this.load(this.aligned(addr(),8),8));return;
      case 63:this.store(this.aligned(addr(),8),8,this.u(rt));return;
      default:unsupported();
    }
  }
  run(entry,{returnAddress=0xfffffff0,args=[],stackPointer}={}){
    assert(Number.isSafeInteger(entry)&&entry%4===0);
    assert(Number.isSafeInteger(returnAddress)&&returnAddress%4===0&&returnAddress>=0&&returnAddress<=0xfffffffc);
    assert(!this.regions.some(r=>returnAddress>=r.start&&returnAddress<r.end),'return sentinel must not be mapped');
    assert(args.length<=8);args.forEach((a,i)=>this.set64(4+i,BigInt(a)));
    if(stackPointer!==undefined)this.set64(29,BigInt(stackPointer));this.set64(31,BigInt(returnAddress));
    this.pc=entry;this.nextPC=(entry+4)>>>0;this.steps=0;this.writes=0;this.lastPCs=[];this.inDelaySlot=false;
    try{while(this.pc!==returnAddress)this.step();}
    catch(e){e.message+=` [steps=${this.steps}; pc=${hex(this.pc)}; recent=${this.lastPCs.map(hex).join(',')}]`;throw e;}
    assert(this.reg[0]===0n);return {value:this.u(2),steps:this.steps,writes:this.writes};
  }
}
const I=(op,rs,rt,imm)=>((op<<26)|(rs<<21)|(rt<<16)|(imm&65535))>>>0;
const R=(rs,rt,rd,sa,fn)=>((rs<<21)|(rt<<16)|(rd<<11)|(sa<<6)|fn)>>>0;
function code(words){const b=Buffer.alloc(words.length*4);words.forEach((w,i)=>b.writeUInt32LE(w>>>0,i*4));return b;}
function selfTest(){
  const fixture=(words,options={})=>{const m=new DecoderMachine(options);m.map(0x1000,code(words),{execute:true});return m;};
  let m=fixture([I(9,0,2,1),R(31,0,0,0,8),I(9,2,2,2)]);assert.equal(m.run(0x1000).value,3n);
  m=fixture([I(9,0,2,1),I(20,0,2,1),I(9,2,2,99),R(31,0,0,0,8),0]);assert.equal(m.run(0x1000).value,1n);
  m=fixture([R(31,0,16,0,37),(3<<26)|(0x1020>>>2),I(9,0,2,2),R(16,0,0,0,8),I(9,2,2,8),0,0,0,I(9,2,2,4),R(31,0,0,0,8),I(9,2,2,16)]);assert.equal(m.run(0x1000).value,30n);
  m=fixture([I(15,0,2,0x8000),R(31,0,0,0,8),0]);assert.equal(m.run(0x1000).value,0xffffffff80000000n);
  m=fixture([I(35,4,2,0),I(43,5,2,0),R(31,0,0,0,8),0]);m.map(0x2000,Buffer.from([1,2,3,0x84]));const out=m.map(0x3000,Buffer.alloc(4),{write:true});assert.equal(m.run(0x1000,{args:[0x2000,0x3000]}).value,0xffffffff84030201n);assert.equal(out.toString('hex'),'01020384');
  for(let size of [4,8])for(let off=0;off<size;off++){
    m=fixture([I(size===4?34:26,4,2,size-1),I(size===4?38:27,4,2,0),R(31,0,0,0,8),0]);const bytes=Buffer.from(Array.from({length:size*3},(_,i)=>i+1));m.map(0x2000,bytes);let expected=0n;for(let i=size-1;i>=0;i--)expected=(expected<<8n)|BigInt(bytes[off+i]);assert.equal(m.run(0x1000,{args:[0x2000+off]}).value,expected);
    const output=m.map(0x3000,Buffer.alloc(size*3,0xaa),{write:true});m.mergeStore(2,0x3000+off+size-1,size,true);m.mergeStore(2,0x3000+off,size,false);assert.deepEqual(output.subarray(off,off+size),bytes.subarray(off,off+size));assert(output.subarray(0,off).every(x=>x===0xaa));assert(output.subarray(off+size).every(x=>x===0xaa));
  }
  m=fixture([0xffffffff]);assert.throws(()=>m.run(0x1000),/unaligned/); // SD uses ra-1: rejected before memory access
  m=fixture([I(63,4,2,0)]);assert.throws(()=>m.run(0x1000,{args:[0x2000]}),/write denied/);
  m=fixture([0x0000000c]);assert.throws(()=>m.run(0x1000),/unsupported opcode/); // syscall
  m=fixture([R(31,1,0,0,8),0]);assert.throws(()=>m.run(0x1000),/reserved JR/);
  m=fixture([R(31,0,0,0,8),I(4,0,0,1),0]);assert.throws(()=>m.run(0x1000),/control transfer in a delay slot/);
  m=fixture([I(21,0,0,1),R(31,0,0,0,8),I(9,0,2,7),R(31,0,0,0,8),0]);assert.equal(m.run(0x1000).value,7n); // annulled JR never executes
  m=fixture([(2<<26)|(0x1000>>>2),0],{maxSteps:10});assert.throws(()=>m.run(0x1000),/step cap/);
  m=fixture([I(43,4,2,0)]);assert.throws(()=>m.run(0x1000,{args:[0x1000]}),/write denied/);
  assert.throws(()=>m.map(0x1000,Buffer.alloc(4)),/overlapping/);
  assert.throws(()=>m.load(0x1000,8),/read denied/);
  assert.throws(()=>m.run(0x1000,{returnAddress:0x1000}),/sentinel/);
  console.log('PASS bounded MIPS decoder fixtures: branch/call delay, likely annul, width, endian, unaligned merge, bounds, unsupported opcode and step cap');
}
if(require.main===module){assert(process.argv[2]==='--self-test','Only --self-test CLI; original decoding requires an explicit audited caller.');selfTest();}
module.exports={DecoderMachine,code,I,R,selfTest};
