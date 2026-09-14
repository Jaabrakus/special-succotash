'use strict';
// Offline provenance catalog. Names from the disc are labels, NEVER output paths.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const {openIso} = require('./extract_iso_camera_reference.cjs');
const {archive} = require('./socom_geometry/archive.cjs');
const {zdbEntries} = require('./source_runtime_module_inventory.cjs');
const policy = require('../config/source_asset_archive_policy.json');

function range(offset, size, total) {
  assert([offset, size, total].every(Number.isSafeInteger), 'integer range required');
  assert(offset >= 0 && size >= 0 && offset <= total && size <= total - offset, 'payload range out of bounds');
}
function hashRange(reader, offset, size) {
  range(offset, size, reader.size);
  const hash = crypto.createHash('sha256');
  for (let done = 0; done < size; done += policy.chunk_bytes) {
    hash.update(reader.readRange(offset + done, Math.min(policy.chunk_bytes, size - done)));
  }
  return hash.digest('hex');
}
function hashFile(file) {
  const fd = fs.openSync(file, 'r');
  try {
    const size = fs.fstatSync(fd).size;
    return hashRange({size, readRange(offset, length) {
      const b = Buffer.alloc(length);
      assert.equal(fs.readSync(fd, b, 0, length, offset), length, 'short existing file');
      return b;
    }}, 0, size);
  } finally { fs.closeSync(fd); }
}
function directory(reader, offset, size) {
  range(offset, size, reader.size);
  const h = reader.readRange(offset, Math.min(160, size));
  let format, bytes;
  if (h.length >= 100 && h.readUInt32LE(0) === 0 && h.readUInt32LE(96) === 0x20002) {
    format = 'ZAR_KEY_TREE';
    const count = h.readUInt32LE(4), names = h.readUInt32LE(8);
    assert(count > 0 && count < 100000, 'archive count cap');
    bytes = 100 + names + count * 16;
  } else if (h.length >= 160 && h.readUInt32LE(0) === 252 && h.readUInt32LE(4) === 1) {
    format = 'ZDB_92';
    assert(h.readUInt32LE(152) < 10000 && h.readUInt32LE(156) === 92, 'ZDB directory layout');
    bytes = 160 + h.readUInt32LE(152) * 92;
  } else return null;
  assert(bytes <= policy.max_directory_bytes && bytes <= size, 'directory allocation cap/bounds');
  const prefix = reader.readRange(offset, bytes);
  const entries = format === 'ZAR_KEY_TREE'
    ? archive(prefix, size).entries.filter(e => e.index > 0)
    : zdbEntries(prefix, size).map((e, index) => ({...e, index, parent: null, children: 0}));
  return {format, entries};
}
function existingMapExports(library) {
  const verified = new Map(), failures = [], manifests = [];
  if (!library) return {verified, failures, manifests};
  const root = fs.realpathSync(library);
  for (const entry of fs.readdirSync(root, {withFileTypes: true}).filter(e => e.isDirectory()).sort((a,b) => a.name.localeCompare(b.name))) {
    const manifestFile = path.join(root, entry.name, 'manifest.json');
    if (!fs.existsSync(manifestFile)) continue;
    const manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf8'));
    let checked = 0;
    for (const asset of manifest.assets || []) {
      // Only exact raw-file hashes can satisfy recovery; PNG/GLB hashes cannot.
      if (!asset.kind?.endsWith('_raw') || !/^[a-f0-9]{64}$/.test(asset.sha256 || '')) continue;
      try {
        assert(typeof asset.file === 'string' && !path.isAbsolute(asset.file), 'invalid existing asset path');
        const file = fs.realpathSync(path.resolve(path.dirname(manifestFile), asset.file));
        assert(file.startsWith(path.dirname(manifestFile) + path.sep), 'existing asset escaped map directory');
        assert.equal(fs.statSync(file).size, asset.size, 'existing size mismatch');
        assert.equal(hashFile(file), asset.sha256, 'existing hash mismatch');
        if (!verified.has(asset.sha256)) verified.set(asset.sha256, file);
        checked++;
      } catch (error) { failures.push({manifest: manifestFile, file: asset.file, reason: error.message}); }
    }
    manifests.push({file: manifestFile, sha256: hashFile(manifestFile), verified_raw_files: checked});
  }
  return {verified, failures, manifests};
}
function inventory(isoPath, library = null, progress = () => {}) {
  const iso = openIso(isoPath);
  try {
    const records = [], topFiles = [], issues = [], seenDirectories = new Set(), hashes = new Map(), expandedArchives = new Map();
    function walk(dir = '', depth = 0) {
      assert(depth < 12 && seenDirectories.size < 512, 'ISO directory walk cap');
      for (const entry of iso.list(dir).sort((a,b) => a.name.localeCompare(b.name))) {
        const name = dir ? dir + '/' + entry.name : entry.name;
        range(entry.sector * 2048, entry.size, iso.size);
        if (entry.directory) {
          assert(!seenDirectories.has(entry.sector), 'cyclic/aliased ISO directory');
          seenDirectories.add(entry.sector); walk(name, depth + 1);
        } else topFiles.push({...entry, path: name});
      }
    }
    walk();
    progress('Hashing original ISO in bounded chunks');
    const isoHash = hashRange(iso, 0, iso.size);
    function add(id, parent, topFile, name, offset, size, depth, group = false) {
      assert(records.length < policy.max_records && depth < policy.max_archive_depth, 'catalog recursion/record cap');
      range(offset, size, iso.size);
      const key = offset + ':' + size;
      if (!hashes.has(key)) hashes.set(key, hashRange(iso, offset, size));
      const record = {id, parent, top_file: topFile, name, offset, size,
        sha256: hashes.get(key), hierarchy_group: group,
        container: null, status: size ? 'raw_not_decoded' : 'empty_metadata',
        category_hint: path.extname(name.replaceAll('\\', '/')).slice(1).toUpperCase() || 'UNNAMED'};
      records.push(record);
      // A key-tree group has its own directory children; its payload is still
      // preserved, but must not be mistaken for another enclosing archive.
      if (!size || group) return;
      // ZED/MDL/property payloads can share the key-tree signature. Expanding
      // their scalar fields would manufacture millions of false "assets".
      if (!['ZAR', 'ZDB'].includes(record.category_hint)) return;
      const previous = expandedArchives.get(record.sha256);
      if (previous) {
        record.container = previous.container;
        record.directory_alias_of = previous.id;
        record.status = 'identical_directory_indexed_at_alias';
        return;
      }
      let parsed;
      try { parsed = directory(iso, offset, size); }
      catch (error) {
        record.status = 'container_parse_deferred';
        issues.push({id, name, reason: error.message}); return;
      }
      if (!parsed) {
        if (['ZAR', 'ZDB'].includes(record.category_hint)) {
          record.status = 'container_format_unknown';
          issues.push({id, name, reason: 'No supported directory signature; payload preserved without guessed decoding'});
        }
        return;
      }
      // Hierarchical ZARs (clutter placements and *ZANIM control tables) are
      // structured assets themselves, not thousands of independent scalar files.
      if (parsed.format === 'ZAR_KEY_TREE' && parsed.entries.some(e => e.children > 0)) {
        record.status = 'structured_key_tree_preserved_not_decoded';
        record.property_key_count = parsed.entries.length;
        record.root_keys = parsed.entries.filter(e => e.parent === 0).map(e => e.name);
        return;
      }
      record.container = parsed.format; record.status = 'directory_indexed_not_asset_decoded';
      expandedArchives.set(record.sha256, record);
      // Use table indices for stable identities, not archive-controlled names.
      for (const e of parsed.entries) {
        range(e.offset, e.size, size);
        const childId = id + '/' + parsed.format + ':' + e.index;
        const parentId = parsed.format === 'ZAR_KEY_TREE' && e.parent > 0
          ? id + '/' + parsed.format + ':' + e.parent : id;
        add(childId, parentId, topFile, e.name, offset + e.offset, e.size, depth + 1, e.children > 0);
      }
    }
    topFiles.forEach((file, index) => {
      add('iso:' + index, null, file.path, file.path, file.sector * 2048, file.size, 0);
      if (index % 25 === 0) progress(`Indexed ${index + 1}/${topFiles.length} disc files; ${records.length} records`);
    });
    progress('Checking existing raw map exports by content hash');
    const existing = existingMapExports(library);
    for (const record of records) {
      const file = existing.verified.get(record.sha256);
      if (file) record.existing_raw_file = file;
    }
    const byExtension = {}, unique = new Map();
    for (const record of records) {
      if (!record.parent) {
        const count = byExtension[record.category_hint] ||= {files: 0, bytes: 0};
        count.files++; count.bytes += record.size;
      }
      if (record.size && !record.container && !/\.PSS$/i.test(record.top_file)) unique.set(record.sha256, record);
    }
    const missing = [...unique.values()].filter(r => !r.existing_raw_file);
    return {schema_version: 1, status: 'offline_inventory_not_runtime_recreation',
      source: {iso: path.resolve(isoPath), size: iso.size, sha256: isoHash, volume: iso.volume},
      policy, summary: {disc_files: topFiles.length, records: records.length,
        supported_containers: records.filter(r => r.container).length,
        deferred_containers: issues.length, by_extension: byExtension,
        unique_nonmovie_raw_payloads: unique.size, missing_unique_payloads: missing.length,
        missing_unique_bytes: missing.reduce((n,r) => n + r.size, 0),
        verified_existing_unique_payloads: unique.size - missing.length,
        newly_decoded_assets: 0, newly_recreated_assets: 0, newly_integrated_assets: 0},
      existing_exports: {manifests: existing.manifests, failures: existing.failures},
      issues, records};
  } finally { iso.close(); }
}
function freshOutput(directoryPath, plannedBytes = 0) {
  const output = path.resolve(directoryPath), parent = path.dirname(output);
  assert(fs.realpathSync(parent) === parent, 'output parent must be a real existing directory, not a symlink');
  assert(!fs.existsSync(output), 'refusing to overwrite existing output');
  const stats = fs.statfsSync(parent);
  assert(stats.bavail * stats.bsize - plannedBytes >= policy.minimum_free_bytes, 'free-space reserve would be violated');
  fs.mkdirSync(output);
  fs.writeFileSync(path.join(output, '.gdignore'), '', {flag: 'wx'});
  return output;
}
if (require.main === module) {
  const [iso, output, existingLibrary] = process.argv.slice(2);
  assert(iso && output, 'usage: node tools/source_asset_inventory.cjs ISO NEW_OUTPUT_DIRECTORY [EXISTING_MAP_LIBRARY]');
  assert(!fs.existsSync(output), 'output already exists');
  const result = inventory(iso, existingLibrary, message => console.log(message));
  const data = JSON.stringify(result, null, 2) + '\n';
  const dir = freshOutput(output, Buffer.byteLength(data));
  fs.writeFileSync(path.join(dir, 'catalog.json'), data, {flag: 'wx'});
  console.log('SOURCE_ASSET_INVENTORY ' + JSON.stringify(result.summary));
}
module.exports = {range, hashRange, hashFile, directory, inventory, freshOutput, policy};
