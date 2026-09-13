'use strict';
// Header/table inspection only. Never executes or disassembles ISO content.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {openIso} = require('./extract_iso_camera_reference.cjs');
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const hex = n => '0x' + n.toString(16);

function elfInventory(bytes) {
  assert(bytes.length >= 52 && bytes.subarray(0, 4).equals(Buffer.from([127,69,76,70])), 'ELF header missing');
  assert(bytes[4] === 1 && bytes[5] === 1 && bytes[6] === 1, 'only ELF32 little-endian version 1 supported');
  const bounds = (offset, size) => assert(Number.isSafeInteger(offset + size) && offset >= 0 && size >= 0 && offset + size <= bytes.length, 'ELF table bounds');
  const shoff = bytes.readUInt32LE(32), shentsize = bytes.readUInt16LE(46), shnum = bytes.readUInt16LE(48), shstrndx = bytes.readUInt16LE(50);
  assert(shnum > 0 && shentsize === 40 && shstrndx < shnum, 'unsupported extended/missing section table');
  bounds(shoff, shnum * shentsize);
  const sections = Array.from({length: shnum}, (_, index) => {
    const p = shoff + index * shentsize;
    const s = {index, name_offset: bytes.readUInt32LE(p), type: bytes.readUInt32LE(p + 4), flags: hex(bytes.readUInt32LE(p + 8)), address: hex(bytes.readUInt32LE(p + 12)), offset: bytes.readUInt32LE(p + 16), size: bytes.readUInt32LE(p + 20), link: bytes.readUInt32LE(p + 24), entry_size: bytes.readUInt32LE(p + 36)};
    if (s.type !== 8) bounds(s.offset, s.size); // SHT_NOBITS does not occupy file bytes.
    return s;
  });
  const stringAt = (section, offset) => {
    assert(section.type === 3 && offset < section.size, 'invalid ELF string reference');
    const begin = section.offset + offset, end = bytes.indexOf(0, begin);
    assert(end >= begin && end < section.offset + section.size, 'unterminated ELF string');
    return bytes.toString('utf8', begin, end);
  };
  for (const section of sections) section.name = stringAt(sections[shstrndx], section.name_offset);
  const symbol_tables = sections.filter(s => s.type === 2 || s.type === 11).map(s => {
    assert(s.entry_size === 16 && s.size % 16 === 0 && s.link < sections.length, 'invalid ELF32 symbol table');
    const symbols = Array.from({length: s.size / 16}, (_, index) => {
      const p = s.offset + index * 16;
      return {index, name: stringAt(sections[s.link], bytes.readUInt32LE(p)), value: hex(bytes.readUInt32LE(p + 4)), size: bytes.readUInt32LE(p + 8), type: bytes[p + 12] & 15, binding: bytes[p + 12] >>> 4, section_index: bytes.readUInt16LE(p + 14)};
    });
    return {section: s.name, kind: s.type === 2 ? 'SYMTAB' : 'DYNSYM', symbols};
  });
  const named_functions = symbol_tables.flatMap(t => t.symbols).filter(s => s.name && s.type === 2 && s.section_index !== 0);
  return {format: 'ELF32 little-endian', type: bytes.readUInt16LE(16), machine: bytes.readUInt16LE(18), elf_version: bytes.readUInt32LE(20), entry_point: hex(bytes.readUInt32LE(24)), flags: hex(bytes.readUInt32LE(36)), section_table_offset: shoff, section_count: shnum, sections, symbol_tables, named_functions,
    stripped_symbol_tables: symbol_tables.every(table => table.symbols.length === 0),
    interpretation: symbol_tables.every(table => table.symbols.length === 0) ? 'ELF symbol tables are absent or empty: no function names are available through ELF symbols. Empty section headers are not usable symbols. This does not prove absence of code, strings, overlays, or external debug metadata.' : 'Non-empty symbol tables present; names alone do not prove trajectory semantics.'};
}

function inventory(file) {
  const iso = openIso(file);
  try {
    const config = iso.find('SYSTEM.CNF');
    const text = config.bytes.toString('ascii');
    const boot = /^BOOT2\s*=\s*cdrom0:[\\/]([^;\r\n]+);\d+/im.exec(text);
    assert(boot, 'BOOT2 executable not identified');
    const executable_path = boot[1].replaceAll('\\', '/');
    const executable = iso.find(executable_path);
    return {schema_version: 1, status: 'Read-only boot ELF header/section/symbol inventory; no code execution or decompilation',
      source: {iso_size: iso.size, volume: iso.volume, system_cnf_text: text, system_cnf_sha256: sha(config.bytes), executable_path, executable_bytes: executable.size, executable_sector: executable.sector, executable_sha256: sha(executable.bytes), boot_version: /^VER\s*=\s*(.+)$/im.exec(text)?.[1].trim() ?? null, video_mode: /^VMODE\s*=\s*(.+)$/im.exec(text)?.[1].trim() ?? null},
      elf: elfInventory(executable.bytes)};
  } finally { iso.close(); }
}

function selfTest() {
  assert.throws(() => elfInventory(Buffer.alloc(12)));
  const bytes = Buffer.alloc(144); Buffer.from([127,69,76,70,1,1,1]).copy(bytes);
  bytes.writeUInt32LE(52,32); bytes.writeUInt16LE(40,46); bytes.writeUInt16LE(2,48); bytes.writeUInt16LE(1,50);
  bytes.writeUInt32LE(1,92); bytes.writeUInt32LE(3,96); bytes.writeUInt32LE(132,108); bytes.writeUInt32LE(11,112);
  Buffer.from('\0.shstrtab\0').copy(bytes,132);
  const valid = elfInventory(bytes);
  assert(valid.stripped_symbol_tables && valid.named_functions.length === 0 && valid.sections[1].name === '.shstrtab');
  const bad = Buffer.from(bytes); bad.writeUInt32LE(0xffffff00,32); assert.throws(() => elfInventory(bad));
  console.log('SOURCE_EXECUTABLE_INVENTORY_SELF_TEST PASS');
}

if (require.main === module) {
  if (process.argv[2] === '--self-test') selfTest();
  else {
    const [iso, output] = process.argv.slice(2);
    assert(iso && output, 'usage: node tools/source_executable_inventory.cjs ISO NEW_REPORT.json');
    const result = inventory(iso);
    fs.writeFileSync(output, JSON.stringify(result, null, 2) + '\n', {flag: 'wx'});
    console.log('SOURCE_EXECUTABLE_INVENTORY PASS ' + JSON.stringify({source: result.source, entry: result.elf.entry_point, sections: result.elf.sections.map(s => s.name), symbol_tables: result.elf.symbol_tables.length, named_functions: result.elf.named_functions.length}));
  }
}
module.exports = {inventory, elfInventory};
