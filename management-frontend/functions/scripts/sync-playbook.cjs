"use strict";

const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..", "..", "..");
const src = path.join(root, "docs", "ai-playbook-wholesale-po-to-order.md");
const destDir = path.join(__dirname, "..", "assets");
const dest = path.join(destDir, "ai-playbook-wholesale-po-to-order.md");

if (!fs.existsSync(src)) {
  console.error("Missing source playbook:", src);
  process.exit(1);
}
fs.mkdirSync(destDir, { recursive: true });
fs.copyFileSync(src, dest);
console.log("Synced playbook to", dest);
