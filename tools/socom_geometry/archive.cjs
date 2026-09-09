'use strict';
// Offline research reader; archive names are metadata, never filesystem paths.
const assert = require('node:assert/strict');
function archive(b) {
  assert(b.length >= 100, 'short header');
  const count=b.readUInt32LE(4), namesSize=b.readUInt32LE(8), pointer=b.readUInt32LE(12), align=b.readUInt32LE(16);
  assert(b.readUInt32LE(0)===0 && b.readUInt32LE(96)===0x20002, 'unsupported version');
  assert(count>0 && count<100000 && align>0 && align<=4096, 'invalid directory');
  const table=100+namesSize, payload=Math.ceil((table+count*16)/align)*align;
  assert(payload<=b.length,'directory out of bounds');
  const entries=[]; let cursor=0;
  function visit(parent=null,depth=0) {
    assert(depth<64 && cursor<count,'invalid key tree');
    const index=cursor++, at=table+index*16;
    const np=b.readUInt32LE(at)-pointer, offset=payload+b.readUInt32LE(at+4), size=b.readUInt32LE(at+8), children=b.readUInt32LE(at+12);
    let name='';
    if(index) {
      assert(np>=0 && np<namesSize,'name pointer out of bounds');
      const end=b.indexOf(0,100+np);
      assert(end>=100+np && end<table,'unterminated name');
      name=b.toString('ascii',100+np,end);
      assert(offset+size<=b.length,'entry out of bounds');
    }
    const e={index,parent,name,offset,size,children}; entries.push(e);
    for(let i=0;i<children;i++)visit(index,depth+1);
  }
  visit(); assert.equal(cursor,count,'unvisited entries');
  return {entries,payload};
}
module.exports={archive};
