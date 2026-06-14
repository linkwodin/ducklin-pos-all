"use strict";

const fs = require("fs");
const path = require("path");

const assetsDir = path.join(__dirname, "..", "assets");
const libAssets = path.join(__dirname, "..", "lib", "assets");

if (!fs.existsSync(assetsDir)) {
  console.error("Run sync-playbook first; missing", assetsDir);
  process.exit(1);
}
fs.mkdirSync(libAssets, { recursive: true });
for (const name of fs.readdirSync(assetsDir)) {
  fs.copyFileSync(path.join(assetsDir, name), path.join(libAssets, name));
}
console.log("Copied assets to lib/assets");
