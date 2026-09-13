'use strict';
const assert=require('node:assert/strict');
const {DecoderMachine,code,R,I}=require('./source_mips_decoder_harness.cjs');
class FloatFixtureMachine extends DecoderMachine {
  constructor(options){super(options);this.fp=new Uint32Array(32);this.condition=Array(8).fill(false);this.acc=0;this.scratch=Buffer.alloc(4);}
  float(i){const bits=this.fp[i];assert((bits&0x7f800000)!==0x7f800000,'non-finite FPU operand');assert((bits&0x7f800000)!==0||(bits&0x7fffff)===0,'subnormal FPU operand');this.scratch.writeUInt32LE(bits);return this.scratch.readFloatLE();}
  setFloat(i,value){assert(Number.isFinite(value),'non-finite FPU result');this.scratch.writeFloatLE(value);const bits=this.scratch.readUInt32LE();assert((bits&0x7f800000)!==0x7f800000,'FPU overflow');assert((bits&0x7f800000)!==0||(bits&0x7fffff)===0,'FPU underflow');this.fp[i]=bits;}
  step(){
    const pc=this.pc,w=Number(this.load(this.aligned(pc,4),4,false,'execute')),op=w>>>26;
    if(![17,49,57].includes(op))return super.step();
    assert(this.steps<this.maxSteps,'instruction step cap');
    const fmt=(w>>>21)&31,ft=(w>>>16)&31,fs=(w>>>11)&31,fd=(w>>>6)&31,fn=w&63,imm=(w<<16)>>16;
    const isBranch=op===17&&fmt===8;assert(!(this.inDelaySlot&&isBranch),'control transfer in a delay slot is unsupported');this.inDelaySlot=isBranch;
    const next=this.nextPC;this.pc=next;this.nextPC=(next+4)>>>0;this.steps++;this.lastPCs.push(pc);if(this.lastPCs.length>16)this.lastPCs.shift();
    if(op===49){this.fp[ft]=Number(this.load(this.aligned(this.address(fmt,imm),4),4));return;}
    if(op===57){this.store(this.aligned(this.address(fmt,imm),4),4,BigInt(this.fp[ft]));return;}
    if(fmt===0||fmt===4){assert((w&2047)===0,'reserved FPU transfer encoding');if(fmt===0)this.set32(ft,BigInt(this.fp[fs]));else this.fp[fs]=Number(this.u32(ft));return;}
    if(isBranch){const selected=this.condition[ft>>>2],taken=(ft&1)?selected:!selected;if(taken)this.nextPC=(pc+4+imm*4)>>>0;else if(ft&2){this.pc=this.nextPC;this.nextPC=(this.nextPC+4)>>>0;this.inDelaySlot=false;}return;}
    if(fmt===20&&fn===32){assert(ft===0,'reserved CVT.S.W ft');this.setFloat(fd,this.fp[fs]|0);return;}
    assert(fmt===16,`unsupported FPU format ${fmt} at 0x${pc.toString(16)}`);
    const a=()=>this.float(fs),b=()=>this.float(ft);
    switch(fn){
      case 0:this.setFloat(fd,a()+b());return;
      case 1:this.setFloat(fd,a()-b());return;
      case 2:this.setFloat(fd,a()*b());return;
      case 3:assert(b()!==0,'FPU zero divisor');this.setFloat(fd,a()/b());return;
      case 4:assert(fs===0,'reserved PS2 SQRT fs');this.setFloat(fd,Math.sqrt(Math.abs(b())));return;
      case 5:assert(ft===0);this.setFloat(fd,Math.abs(a()));return;
      case 6:assert(ft===0);this.fp[fd]=this.fp[fs];return;
      case 7:assert(ft===0);this.setFloat(fd,-a());return;
      case 13:{assert(ft===0);const v=Math.trunc(a());assert(v>=-2147483648&&v<=2147483647,'FPU integer overflow');this.fp[fd]=v>>>0;return;}
      case 24:this.acc=Math.fround(a()+b());assert(Number.isFinite(this.acc));return;
      case 25:this.acc=Math.fround(a()-b());assert(Number.isFinite(this.acc));return;
      case 26:this.acc=Math.fround(a()*b());assert(Number.isFinite(this.acc));return;
      case 28:this.setFloat(fd,this.acc+Math.fround(a()*b()));return;
      case 29:this.setFloat(fd,this.acc-Math.fround(a()*b()));return;
      case 48:case 50:case 52:case 54:{assert((fd&3)===0,'reserved FPU comparison');const x=a(),y=b();this.condition[fd>>>2]=fn===48?false:fn===50?x===y:fn===52?x<y:x<=y;return;}
      default:throw Error(`unsupported scalar FPU fn ${fn} at 0x${pc.toString(16)}`);
    }
  }
}
const F=(fmt,ft,fs,fd,fn)=>((17<<26)|(fmt<<21)|(ft<<16)|(fs<<11)|(fd<<6)|fn)>>>0;
function selfTest(){
  let m=new FloatFixtureMachine();m.map(0x1000,code([F(16,2,1,3,0),F(16,2,3,4,2),F(16,4,0,5,4),R(31,0,0,0,8),0]),{execute:true});m.setFloat(1,4);m.setFloat(2,5);m.run(0x1000);assert.equal(m.float(3),9);assert.equal(m.float(4),45);assert.equal(m.float(5),Math.fround(Math.sqrt(45)));
  m=new FloatFixtureMachine();m.map(0x1000,code([F(16,2,1,0,52),I(17,8,3,1),I(9,0,2,99),R(31,0,0,0,8),0]),{execute:true});m.setFloat(1,4);m.setFloat(2,2);assert.equal(m.run(0x1000).value,0n);
  m=new FloatFixtureMachine();m.map(0x1000,code([F(20,0,1,2,32),F(16,0,2,3,13),F(0,2,3,0,0),R(31,0,0,0,8),0]),{execute:true});m.fp[1]=0xfffffff9;assert.equal(m.run(0x1000).value,0xfffffffffffffff9n);
  assert.throws(()=>m.setFloat(1,Infinity),/non-finite/);m.fp[1]=1;assert.throws(()=>m.float(1),/subnormal/);
  console.log('PASS finite scalar COP1 fixtures: arithmetic, PS2 sqrt-ft, branch-likely, signed conversion, unsupported numeric domain');
}
if(require.main===module){assert(process.argv[2]==='--self-test');selfTest();}
module.exports={FloatFixtureMachine,F,selfTest};
