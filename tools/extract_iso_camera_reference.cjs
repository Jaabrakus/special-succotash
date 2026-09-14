// Offline, read-only ISO inspection. Never executes code from the disc.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');

function openIso(file) {
  const fd = fs.openSync(file, 'r');
  const size = fs.fstatSync(fd).size;
  function read(offset, length) {
    assert(Number.isSafeInteger(offset) && Number.isSafeInteger(length));
    assert(offset >= 0 && length >= 0 && length <= 64 * 1024 * 1024 && offset + length <= size, 'ISO read bounds');
    const bytes = Buffer.alloc(length);
    assert.equal(fs.readSync(fd, bytes, 0, length, offset), length, 'short ISO read');
    return bytes;
  }
  function record(bytes, offset) {
    const length = bytes[offset];
    assert(length >= 34 && offset + length <= bytes.length, 'directory record bounds');
    const nameLength = bytes[offset + 32];
    assert(33 + nameLength <= length, 'directory name bounds');
    const sector = bytes.readUInt32LE(offset + 2), lengthBytes = bytes.readUInt32LE(offset + 10);
    assert.equal(sector, bytes.readUInt32BE(offset + 6), 'extent endian mismatch');
    assert.equal(lengthBytes, bytes.readUInt32BE(offset + 14), 'size endian mismatch');
    assert((bytes[offset + 25] & 128) === 0, 'multi-extent files unsupported');
    return {name: bytes.toString('ascii', offset + 33, offset + 33 + nameLength).replace(/;\d+$/, ''), sector, size: lengthBytes, directory: !!(bytes[offset + 25] & 2)};
  }
  try {
    const pvd = read(16 * 2048, 2048);
    assert(pvd[0] === 1 && pvd.toString('ascii', 1, 6) === 'CD001' && pvd[6] === 1, 'unsupported ISO descriptor');
    assert.equal(pvd.readUInt16LE(128), 2048, 'unsupported sector size');
    const root = record(pvd, 156);
    function find(relative) {
      let current = root;
      for (const component of relative.split('/')) {
        assert(current.directory && /^[A-Z0-9_.-]+$/i.test(component), 'invalid ISO path');
        const data = read(current.sector * 2048, current.size), entries = [];
        for (let i = 0; i < data.length;) {
          if (!data[i]) { i = (Math.floor(i / 2048) + 1) * 2048; continue; }
          entries.push(record(data, i)); i += data[i];
        }
        const matches = entries.filter(e => e.name.toUpperCase() === component.toUpperCase());
        assert.equal(matches.length, 1, 'missing/ambiguous ISO path: ' + relative);
        current = matches[0];
      }
      assert(!current.directory, 'expected file');
      return {...current, bytes: read(current.sector * 2048, current.size)};
    }
    function list(relative = '') {
      function entries(current) {
        assert(current.directory, 'expected directory');
        const data = read(current.sector * 2048, current.size), result = [];
        for (let i = 0; i < data.length;) {
          if (!data[i]) { i = (Math.floor(i / 2048) + 1) * 2048; continue; }
          result.push(record(data, i)); i += data[i];
        }
        return result.filter(e => e.name !== '\0' && e.name !== '\1');
      }
      let current = root;
      for (const component of relative ? relative.split('/') : []) {
        assert(/^[A-Z0-9_.-]+$/i.test(component), 'invalid ISO path');
        const matches = entries(current).filter(e => e.name.toUpperCase() === component.toUpperCase());
        assert.equal(matches.length, 1, 'missing/ambiguous ISO directory: ' + relative);
        current = matches[0];
      }
      return entries(current);
    }
    // Large archives are inspected in bounded chunks, never via an unbounded find().
    return {find, list, readRange: read, close: () => fs.closeSync(fd), size, volume: pvd.toString('ascii', 40, 72).trim()};
  } catch (error) { fs.closeSync(fd); throw error; }
}

function extract(isoFile, decoderDirectory) {
  // Existing reviewed decoder modules are supplied explicitly, not loaded from the ISO.
  const {archive} = require(path.resolve(decoderDirectory, 'extract.cjs'));
  const {reader} = require(path.resolve(decoderDirectory, 'readers.cjs'));
  const iso = openIso(isoFile);
  try {
    const file = iso.find('RUN/READERC.ZAR');
    const entries = archive(file.bytes).entries.filter(e => e.name.toLowerCase() === 'dynamics.rdr');
    assert.equal(entries.length, 1, 'expected one dynamics reader');
    const entry = entries[0], raw = file.bytes.subarray(entry.offset, entry.offset + entry.size);
    const tree = reader(raw), parameters = {};
    for (let i = 0; i < tree.length - 1; i++) {
      const key = tree[i], value = tree[i + 1];
      if (typeof key === 'string' && /^(cam_|camera_|CAMERA_|BOBBING_|.*aim_pitch$|.*look_pitch$|zoom_)/.test(key) && Array.isArray(value)) {
        assert(!Object.hasOwn(parameters, key), 'duplicate camera parameter');
        parameters[key] = value.length === 1 ? value[0] : value;
      }
    }
    for (const key of ['cam_full_dist', 'cam_full_height', 'cam_back_dist', 'cam_back_height']) {
      assert(Number.isFinite(parameters[key]) && parameters[key] > 0, 'invalid source camera dimensions');
    }
    return {schema_version: 1, status: 'decoded_parameters_not_executable_camera', source: {
      iso: path.basename(isoFile), iso_size: iso.size, volume: iso.volume,
      archive: 'RUN/READERC.ZAR', archive_sector: file.sector, archive_size: file.size,
      archive_sha256: sha(file.bytes), entry: entry.name, entry_offset: entry.offset,
      entry_size: entry.size, entry_sha256: sha(raw),
      decoder_sha256: {archive: sha(fs.readFileSync(path.join(decoderDirectory, 'extract.cjs'))), reader: sha(fs.readFileSync(path.join(decoderDirectory, 'readers.cjs')))}
    }, parameters, limitations: ['Source units and SOCOM II camera update formulas are not verified.', 'No FOV is established by these parameters.', 'Peek offsets, tether stiffness and pitch signs must not be copied directly into runtime.']};
  } finally { iso.close(); }
}

if (require.main === module) {
  const [iso, decoder, output] = process.argv.slice(2);
  assert(iso && decoder && output, 'usage: node tools/extract_iso_camera_reference.cjs ISO DECODER_DIRECTORY NEW_OUTPUT_JSON');
  const result = extract(iso, decoder);
  fs.writeFileSync(output, JSON.stringify(result, null, 2) + '\n', {flag: 'wx'});
  console.log(JSON.stringify({output, source: result.source, parameters: Object.keys(result.parameters).length}, null, 2));
}
module.exports = {openIso, extract};
