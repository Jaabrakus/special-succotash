const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const assert = require('node:assert/strict');
const {openIso} = require('./extract_iso_camera_reference.cjs');
// Generated, non-game fixture. Exercise bounds and paths without requiring an ISO.
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'socom-iso-parser-test-'));
function record(name, sector, size, directory) {
  const n = Buffer.from(name, 'ascii'), length = 33 + n.length + ((33 + n.length) % 2);
  const r = Buffer.alloc(length); r[0] = length;
  r.writeUInt32LE(sector, 2); r.writeUInt32BE(sector, 6);
  r.writeUInt32LE(size, 10); r.writeUInt32BE(size, 14);
  r[25] = directory ? 2 : 0; r[32] = n.length; n.copy(r, 33); return r;
}
const bytes = Buffer.alloc(21 * 2048), pvd = bytes.subarray(16 * 2048, 17 * 2048);
pvd[0] = 1; pvd.write('CD001', 1); pvd[6] = 1; pvd.writeUInt16LE(2048, 128);
record('\0', 18, 2048, true).copy(pvd, 156);
record('RUN', 19, 2048, true).copy(bytes, 18 * 2048);
record('TEST.BIN;1', 20, 3, false).copy(bytes, 19 * 2048);
bytes.write('abc', 20 * 2048);
function file(label, data) {const p = path.join(scratch, label); fs.writeFileSync(p, data, {flag:'wx'}); return p;}
const iso = openIso(file('valid.iso', bytes));
try {
  assert.equal(iso.find('RUN/TEST.BIN').bytes.toString(), 'abc');
  assert.throws(()=>iso.find('../TEST.BIN'));
  assert.throws(()=>iso.find('RUN/MISSING.BIN'));
  assert.throws(()=>iso.find('RUN'));
  assert.deepEqual(iso.list().map(e => e.name), ['RUN']);
  assert.deepEqual(iso.list('run').map(e => e.name), ['TEST.BIN']);
  assert.throws(()=>iso.list('../RUN'));
  assert.throws(()=>iso.list('RUN/MISSING'));
  assert.throws(()=>iso.list('RUN/TEST.BIN'));
} finally {iso.close();}
assert.throws(()=>openIso(file('truncated.iso', Buffer.alloc(15))));
const wrong = Buffer.from(bytes); wrong[16*2048+1] = 0;
assert.throws(()=>openIso(file('bad-descriptor.iso', wrong)));
const endian = Buffer.from(bytes); endian.writeUInt32BE(99, 16*2048+156+6);
assert.throws(()=>openIso(file('bad-endian.iso', endian)));
const extent = Buffer.from(bytes); record('TEST.BIN;1', 99, 3, false).copy(extent, 19*2048);
const outside = openIso(file('outside.iso', extent));
try {assert.throws(()=>outside.find('RUN/TEST.BIN'));} finally {outside.close();}
console.log('ISO_REFERENCE_REGRESSION PASS: valid read, traversal, missing path, directory, truncation, signature, endian, extent bounds. Fixtures: '+scratch);
