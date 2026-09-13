// Read-only metadata audit. Names from archives are NEVER used as output paths.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {openIso} = require('./extract_iso_camera_reference.cjs');
const sha = b => crypto.createHash('sha256').update(b).digest('hex');

function inspectArchive(buffer) {
  assert(buffer.length >= 100, 'short archive header');
  const n = buffer.readUInt32LE(4), bytes = buffer.readUInt32LE(8);
  const pointer = buffer.readUInt32LE(12), align = buffer.readUInt32LE(16);
  assert(buffer.readUInt32LE(0) === 0 && buffer.readUInt32LE(96) === 0x20002, 'archive flags/version');
  assert(n > 0 && n < 100000 && align > 0 && align <= 4096, 'archive directory limits');
  const table = 100 + bytes, payload = Math.ceil((table + n * 16) / align) * align;
  assert(payload <= buffer.length, 'archive directory bounds');
  const entries = []; let cursor = 0;
  function key(parentIndex, depth) {
    assert(depth < 64 && cursor < n, 'archive tree bounds');
    const index = cursor++, p = table + index * 16;
    const np = buffer.readUInt32LE(p) - pointer;
    const offset = payload + buffer.readUInt32LE(p + 4), size = buffer.readUInt32LE(p + 8);
    const children = buffer.readUInt32LE(p + 12);
    assert(offset <= buffer.length && size <= buffer.length - offset, 'archive payload bounds');
    let name = '';
    if (index) {
      assert(np >= 0 && np < bytes, 'archive name pointer');
      const end = buffer.indexOf(0, 100 + np);
      assert(end >= 100 + np && end < table, 'archive name termination');
      name = buffer.toString('ascii', 100 + np, end);
    }
    entries.push({index, parentIndex, name, offset, size});
    for (let c = 0; c < children; c++) key(index, depth + 1);
  }
  key(null, 0);
  assert.equal(cursor, n, 'unvisited archive keys');
  return entries;
}

function inspectFile(file) {
  const bytes = fs.readFileSync(file), entries = inspectArchive(bytes);
  const records = entries.filter(e => /^(MetersPerUnit|camera|cameras)$/i.test(e.name)).map(e => {
    const raw = bytes.subarray(e.offset, e.offset + e.size);
    return {...e, parent: entries[e.parentIndex]?.name ?? null, sha256: sha(raw), hex: raw.toString('hex'),
      floats: Array.from({length: Math.floor(raw.length / 4)}, (_, i) => raw.readFloatLE(i * 4))};
  });
  return {file, size: bytes.length, sha256: sha(bytes), records};
}

function sourceWorld(iso, id) {
  assert(/^MP?\d+$/.test(id), 'invalid world id');
  const source = iso.find('RUN/' + id + '.ZDB'), b = source.bytes;
  assert(b.length >= 160 && b.readUInt32LE(0) === 252 && b.readUInt32LE(4) === 1, 'ZDB version');
  const count = b.readUInt32LE(152), record = b.readUInt32LE(156);
  assert(record === 92 && count < 10000 && 160 + count * record <= b.length, 'ZDB directory');
  const matches = [];
  for (let i = 0; i < count; i++) {
    const p = 160 + i * record, end = b.indexOf(0, p + 4);
    assert(b.readUInt32LE(p) === record && end >= p + 4 && end < p + 68, 'ZDB record');
    const name = b.toString('ascii', p + 4, end), offset = b.readUInt32LE(p + 68), size = b.readUInt32LE(p + 72);
    assert(offset >= 160 + count * record && offset <= b.length && size <= b.length - offset, 'ZDB payload');
    if (name.split('\\').at(-1) === id + '.ZED') matches.push({name, offset, size, sha256: sha(b.subarray(offset, offset + size))});
  }
  assert.equal(matches.length, 1, 'one source world required');
  return {iso_path: 'RUN/' + id + '.ZDB', sector: source.sector, zdb_sha256: sha(b), ...matches[0]};
}

function auditLibrary(library, iso = null) {
  const worlds = [];
  for (const dir of fs.readdirSync(library).filter(x => /^MP?\d+$/.test(x)).sort()) {
    const raw = path.join(library, dir, 'raw');
    for (const name of fs.readdirSync(raw).filter(x => new RegExp('^\\d+--' + dir + '\\.ZED$').test(x))) {
      const world = inspectFile(path.join(raw, name));
      if (iso) {
        world.source = sourceWorld(iso, dir);
        assert.equal(world.sha256, world.source.sha256, 'extracted world differs from ISO');
      }
      worlds.push(world);
    }
  }
  assert(worlds.length > 0, 'no world archives');
  return {schema_version: 1, status: 'raw_world_camera_metadata_not_runtime_calibration', worlds};
}

function selfTest() {
  assert.throws(() => inspectArchive(Buffer.alloc(0)), /short archive/);
  const b = Buffer.alloc(116); b.writeUInt32LE(1, 4); b.writeUInt32LE(4, 16); b.writeUInt32LE(0x20002, 96);
  assert.equal(inspectArchive(b).length, 1);
  b.writeUInt32LE(999999, 108);
  assert.throws(() => inspectArchive(b), /payload bounds/);
  b.writeUInt32LE(0, 108); b.writeUInt32LE(1, 112);
  assert.throws(() => inspectArchive(b), /tree bounds/);
  console.log('camera source metadata audit self-test PASS');
}

if (require.main === module) {
  if (process.argv[2] === '--self-test') selfTest();
  else {
    const [library, output, isoFile] = process.argv.slice(2);
    assert(library && output, 'usage: node tools/camera_source_calibration_audit.cjs MAP_LIBRARY NEW_OUTPUT_JSON [ISO]');
    const iso = isoFile ? openIso(isoFile) : null;
    let report;
    try { report = auditLibrary(library, iso); } finally { iso?.close(); }
    fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n', {flag: 'wx'});
    console.log(JSON.stringify({output, worlds: report.worlds.length, records: report.worlds.reduce((n, x) => n + x.records.length, 0)}));
  }
}
module.exports = {inspectArchive, inspectFile, auditLibrary};
