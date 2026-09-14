'use strict';
const fs = require('node:fs');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {openIso} = require('./extract_iso_camera_reference.cjs');
const {elfInventory} = require('./source_executable_inventory.cjs');
const {archive} = require('./socom_geometry/archive.cjs');
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
const hex = n => '0x' + n.toString(16);

function loadSegments(b) {
  assert(b.length >= 52 && b.readUInt32LE(0) === 0x464c457f && b[4] === 1 && b[5] === 1);
  const offset = b.readUInt32LE(28), stride = b.readUInt16LE(42), count = b.readUInt16LE(44);
  assert(stride === 32 && offset + stride * count <= b.length, 'ELF program table bounds');
  return Array.from({length: count}, (_, i) => {
    const p = offset + i * stride;
    const type = b.readUInt32LE(p), fileOffset = b.readUInt32LE(p + 4), address = b.readUInt32LE(p + 8), fileSize = b.readUInt32LE(p + 16), memorySize = b.readUInt32LE(p + 20), flags = b.readUInt32LE(p + 24);
    assert(fileOffset + fileSize <= b.length && (type !== 1 || memorySize >= fileSize));
    return {index: i, type, file_offset: fileOffset, file_bytes: fileSize, virtual_address: hex(address), memory_bytes: memorySize, end_address_exclusive: hex(address + memorySize), executable: !!(flags & 1), flags};
  });
}
function strings(b, pattern) {
  return [...b.toString('latin1').matchAll(/[ -~]{7,}/g)].filter(m => pattern.test(m[0])).map(m => ({offset: m.index, value: m[0]}));
}
// Same 92-byte outer ZDB record layout as the existing map-assets/zdb.cjs.
// This is not the different inner ZAR key-tree layout.
function zdbEntries(b, totalSize = b.length) {
  assert(Number.isSafeInteger(totalSize) && totalSize >= b.length, 'invalid ZDB size');
  assert(b.length >= 160 && b.readUInt32LE(0) === 252 && b.readUInt32LE(4) === 1, 'unsupported ZDB');
  const count = b.readUInt32LE(152), stride = b.readUInt32LE(156);
  assert(stride === 92 && count < 10000 && 160 + count * stride <= b.length, 'ZDB table bounds');
  return Array.from({length:count}, (_, i) => {
    const p = 160 + i * stride, end = b.indexOf(0, p + 4);
    assert(b.readUInt32LE(p) === 92 && end >= p + 4 && end < p + 68, 'ZDB name/record bounds');
    const offset = b.readUInt32LE(p + 68), size = b.readUInt32LE(p + 72);
    assert(offset >= 160 + count * stride && offset + size <= totalSize, 'ZDB payload bounds');
    return {name:b.toString('ascii',p + 4,end), offset,size};
  });
}
function inventory(file) {
  const iso = openIso(file);
  try {
    const files = [], directories = [], seen = new Set();
    function walk(dir, depth = 0) {
      assert(depth < 12 && directories.length < 512, 'bounded directory walk');
      directories.push(dir || '/');
      for (const entry of iso.list(dir)) {
        const p = dir ? dir + '/' + entry.name : entry.name;
        if (entry.directory) { assert(!seen.has(entry.sector), 'cyclic directory'); seen.add(entry.sector); walk(p, depth + 1); }
        else files.push({path: p, sector: entry.sector, size: entry.size});
      }
    }
    walk('');
    const cnf = iso.find('SYSTEM.CNF').bytes.toString('ascii');
    const boot = /^BOOT2\s*=\s*cdrom0:[\\/]([^;\r\n]+);\d+/im.exec(cnf)?.[1];
    assert(boot);
    const candidates = files.filter(f => f.path === boot || /\.(ELF|IRX|IMG|BIN|OVL|REL)$/i.test(f.path));
    const modules = candidates.map(f => {
      assert(f.size < 16 * 1024 * 1024, 'module inspection size cap');
      const b = iso.find(f.path).bytes;
      const r = {...f, sha256: sha(b), magic_hex: b.subarray(0, 16).toString('hex')};
      if (b.length >= 4 && b.readUInt32LE(0) === 0x464c457f) {
        r.format = 'ELF';
        try {
          const e = elfInventory(b);
          r.elf = {entry: e.entry_point, machine: e.machine, type: e.type, section_count: e.section_count, symbol_tables: e.symbol_tables.map(t => ({section: t.section, entries: t.symbols.length})), named_functions_count: e.named_functions.length,
            projectile_named_functions: e.named_functions.filter(s => /projectile|trajectory|zwep|bullet|weapon.*fire|fire.*weapon/i.test(s.name)),
            named_function_examples: e.named_functions.slice(0, 12)};
        } catch (e) { r.symbol_inventory_deferred = e.message; }
        if (f.path === boot || /SCUSNGUI/i.test(f.path)) r.program_headers = loadSegments(b);
        if (f.path === boot) {
          r.payload_prefix_before_entry = {file_offset:256, bytes:524288, all_zero:b.subarray(256,524544).every(v => v === 0)};
          r.compiler_comment = b.toString('ascii',874285,874328);
        }
      } else if (b.toString('ascii', 0, 4) === 'MWo3') {
        r.format = 'MWo3 overlay container; header layout not fully decoded';
        r.first_40_bytes_u32le = Array.from({length:10}, (_, i) => ({offset:i * 4, value:hex(b.readUInt32LE(i * 4))}));
      } else r.format = 'non-ELF module/data container; not decoded';
      if (f.path === boot || f.path === 'SCUSNGUI.ELF' || f.path.startsWith('OVERLAY/')) {
        r.named_references = strings(b, /overlay|DNAS|SCUS|NETGUI|APACHE00|FTSCORE|ZSEALETC|compress|projectile|trajectory|zwep/i);
        if (f.path === boot) for (const reference of r.named_references) {
          const segment = r.program_headers.find(s => reference.offset >= s.file_offset && reference.offset < s.file_offset + s.file_bytes);
          if (segment) reference.virtual_data_address = hex(parseInt(segment.virtual_address,16) + reference.offset - segment.file_offset);
          reference.is_callable_address = false;
        }
      }
      return r;
    });
    const embedded_modules = [];
    const archives = ['RUN/READERC.ZAR', 'RUN/ZWEAPON.ZAR', 'RUN/MP1.ZDB', 'RUN/M51.ZDB', 'RUN/RAW/APACHE00.ZDB'].map(p => {
      const b = iso.find(p).bytes;
      let names;
      try { names = p.endsWith('.ZDB') ? zdbEntries(b) : archive(b).entries.filter(e => e.name).map(e => ({name:e.name, offset:e.offset, size:e.size})); }
      catch (error) { return {path:p, sha256:sha(b), deferred:error.message, reason:'Outer container is not this ZAR decoder version; no entries guessed.'}; }
      if (p === 'RUN/RAW/APACHE00.ZDB') {
        for (const entry of names) {
          const payload = b.subarray(entry.offset, entry.offset + entry.size);
          embedded_modules.push({...entry, archive:p, sha256:sha(payload), prefix_96_bytes_hex:payload.subarray(0,96).toString('hex'),
            is_plain_elf:payload.readUInt32LE(0) === 0x464c457f, is_plain_mwo3:payload.toString('ascii',0,4) === 'MWo3',
            named_references:strings(payload,/ftscore|zseal|projectile|weapon|zwep|muzzle|compress/i),
            status:'Named runtime-code candidate; wrapped payload, decoding/loading not established. Not claimed to contain a located projectile routine.'});
        }
      }
      return {path:p, sha256:sha(b), entry_count:names.length,
        executable_named_entries: names.filter(e => /\.(ELF|IRX|OVL|REL|BIN)$/i.test(e.name) || /code|executable|overlay|module|symbol|ftscore|zsealetc/i.test(e.name)),
        weapon_named_entries: names.filter(e => /weap|zwep|ammo|bullet|projectile/i.test(e.name))};
    });
    return {schema_version:1, source:{volume:iso.volume, iso_size:iso.size, boot_config:cnf}, status:'Read-only directory/header/symbol/reference inventory; no executable invocation or disassembly', directories, files, modules, sampled_archives:archives, embedded_modules,
      limits:['Only five named gameplay/data archives inspected internally; no claim that every disc payload is exhaustively decoded.', 'MWo3 numeric header words and strings are evidence, not a recovered relocation/compression loader.', 'Reserved executable virtual memory is not proof of which subsystem fills it.', 'IOP/network GUI symbols do not establish EE gameplay projectile functions.']};
  } finally {iso.close();}
}
if (require.main === module) {
  const [file, output] = process.argv.slice(2); assert(file && output);
  const r = inventory(file); fs.writeFileSync(output, JSON.stringify(r,null,2) + '\n', {flag:'wx'});
  console.log('SOURCE_RUNTIME_MODULE_INVENTORY PASS ' + JSON.stringify({files:r.files.length, modules:r.modules.length, elf_modules:r.modules.filter(m => m.elf).length, symbol_bearing:r.modules.filter(m => m.elf?.named_functions_count).map(m => ({path:m.path, functions:m.elf.named_functions_count})), projectile_symbols:r.modules.flatMap(m => m.elf?.projectile_named_functions || []), sampled_archives:r.sampled_archives}));
}
module.exports = {inventory, loadSegments, zdbEntries};
