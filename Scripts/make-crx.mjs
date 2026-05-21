#!/usr/bin/env node
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { createHash, createPrivateKey, createPublicKey, generateKeyPairSync, sign } from "node:crypto";
import { basename } from "node:path";

const [, , zipPath, crxPath] = process.argv;

if (!zipPath || !crxPath) {
  console.error("Usage: make-crx.mjs <extension.zip> <output.crx>");
  process.exit(64);
}

if (!existsSync(zipPath)) {
  console.error(`Missing extension zip: ${zipPath}`);
  process.exit(66);
}

const archive = readFileSync(zipPath);
const { privateKey, keySource } = loadPrivateKey();
const publicKey = createPublicKey(privateKey).export({
  format: "der",
  type: "spki"
});
const crxID = createHash("sha256").update(publicKey).digest().subarray(0, 16);
const signedHeaderData = protobufMessage([
  bytesField(1, crxID)
]);
const signedHeaderSize = Buffer.alloc(4);
signedHeaderSize.writeUInt32LE(signedHeaderData.length, 0);
const signedPayload = Buffer.concat([
  Buffer.from("CRX3 SignedData\0", "utf8"),
  signedHeaderSize,
  signedHeaderData,
  archive
]);
const signature = sign("sha256", signedPayload, {
  key: privateKey,
  padding: 6,
  saltLength: 32
});
const keyProof = protobufMessage([
  bytesField(1, publicKey),
  bytesField(2, signature)
]);
const header = protobufMessage([
  bytesField(2, keyProof),
  bytesField(10000, signedHeaderData)
]);
const computedExtensionID = extensionID(crxID);
const expectedExtensionID = process.env.SWIFTGETX_EXPECTED_CHROME_EXTENSION_ID
  || process.env.CHROME_EXTENSION_ID
  || "";
if (expectedExtensionID && computedExtensionID !== expectedExtensionID.trim().toLowerCase()) {
  console.error(`CRX ID mismatch: expected ${expectedExtensionID}, got ${computedExtensionID}`);
  process.exit(65);
}

const fileHeader = Buffer.alloc(12);
fileHeader.write("Cr24", 0, "ascii");
fileHeader.writeUInt32LE(3, 4);
fileHeader.writeUInt32LE(header.length, 8);
writeFileSync(crxPath, Buffer.concat([fileHeader, header, archive]));

if (process.env.SWIFTGETX_CHROME_EXTENSION_ID_FILE) {
  writeFileSync(process.env.SWIFTGETX_CHROME_EXTENSION_ID_FILE, `${computedExtensionID}\n`);
}

console.log(`CRX ID: ${computedExtensionID}`);
console.log(`Key: ${keySource}`);
console.log(`Input: ${basename(zipPath)}`);
console.log(`Output: ${basename(crxPath)}`);

function loadPrivateKey() {
  if (process.env.SWIFTGETX_CHROME_EXTENSION_KEY_BASE64) {
    return {
      privateKey: createPrivateKey(
        Buffer.from(process.env.SWIFTGETX_CHROME_EXTENSION_KEY_BASE64, "base64")
      ),
      keySource: "SWIFTGETX_CHROME_EXTENSION_KEY_BASE64"
    };
  }

  if (process.env.SWIFTGETX_CHROME_EXTENSION_KEY_PATH) {
    return {
      privateKey: createPrivateKey(readFileSync(process.env.SWIFTGETX_CHROME_EXTENSION_KEY_PATH)),
      keySource: process.env.SWIFTGETX_CHROME_EXTENSION_KEY_PATH
    };
  }

  const generated = generateKeyPairSync("rsa", {
    modulusLength: 2048,
    privateKeyEncoding: {
      format: "pem",
      type: "pkcs8"
    },
    publicKeyEncoding: {
      format: "pem",
      type: "spki"
    }
  });

  return {
    privateKey: createPrivateKey(generated.privateKey),
    keySource: "temporary generated key"
  };
}

function protobufMessage(fields) {
  return Buffer.concat(fields);
}

function bytesField(fieldNumber, value) {
  return Buffer.concat([
    varint((fieldNumber << 3) | 2),
    varint(value.length),
    Buffer.from(value)
  ]);
}

function varint(value) {
  const bytes = [];
  let remaining = value;

  while (remaining > 0x7f) {
    bytes.push((remaining & 0x7f) | 0x80);
    remaining >>>= 7;
  }

  bytes.push(remaining);
  return Buffer.from(bytes);
}

function extensionID(crxID) {
  return [...crxID]
    .map((byte) => `${nibbleToIDChar(byte >> 4)}${nibbleToIDChar(byte & 0x0f)}`)
    .join("");
}

function nibbleToIDChar(nibble) {
  return String.fromCharCode("a".charCodeAt(0) + nibble);
}
