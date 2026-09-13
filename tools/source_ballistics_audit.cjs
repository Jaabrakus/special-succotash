'use strict';
// Offline, lossless research export. Never writes the ISO or runtime profiles.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const {isoFile, reader, pairs, extract} = require('./socom2_weapon_reference.cjs');
const {archive} = require('./socom_geometry/archive.cjs');
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const ROOT = path.resolve(__dirname, '..');

// Preserve ordered tag/list fields and every non-pair atom at its exact index.
// Unlike object conversion, duplicate tags also remain lossless and explicit.
function taggedBlock(row, context) {
  assert(Array.isArray(row));
  const fields = [], unparsed_atoms = [];
  for (let index = 0; index < row.length; index++) {
    if (typeof row[index] === 'string' && Array.isArray(row[index + 1])) {
      fields.push({index, tag: row[index], values: row[++index]});
    } else unparsed_atoms.push({context, index, value: row[index]});
  }
  const reconstructed = [];
  for (const item of fields) { reconstructed[item.index] = item.tag; reconstructed[item.index + 1] = item.values; }
  for (const item of unparsed_atoms) reconstructed[item.index] = item.value;
  assert.deepEqual(reconstructed, row, 'lossless tagged row reconstruction');
  return {context, fields, unparsed_atoms};
}

function record(row, section, index) {
  const context = `${section}[${index}]`;
  const top = taggedBlock(row, context);
  const name = top.fields.find(f => f.tag === 'InternalName')?.values?.[0] ?? null;
  const nested = [];
  function visit(array, at) {
    if (array.some((v, i) => typeof v === 'string' && Array.isArray(array[i + 1]))) {
      nested.push(taggedBlock(array, at));
    }
    array.forEach((value, i) => { if (Array.isArray(value)) visit(value, `${at}[${i}]`); });
  }
  row.forEach((value, i) => { if (Array.isArray(value)) visit(value, `${context}[${i}]`); });
  return {name, index, raw_row: row, ...top, nested_tagged_blocks: nested};
}

function reconstructionInventory() {
  const prefix = 'reCOM-main/src/gamez/zWeapon/';
  const files = ['zweapon.h', 'zwep_projectile.cpp', 'zwep_weapon.cpp', 'zwep_ammo.cpp', 'zwep_explosive.cpp', 'zwep_global.cpp'];
  const commit = cp.execFileSync('git', ['rev-parse', 'HEAD'], {cwd: ROOT, encoding: 'utf8'}).trim();
  return {
    status: 'Incomplete community reconstruction, not verified SOCOM II executable equations',
    commit,
    files: files.map(name => {
      const gitPath = prefix + name;
      const text = cp.execFileSync('git', ['show', `${commit}:${gitPath}`], {cwd: ROOT, encoding: 'utf8'});
      const localPath = '/Users/kiwimango/Documents/socom-tactical-ops/' + gitPath;
      const lines = text.split('\n');
      return {path: gitPath, git_object: `${commit}:${gitPath}`, sha256: sha(text),
        local_copy_path: localPath, local_copy_matches: fs.existsSync(localPath) ? sha(fs.readFileSync(localPath)) === sha(text) : null,
        defined_symbols_including_stubs: [...text.matchAll(/^[\w:*&<>]+\s+(CZ\w+::\w+)\s*\(/gm)].map(m => m[1]),
        evidence_lines: lines.flatMap((line, i) => /velscale\.Scale|m_vel\.Add|m_currange =|GetMuzzleVelocity|GetMaxRange|ONE_FRAME|TODO|CZProjectile::|IsDirectFire\(\)|m_accelerationFactor|IsValidFire|GetZoomRange/.test(line) ? [{line: i + 1, text: line}] : []),
      };
    }),
    available_fragment: 'SetProjectile initializes velocity = velscale * weapon muzzle velocity + supplied velocity. Argument meaning/units and per-tick integration are not established.',
    not_recovered: ['SOCOM II executable-matched trajectory update', 'gravity/drag application and timestep', 'hitscan-versus-flyout behavior', 'reticle/bloom-to-angle dispersion equation', 'shotgun spread pattern', 'range-dependent damage and penetration equations'],
  };
}

function audit(iso, includeReconstruction = true) {
  const zar = isoFile(iso, ['RUN', 'ZWEAPON.ZAR']);
  const matches = archive(zar).entries.filter(e => e.name === 'zweapon.rdr');
  assert.equal(matches.length, 1);
  const entry = matches[0];
  const bytes = zar.subarray(entry.offset, entry.offset + entry.size);
  const decoded_root = reader(bytes); // Existing reader requires complete node-byte coverage.
  const root = pairs(decoded_root);
  const legacy = extract(iso);
  const existing = JSON.parse(fs.readFileSync(path.join(ROOT, 'config/reference/socom2_weapon_settings.json'), 'utf8'));
  assert.deepEqual(legacy, existing, 'existing reference and its metadata stay byte-value equivalent');
  assert.equal(sha(zar), existing.source.archive_sha256);
  assert.equal(sha(bytes), existing.source.reader_sha256);
  const weapons = root.ZWEAPON.map((r, i) => record(r, 'ZWEAPON', i));
  const ammunition = root.ZAMMO.map((r, i) => record(r, 'ZAMMO', i));
  const globals = taggedBlock(root.WEAPON_GLOBAL, 'WEAPON_GLOBAL');
  const inventory = Object.create(null);
  for (const r of [...weapons, ...ammunition]) {
    for (const block of [r, ...r.nested_tagged_blocks]) {
      for (const f of block.fields) {
        const item = inventory[f.tag] ??= {occurrences: 0, examples: []};
        item.occurrences++;
        if (item.examples.length < 3) item.examples.push({record: r.name, context: block.context, values: f.values});
      }
    }
  }
  const candidateTags = Object.keys(inventory).filter(tag => /velocity|range|gravity|acceleration|projectile|impact|blowback|drag|spread|scatter|dilat|constrict|accscalar|accburst|sniper/i.test(tag));
  const unparsed_atoms = [globals, ...weapons, ...ammunition, ...weapons.flatMap(r => r.nested_tagged_blocks), ...ammunition.flatMap(r => r.nested_tagged_blocks)].flatMap(b => b.unparsed_atoms);
  const result = {schema_version: 1, source: existing.source,
    status: 'Lossless decoded data only; source units and full executable ballistics equations are not recovered',
    reader_bytes: bytes.length, decoded_root, globals, weapons, ammunition, field_inventory: inventory,
    trajectory_candidate_tags: candidateTags,
    gravity_named_tags_found: Object.keys(inventory).filter(tag => /gravity|drag/i.test(tag)),
    unparsed_atoms,
    checks: {legacy_reference_identical: true, complete_reader_node_coverage: true, all_tagged_rows_reconstruct_exactly: true,
      weapon_records: weapons.length, ammunition_records: ammunition.length, explicit_tag_names: Object.keys(inventory).length,
      malformed_loose_atoms_preserved: unparsed_atoms.length},
  };
  if (includeReconstruction) result.reconstructed_source = reconstructionInventory();
  return result;
}

function selfTest() {
  const fixture = ['Muzzle_Velocity', [340], 'from', 40, 'ModelName', ['pistol'], 'Flag', [], 'Nested', ['Field', [2], 0], 'ModelName', ['duplicate preserved']];
  const result = record(fixture, 'TEST', 0);
  assert.equal(result.fields.length, 5);
  assert.deepEqual(result.unparsed_atoms.map(a => a.value), ['from', 40]);
  assert.equal(result.nested_tagged_blocks[0].unparsed_atoms[0].value, 0);
  assert.equal(result.fields.filter(f => f.tag === 'ModelName').length, 2);
  assert.throws(() => reader(Buffer.alloc(12)));
  console.log('SOURCE_BALLISTICS_AUDIT_SELF_TEST PASS');
}

if (require.main === module) {
  if (process.argv[2] === '--self-test') selfTest();
  else {
    const [iso, output] = process.argv.slice(2);
    assert(iso && output, 'usage: node tools/source_ballistics_audit.cjs game.iso NEW_REPORT.json');
    assert(!fs.existsSync(output), 'refuse to overwrite any existing report');
    const report = audit(iso);
    fs.mkdirSync(path.dirname(output), {recursive: true});
    fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n', {flag: 'wx'});
    console.log('SOURCE_BALLISTICS_AUDIT PASS ' + JSON.stringify({...report.checks, source: report.source, trajectory_candidate_tags: report.trajectory_candidate_tags, gravity_named_tags_found: report.gravity_named_tags_found, output}));
  }
}
module.exports = {audit, taggedBlock, record};
