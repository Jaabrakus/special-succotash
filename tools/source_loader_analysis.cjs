'use strict';
// Bounded static EE/MIPS inspection only; no instruction execution.
const assert = require('node:assert/strict');
const {openIso} = require('./extract_iso_camera_reference.cjs');
const {loadSegments} = require('./source_runtime_module_inventory.cjs');
const reg = ['zero','at','v0','v1','a0','a1','a2','a3','t0','t1','t2','t3','t4','t5','t6','t7','s0','s1','s2','s3','s4','s5','s6','s7','t8','t9','k0','k1','gp','sp','fp','ra'];
const hex = n => '0x' + (n >>> 0).toString(16);
function decode(w, pc) {
  const op = w >>> 26, rs = (w >>> 21) & 31, rt = (w >>> 16) & 31, rd = (w >>> 11) & 31, sa = (w >>> 6) & 31, fn = w & 63;
  const uimm = w & 65535, imm = (w << 16) >> 16;
  if (w === 0) return 'nop';
  if (op === 2 || op === 3) return `${op === 2 ? 'j' : 'jal'} ${hex(((pc + 4) & 0xf0000000) | ((w & 0x3ffffff) << 2))}`;
  if (op === 0) {
    if (fn === 8) return `jr ${reg[rs]}`;
    if (fn === 9) return `jalr ${reg[rd]},${reg[rs]}`;
    const shifts = {0:'sll',2:'srl',3:'sra',56:'dsll',58:'dsrl',59:'dsra',60:'dsll32',62:'dsrl32',63:'dsra32'};
    if (shifts[fn]) return `${shifts[fn]} ${reg[rd]},${reg[rt]},${sa}`;
    const alu = {4:'sllv',6:'srlv',7:'srav',20:'dsllv',22:'dsrlv',23:'dsrav',32:'add',33:'addu',34:'sub',35:'subu',36:'and',37:'or',38:'xor',39:'nor',42:'slt',43:'sltu',44:'dadd',45:'daddu',46:'dsub',47:'dsubu',10:'movz',11:'movn'};
    if ([4,6,7,20,22,23].includes(fn)) return `${alu[fn]} ${reg[rd]},${reg[rt]},${reg[rs]}`;
    if (alu[fn]) return `${alu[fn]} ${reg[rd]},${reg[rs]},${reg[rt]}`;
    if ([16,18].includes(fn)) return `${fn===16?'mfhi':'mflo'} ${reg[rd]}`;
    if ([17,19].includes(fn)) return `${fn===17?'mthi':'mtlo'} ${reg[rs]}`;
    const mult = {24:'mult',25:'multu',26:'div',27:'divu',28:'dmult',29:'dmultu',30:'ddiv',31:'ddivu'};
    if (mult[fn]) return `${mult[fn]} ${reg[rs]},${reg[rt]}`;
  }
  if (op === 15) return `lui ${reg[rt]},${hex(uimm)}`;
  if (op === 17) {
    const ft=rt,fs=rd,fd=sa;
    if(rs===0)return `mfc1 ${reg[rt]},f${fs}`;
    if(rs===4)return `mtc1 ${reg[rt]},f${fs}`;
    if(rs===2)return `cfc1 ${reg[rt]},fcr${fs}`;
    if(rs===6)return `ctc1 ${reg[rt]},fcr${fs}`;
    if(rs===8){const names={0:'bc1f',1:'bc1t',2:'bc1fl',3:'bc1tl'};if(names[rt])return `${names[rt]} ${hex(pc+4+imm*4)}`;}
    const format={16:'s',17:'d',20:'w'}[rs];
    if(format){
      // EE scalar accumulator instructions; local Play! COP_FPU_Reflection.cpp
      // 0x18..0x1f and SQRT.S operand order are the decoder reference.
      if(format==='s'&&fn===4)return `sqrt.s f${fd},f${ft}`;
      const accum={24:'adda',25:'suba',26:'mula',28:'madd',29:'msub',30:'madda',31:'msuba'}[fn];
      if(format==='s'&&accum)return `${accum}.s ${[28,29].includes(fn)?`f${fd},`:''}f${fs},f${ft}`;
      const name={0:'add',1:'sub',2:'mul',3:'div',4:'sqrt',5:'abs',6:'mov',7:'neg',12:'round.w',13:'trunc.w',14:'ceil.w',15:'floor.w',32:'cvt.s',33:'cvt.d',36:'cvt.w'}[fn];
      if(name)return `${name}.${format} f${fd},f${fs}${fn<4?`,f${ft}`:''}`;
      const compare={48:'f',49:'un',50:'eq',51:'ueq',52:'olt',53:'ult',54:'ole',55:'ule',56:'sf',57:'ngle',58:'seq',59:'ngl',60:'lt',61:'nge',62:'le',63:'ngt'}[fn];
      if(compare)return `c.${compare}.${format} f${fs},f${ft}`;
    }
  }
  if (op === 1) { const names={0:'bltz',1:'bgez',2:'bltzl',3:'bgezl',16:'bltzal',17:'bgezal'}; if(names[rt])return `${names[rt]} ${reg[rs]},${hex(pc+4+imm*4)}`; }
  const branches = {4:'beq',5:'bne',6:'blez',7:'bgtz',20:'beql',21:'bnel',22:'blezl',23:'bgtzl'};
  if (branches[op]) return `${branches[op]} ${reg[rs]},${reg[rt]},${hex(pc+4+imm*4)}`;
  const arithmetic = {8:'addi',9:'addiu',10:'slti',11:'sltiu',12:'andi',13:'ori',14:'xori',24:'daddi',25:'daddiu'};
  if (arithmetic[op]) return `${arithmetic[op]} ${reg[rt]},${reg[rs]},${[12,13,14].includes(op)?hex(uimm):imm}`;
  const memory={26:'ldl',27:'ldr',30:'lq',31:'sq',32:'lb',33:'lh',34:'lwl',35:'lw',36:'lbu',37:'lhu',38:'lwr',39:'lwu',40:'sb',41:'sh',42:'swl',43:'sw',44:'sdl',45:'sdr',46:'swr',49:'lwc1',55:'ld',57:'swc1',63:'sd'};
  if(memory[op])return `${memory[op]} ${[49,57].includes(op)?`f${rt}`:reg[rt]},${imm}(${reg[rs]})`;
  return `.word ${hex(w)} # opcode not decoded; do not infer semantics`;
}
function image(file, overlay = '') {
  const iso = openIso(file);
  try {
    const cnf = iso.find('SYSTEM.CNF').bytes.toString('ascii');
    const boot = /^BOOT2\s*=\s*cdrom0:[\\/]([^;\r\n]+);\d+/im.exec(cnf)?.[1]; assert(boot);
    const bytes = iso.find(overlay || boot).bytes;
    let segments;
    if (overlay) {
      assert(bytes.toString('ascii',0,4) === 'MWo3' && bytes.length >= 64, 'expected MWo3');
      assert(64 + bytes.readUInt32LE(12) + bytes.readUInt32LE(16) === bytes.length, 'MWo3 observed header/text/data size mismatch');
      // MWo3 observed load image retains its 64-byte header. This mapping is
      // cross-checked against four direct boot jal targets (see audit doc).
      // Skipping the header puts those calls inside unrelated instructions.
      segments = [{file_offset:0,file_bytes:bytes.length,virtual_address:hex(bytes.readUInt32LE(8))}];
    } else segments = loadSegments(bytes);
    const offset = address => {
      const s = segments.find(s => address >= parseInt(s.virtual_address,16) && address + 4 <= parseInt(s.virtual_address,16) + s.file_bytes);
      assert(s, 'address not backed by executable file');
      return s.file_offset + address - parseInt(s.virtual_address,16);
    };
    return {bytes, segments, offset, boot};
  } finally {iso.close();}
}
function disassemble(img, start, end) {
  assert(start % 4 === 0 && end % 4 === 0 && end > start && end - start <= 65536, 'bounded aligned static range');
  const rows=[];
  for(let pc=start;pc<end;pc+=4){const at=img.offset(pc),word=img.bytes.readUInt32LE(at); rows.push({pc:hex(pc),file_offset:at,word:hex(word),assembly:decode(word,pc)});}
  return rows;
}
if(require.main===module){const [iso,range,overlay]=process.argv.slice(2);assert(iso&&range,'usage: ISO HEX_START:HEX_END [OVERLAY]');const [start,end]=range.split(':').map(s=>parseInt(s,16));for(const r of disassemble(image(iso,overlay),start,end))console.log(`${r.pc} ${r.word.padEnd(10)} ${r.assembly}`);}
module.exports={image,disassemble,decode};
