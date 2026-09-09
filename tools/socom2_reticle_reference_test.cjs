'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const crypto = require('node:crypto');
const {extract, zdb} = require('./socom2_reticle_reference.cjs');
const root = require('node:path').resolve(__dirname, '..');
const read = p => JSON.parse(fs.readFileSync(root + '/' + p));
const config = read('config/reticle_presentation.json');
const manifest = read('assets/ui/socom2_reticle/manifest.json');
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
assert.equal(manifest.images.length, 7);
for (const image of manifest.images) {
  assert.equal(sha(fs.readFileSync(root + '/assets/ui/socom2_reticle/' + image.name + '.png')), image.png_sha256);
}
for (const family of Object.values(config.families)) {
  const image = manifest.images.find(i => i.name + '.png' === family.floating);
  const [x,y,w,h] = family.region;
  assert(x>=0 && y>=0 && w>0 && h>0 && x+w<=image.width && y+h<=image.height);
  assert(manifest.images.some(i => i.name + '.png' === family.base));
}
assert.throws(() => zdb(Buffer.alloc(159)), /unsupported/);
const bad = Buffer.alloc(252);
bad.writeUInt32LE(252,0); bad.writeUInt32LE(1,4);
bad.writeUInt32LE(1,152); bad.writeUInt32LE(92,156); bad.writeUInt32LE(92,160);
bad.write('test',164); bad.writeUInt32LE(252,228); bad.writeUInt32LE(1,232);
assert.throws(() => zdb(bad)); // Entry claims data beyond the file.
if (process.argv[2]) {
  const source = extract(process.argv[2]);
  assert.deepEqual(source.source, manifest.source);
  for (const image of source.images) {
    const expected = manifest.images.find(i => i.name === image.name);
    assert.equal(image.rgba_sha256, expected.rgba_sha256);
    assert.equal(image.png_sha256, expected.png_sha256);
    const family = Object.values(config.families).find(f => f.floating === image.name + '.png');
    if (!family) continue;
    const [x,y,w,h] = family.region;
    let visible = 0;
    for (let py=0; py<image.height; py++) for (let px=0; px<image.width; px++) {
      if (!image.rgba[(py*image.width+px)*4+3]) continue;
      visible++;
      assert(px>=x && px<x+w && py>=y && py<y+h, image.name + ' crop loses source pixels');
    }
    assert(visible>0, image.name + ' is not transparent');
  }
}
console.log('SOCOM2_RETICLE_REFERENCE PASS: 7 images, bounded regions/container, ISO=' + Boolean(process.argv[2]));
