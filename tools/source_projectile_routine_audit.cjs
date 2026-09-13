'use strict';
// Offline, read-only disassembly of the decoded source module. No execution.
const fs=require('node:fs');
const assert=require('node:assert/strict');
const {disassemble}=require('./source_loader_analysis.cjs');
function moduleImage(file){
  const bytes=fs.readFileSync(file);assert(bytes.length>=64&&bytes.toString('ascii',0,4)==='MWo3');
  const base=bytes.readUInt32LE(8);return{bytes,base,offset(a){const p=a-base;assert(p>=0&&p+4<=bytes.length,'mapped source bounds');return p;}};
}
if(require.main===module){const[file,range]=process.argv.slice(2);assert(file&&range);const[start,end]=range.split(':').map(v=>parseInt(v,16));for(const row of disassemble(moduleImage(file),start,end))console.log(`${row.pc} ${row.word.padEnd(10)} ${row.assembly}`);}
module.exports={moduleImage};
