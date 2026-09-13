'use strict';
// Bounded original scalar-math instructions only, not boot/game execution.
const assert=require('node:assert/strict');
const crypto=require('node:crypto');
const path=require('node:path');
const {image}=require('./source_loader_analysis.cjs');
const {moduleImage}=require('./source_projectile_routine_audit.cjs');
const {FloatFixtureMachine}=require('./source_mips_float_fixture.cjs');
const BOOT_HASH='0172dc0bec19c83d1fe2d0fec0a290f41cc5d32efa14ed6859ca92773c05346c';
const MODULES=path.resolve(__dirname,'../art_source/socom2_ballistics_reference_20260912/decoded_runtime_v1');
function sourceSpan(m,im,lo,hi,execute=true){
  m.map(lo,im.bytes.subarray(im.offset(lo),im.offset(hi)),{execute,name:'original audited scalar span'});
}
function tangentMachine(im){
  const m=new FloatFixtureMachine({maxSteps:10000,maxMappedBytes:128*1024});
  for(const[lo,hi,execute]of [[0x1b3808,0x1b3880,true],[0x1b2a00,0x1b2c84,true],[0x1b04f8,0x1b08a8,true],[0x1d2d98,0x1d2dcc,false]])sourceSpan(m,im,lo,hi,execute);
  m.map(0x100000,Buffer.alloc(4096),{write:true,name:'bounded scratch stack'});
  return m;
}
function auditedModule(file,hash){
  const im=moduleImage(file);
  assert.equal(crypto.createHash('sha256').update(im.bytes).digest('hex'),hash,'unexpected module; source addresses are version-specific');
  return im;
}
function audit(iso,modules=MODULES){
  const im=image(iso),hash=crypto.createHash('sha256').update(im.bytes).digest('hex');
  assert.equal(hash,BOOT_HASH,'unexpected boot; source addresses are version-specific');
  const rows=[];
  for(const argument of [-1.2,-1,-0.785,-0.75,-0.65,-0.5235988,-0.25,0.1,0.25,0.5235988,0.65,0.75,0.785,1,1.2]){
    const m=tangentMachine(im);
    m.setFloat(12,argument);m.run(0x1b3808,{stackPointer:0x100800});
    const input=Math.fround(argument),output=m.float(0),expected=Math.fround(Math.tan(input));
    const error=Math.abs(output-expected),tolerance=Math.max(1e-7,Math.abs(expected)*2e-7);
    assert(error<=tolerance,`tangent mismatch for radians ${argument}`);
    rows.push({argument_radians:input,source_output:output,host_tanf_reference:expected,absolute_error:error,instructions:m.steps});
  }
  const seal=auditedModule(path.join(modules,'ZSealEtc.bin'),'cdb3fa8e707090ac879874e3987c6b7784808a4767e85d0e19fc6909d36549b1');
  const core=auditedModule(path.join(modules,'FTSCore.bin'),'cf09a7fabaf59a1d68f01411bd1db9e859af054df1f2fbc4775d8c221785f836');
  const projectionRows=[];
  for(const[height,derivedVertical,dilation]of [[448,.7,6],[1080,.65,12],[480,.9,0],[480,.9,30],[0,.9,6]]){
    const m=tangentMachine(im);
    sourceSpan(m,seal,0x5bd448,0x5bd4e8);
    const globals=Buffer.alloc(4);globals.writeUInt32LE(height);m.map(0x4a44c8,globals);
    const data=m.map(0x110000,Buffer.alloc(8192),{write:true,name:'synthetic controller and seal'});
    data.writeUInt32LE(0x111000,2096);m.set64(17,0x110000n);
    m.setFloat(25,derivedVertical);m.setFloat(22,dilation);
    m.run(0x5bd448,{stackPointer:0x100800,returnAddress:0x5bd4e8});
    const output=data.readFloatLE(0x1000+1500),f=Math.fround;
    const expected=height===0?0:f(f(.707)*f(f(dilation)*f(f(Math.tan(f(f(.5)*f(derivedVertical))))/f(f(.5)*f(height)))));
    assert(Math.abs(output-expected)<=Math.max(1e-8,Math.abs(expected)*2e-7),'source projection operation mismatch');
    projectionRows.push({height,derived_vertical_ratio:f(derivedVertical),dilation,source_output:output,host_float32_reference:expected,instructions:m.steps});
  }
  const cameraRows=[];
  for(const width of [640,641,1920,1921]){
    const m=new FloatFixtureMachine({maxSteps:100,maxMappedBytes:4096});
    sourceSpan(m,core,0x293e0c,0x293e44);
    const globals=Buffer.alloc(4);globals.writeUInt32LE(width);m.map(0x4a44c4,globals);
    const camera=m.map(0x110000,Buffer.alloc(2048),{write:true,name:'synthetic camera'});
    m.set64(16,0x110000n);m.set64(1,0x4a0000n);
    m.run(0x293e0c,{returnAddress:0x293e44});
    const output=camera.readFloatLE(0x4b0);assert.equal(output,Math.fround(width>>>1));
    cameraRows.push({width,camera_0x4b0:output,instructions:m.steps});
  }
  return{boot:im.boot,boot_sha256:hash,entry:'0x1b3808',kernel:'0x1b2a00',argument_reduction:'0x1b04f8',fixtures:rows,projection_fixtures:projectionRows,camera_half_width_fixtures:cameraRows,limitations:['Finite normal tangent inputs in [-1.2,1.2] only; zero/tiny inputs and huge argument reduction not tested.','IEEE float32 fixture arithmetic does not claim bit-exact PS2 EE behavior.','Projection fixtures inject the already-derived vertical ratio, not an assumed vertical FOV. Full 0x5bd100 is not executed.','Camera setters establish a projection-distance field; the actual gameplay FOV value and all camera update paths have not been traced.']};
}
if(require.main===module){assert(process.argv[2],'usage: node tools/source_projection_factor_audit.cjs SOCOM_II.iso [decoded_module_folder]');console.log(JSON.stringify(audit(process.argv[2],process.argv[3]),null,2));console.log('PASS original tangent: 15 finite-angle, 5 projection, 4 camera half-width fixtures');}
module.exports={audit};
