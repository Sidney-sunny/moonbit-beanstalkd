import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:net';
import { getEventListeners } from 'node:events';
import { setTimeout as delay } from 'node:timers/promises';
import test from 'node:test';

// Exercise the exact FFI implementation shipped in the MoonBit package.
const ffi = await readFile(new URL('./transport_ffi.mbt', import.meta.url), 'utf8');
const javascript = ffi.split(/\r?\n/).filter(line => /^\s*#\|/.test(line))
  .map(line => line.replace(/^\s*#\| ?/, '')).join('\n');
const connect = Function(`return (${javascript})`)();
const signal = () => new AbortController().signal;

async function fixture(t, onConnection) {
  const sockets = new Set();
  const server = createServer(socket => {
    sockets.add(socket);
    socket.on('error', () => {});
    socket.on('close', () => sockets.delete(socket));
    onConnection(socket);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => {
    for (const socket of sockets) socket.destroy();
    await new Promise(resolve => server.close(resolve));
  });
  const result = await connect('127.0.0.1', server.address().port, 1000, signal());
  assert.equal(result.code, '');
  t.after(() => result.connection.invalidate('CLOSED', 'test cleanup'));
  return result.connection;
}

test('preserves arbitrary bytes over fragmented real TCP and permits ordered reuse', async t => {
  const payload = Buffer.from([0, 13, 10, 255, 128, 65]);
  let received = Buffer.alloc(0);
  const connection = await fixture(t, socket => {
    socket.on('data', async chunk => {
      received = Buffer.concat([received, chunk]);
      socket.write(payload.subarray(0, 2));
      await delay(15);
      socket.write(payload.subarray(2));
    });
  });
  for (let index = 0; index < 2; index++) {
    const { request, code } = connection.begin(1000);
    assert.equal(code, '');
    assert.equal((await connection.write(request, payload, signal())).code, '');
    let reply = Buffer.alloc(0);
    while (reply.length < payload.length) {
      const result = await connection.read(request, signal());
      assert.equal(result.code, '');
      reply = Buffer.concat([reply, result.bytes]);
    }
    assert.deepEqual(reply, payload);
    assert.equal(connection.finish(request).code, '');
    assert.equal(connection.reader, null);
    assert.equal(connection.socket.listenerCount('drain'), 0);
  }
  assert.deepEqual(received, Buffer.concat([payload, payload]));
});

test('one absolute deadline covers successive reads and invalidates reuse', async t => {
  const connection = await fixture(t, socket => {
    socket.on('data', async () => {
      await delay(35);
      socket.write(Buffer.from([1]));
      await delay(100);
      if (!socket.destroyed) socket.write(Buffer.from([2]));
    });
  });
  const { request } = connection.begin(80);
  const start = performance.now();
  await connection.write(request, Buffer.from([0]), signal());
  assert.equal((await connection.read(request, signal())).code, '');
  assert.equal((await connection.read(request, signal())).code, 'TIMEOUT');
  assert.ok(performance.now() - start < 150);
  assert.equal(connection.closed, true);
  assert.equal(connection.begin(100).code, 'CLOSED');
});

test('truncated peer reply reports EOF and rejects a second request', async t => {
  const connection = await fixture(t, socket => {
    socket.once('data', () => socket.end(Buffer.from('RESERVED 1 5\r\nab')));
  });
  const { request } = connection.begin(1000);
  await connection.write(request, Buffer.from('reserve-with-timeout 0\r\n'), signal());
  const first = await connection.read(request, signal());
  assert.equal(first.code, '');
  assert.equal(Buffer.from(first.bytes).toString(), 'RESERVED 1 5\r\nab');
  assert.equal((await connection.read(request, signal())).code, 'EOF');
  assert.equal(connection.begin(100).code, 'CLOSED');
});

test('cancellation closes the socket and removes operation abort listeners', async t => {
  const connection = await fixture(t, () => {});
  const { request } = connection.begin(1000);
  const controller = new AbortController();
  const pending = connection.read(request, controller.signal);
  assert.equal(getEventListeners(controller.signal, 'abort').length, 1);
  controller.abort();
  assert.equal((await pending).code, 'CANCELLED');
  assert.equal(connection.closed, true);
  assert.equal(getEventListeners(controller.signal, 'abort').length, 0);
  await delay(10);
  for (const listener of ['onReadable', 'onEnd', 'onSocketError', 'onClose', 'onDrain']) {
    assert.equal(connection.socket.eventNames().flatMap(event => connection.socket.listeners(event))
      .some(callback => callback.name === listener), false, listener);
  }
});

test('pre-aborted reads close immediately; stale and foreign tokens are rejected', async t => {
  const connection = await fixture(t, () => {});
  const { request } = connection.begin(1000);
  assert.equal(connection.begin(1000).code, 'BUSY');
  assert.equal((await connection.read({}, signal())).code, 'INVALID_ARGUMENT');
  assert.equal(connection.closed, false);
  const controller = new AbortController();
  controller.abort();
  assert.equal((await connection.read(request, controller.signal)).code, 'CANCELLED');
  assert.equal(getEventListeners(controller.signal, 'abort').length, 0);
});

test('write waits for real socket backpressure and cleans drain listeners', async t => {
  const payload = Buffer.alloc(1024 * 1024, 0xA5);
  let received = 0;
  let socketRef;
  const connection = await fixture(t, socket => {
    socketRef = socket;
    socket.pause();
    socket.on('data', chunk => { received += chunk.length; });
  });
  const { request } = connection.begin(3000);
  let backpressured = false;
  let drainEvents = 0;
  const originalWrite = connection.socket.write;
  connection.socket.write = function(...args) {
    const accepted = originalWrite.apply(this, args);
    backpressured ||= !accepted;
    return accepted;
  };
  const observeDrain = () => { drainEvents++; };
  connection.socket.on('drain', observeDrain);
  // Cork forces the real Writable buffer above its high-water mark on every OS.
  connection.socket.cork();
  const writing = connection.write(request, payload, signal());
  await delay(20);
  socketRef.resume();
  connection.socket.uncork();
  assert.equal((await writing).code, '');
  connection.socket.removeListener('drain', observeDrain);
  assert.equal(backpressured, true);
  assert.ok(drainEvents >= 1);
  assert.equal(connection.socket.listenerCount('drain'), 0);
  for (let tries = 0; received < payload.length && tries < 100; tries++) await delay(5);
  assert.equal(received, payload.length);
  assert.equal(connection.finish(request).code, '');
});

test('connect validates inputs and abort cleanup', async () => {
  assert.equal((await connect('', 1, 100, signal())).code, 'INVALID_ARGUMENT');
  assert.equal((await connect('localhost', 0, 100, signal())).code, 'INVALID_ARGUMENT');
  assert.equal((await connect('localhost', 1, 0, signal())).code, 'INVALID_ARGUMENT');
  const controller = new AbortController();
  controller.abort();
  assert.equal((await connect('localhost', 11300, 100, controller.signal)).code, 'CANCELLED');
  assert.equal(getEventListeners(controller.signal, 'abort').length, 0);
});

test('close settles an in-flight read and clears the deadline', async t => {
  const connection = await fixture(t, () => {});
  const { request } = connection.begin(1000);
  const controller = new AbortController();
  const pending = connection.read(request, controller.signal);
  connection.invalidate('CLOSED', 'explicit close');
  connection.invalidate('CLOSED', 'explicit close twice');
  assert.equal((await pending).code, 'CLOSED');
  assert.equal(connection.active, null);
  assert.equal(getEventListeners(controller.signal, 'abort').length, 0);
});

test('connect cancellation after resolution closes an unclaimed socket', async t => {
  const sockets = new Set();
  const server = createServer(socket => {
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => {
    for (const socket of sockets) socket.destroy();
    await new Promise(resolve => server.close(resolve));
  });
  const controller = new AbortController();
  const result = await connect('127.0.0.1', server.address().port, 1000, controller.signal);
  assert.equal(result.code, '');
  assert.equal(getEventListeners(controller.signal, 'abort').length, 1);
  controller.abort();
  assert.equal(result.connection.closed, true);
  assert.equal(getEventListeners(controller.signal, 'abort').length, 0);
});

test('unsolicited bytes between requests invalidate instead of becoming stale replies', async t => {
  const connection = await fixture(t, socket => {
    socket.once('data', async () => {
      socket.write(Buffer.from('DELETED\r\n'));
      await delay(20);
      if (!socket.destroyed) socket.write(Buffer.from('DELETED\r\n'));
    });
  });
  const { request } = connection.begin(1000);
  await connection.write(request, Buffer.from('delete 1\r\n'), signal());
  assert.equal(Buffer.from((await connection.read(request, signal())).bytes).toString(), 'DELETED\r\n');
  assert.equal(connection.finish(request).code, '');
  await delay(40);
  assert.equal(connection.closed, true);
  assert.equal(connection.begin(1000).code, 'CLOSED');
});
