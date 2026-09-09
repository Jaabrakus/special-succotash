'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {extract}=require('./textures.cjs'),{convert}=require('./convert.cjs');
const [source,out]=process.argv.slice(2);assert(source&&out&&!fs.existsSync(out),'source map and fresh output directory required');
const textureDirectory=path.join(out,'textures'),report=extract(source,textureDirectory);
convert(source,path.join(out,'models'),{textureDirectory,alphaTextures:new Set(report.decoded.filter(t=>t.alpha).map(t=>t.name)),modelFilter:/fern|bush|tree|vine|waterplant/i});
