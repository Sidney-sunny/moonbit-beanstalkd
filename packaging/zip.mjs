import assert from "node:assert/strict";
import { inflateRawSync } from "node:zlib";

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

// Moon's package archives are small, single-disk ZIP files. Reject unsupported
// ZIP64/encryption/symlinks and verify each entry before writing any package file.
export function readPackageZip(archive) {
  assert.ok(archive.length <= 64 * 1024 * 1024, "package archive exceeds 64 MiB");
  let end = archive.length - 22;
  while (end >= Math.max(0, archive.length - 65557) && archive.readUInt32LE(end) !== 0x06054b50) end -= 1;
  assert.ok(end >= 0, "ZIP end record missing");
  assert.equal(archive.readUInt16LE(end + 4), 0, "multi-disk ZIP unsupported");
  assert.equal(archive.readUInt16LE(end + 6), 0, "multi-disk ZIP unsupported");
  const count = archive.readUInt16LE(end + 10);
  assert.equal(archive.readUInt16LE(end + 8), count);
  assert.ok(count < 65535, "ZIP64 unsupported");
  const size = archive.readUInt32LE(end + 12);
  let offset = archive.readUInt32LE(end + 16);
  assert.equal(offset + size, end, "invalid ZIP central directory bounds");
  assert.equal(end + 22 + archive.readUInt16LE(end + 20), archive.length);
  const entries = new Map();
  let total = 0;
  for (let index = 0; index < count; index += 1) {
    assert.equal(archive.readUInt32LE(offset), 0x02014b50, "invalid ZIP entry");
    const flags = archive.readUInt16LE(offset + 8);
    const method = archive.readUInt16LE(offset + 10);
    const expectedCrc = archive.readUInt32LE(offset + 16);
    const compressed = archive.readUInt32LE(offset + 20);
    const expanded = archive.readUInt32LE(offset + 24);
    const nameLength = archive.readUInt16LE(offset + 28);
    const extraLength = archive.readUInt16LE(offset + 30);
    const commentLength = archive.readUInt16LE(offset + 32);
    const attributes = archive.readUInt32LE(offset + 38);
    const local = archive.readUInt32LE(offset + 42);
    const name = archive.subarray(offset + 46, offset + 46 + nameLength).toString("utf8");
    assert.equal(flags & 1, 0, "encrypted ZIP unsupported");
    assert.ok(method === 0 || method === 8, "unsupported ZIP compression");
    assert.notEqual((attributes >>> 16) & 0xf000, 0xa000, "ZIP symlinks forbidden");
    assert.ok(name && !/[\\:\0]/.test(name) && !name.startsWith("/"), "unsafe ZIP path");
    assert.ok(!name.split("/").some(part => part === "." || part === ".."), "unsafe ZIP traversal");
    assert.ok(!entries.has(name), "duplicate ZIP path");
    assert.equal(archive.readUInt32LE(local), 0x04034b50, "invalid local ZIP header");
    const localNameLength = archive.readUInt16LE(local + 26);
    const localExtraLength = archive.readUInt16LE(local + 28);
    assert.equal(archive.subarray(local + 30, local + 30 + localNameLength).toString("utf8"), name);
    const start = local + 30 + localNameLength + localExtraLength;
    assert.ok(start + compressed <= archive.readUInt32LE(end + 16), "invalid ZIP data bounds");
    total += expanded;
    assert.ok(expanded <= 16 * 1024 * 1024 && total <= 64 * 1024 * 1024, "expanded ZIP exceeds limits");
    const data = archive.subarray(start, start + compressed);
    const bytes = method === 0 ? Buffer.from(data) : inflateRawSync(data, { maxOutputLength: Math.max(1, expanded) });
    assert.equal(bytes.length, expanded, "ZIP entry size mismatch");
    assert.equal(crc32(bytes), expectedCrc, "ZIP entry CRC mismatch");
    entries.set(name, bytes);
    offset += 46 + nameLength + extraLength + commentLength;
  }
  assert.equal(offset, end, "ZIP central directory size mismatch");
  return entries;
}
