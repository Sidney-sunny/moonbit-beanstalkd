///|
/// The bridge is embedded so compiled consumers need no runtime file copying.
extern "js" fn raw_connect(
  host : String,
  port : Int32,
  timeout_ms : Int32,
  signal : @js_async.AbortSignal,
) -> @js_async.Promise[Outcome] =
  #| (host, port, timeoutMs, signal) => {
  #|   const ok = (extra = {}) => ({ code: "", message: "", ...extra });
  #|   const fail = (code, message) => ({ code, message });
  #|   const validTimeout = value => Number.isInteger(value) && value > 0 && value <= 2147483647;
  #|   if (typeof host !== "string" || host.length === 0 || !Number.isInteger(port) || port < 1 || port > 65535 || !validTimeout(timeoutMs)) {
  #|     return Promise.resolve(fail("INVALID_ARGUMENT", "host, port or timeout is invalid"));
  #|   }
  #|   return new Promise(resolve => {
  #|     let socket;
  #|     let done = false;
  #|     const deadline = performance.now() + timeoutMs;
  #|     const cleanup = () => {
  #|       clearTimeout(timer);
  #|       signal.removeEventListener("abort", onAbort);
  #|       if (socket) {
  #|         socket.removeListener("error", onError);
  #|         socket.removeListener("connect", onConnect);
  #|       }
  #|     };
  #|     const settle = result => {
  #|       if (done) return;
  #|       done = true;
  #|       cleanup();
  #|       if (result.code && socket) {
  #|         const ignoreError = () => {};
  #|         socket.on("error", ignoreError);
  #|         socket.once("close", () => socket.removeListener("error", ignoreError));
  #|         socket.destroy();
  #|       }
  #|       resolve(result);
  #|     };
  #|     const onAbort = () => settle(fail("CANCELLED", "connection cancelled"));
  #|     const onError = error => settle(fail("IO", error.message));
  #|     const timer = setTimeout(() => settle(fail("TIMEOUT", "connection deadline exceeded")), timeoutMs);
  #|     const onConnect = () => {
  #|       if (performance.now() >= deadline) {
  #|         settle(fail("TIMEOUT", "connection deadline exceeded"));
  #|         return;
  #|       }
  #|       let releaseClaim = () => {};
  #|       const connection = {
  #|         socket,
  #|         closed: false,
  #|         ended: false,
  #|         active: null,
  #|         pending: null,
  #|         terminal: null,
  #|         invalidate(code, message) {
  #|           if (this.closed) return;
  #|           this.closed = true;
  #|           releaseClaim();
  #|           this.terminal = fail(code, message);
  #|           if (this.active) clearTimeout(this.active.timer);
  #|           this.active = null;
  #|           if (this.pending) this.pending(this.terminal);
  #|           socket.removeListener("readable", onReadable);
  #|           socket.removeListener("end", onEnd);
  #|           socket.destroy();
  #|         },
  #|         validate(request) {
  #|           if (this.closed) return fail("CLOSED", this.terminal.message);
  #|           if (!request || request.owner !== this || request !== this.active) return fail("INVALID_ARGUMENT", "request token is stale or belongs to another connection");
  #|           if (performance.now() >= request.deadline) {
  #|             this.invalidate("TIMEOUT", "request deadline exceeded");
  #|             return this.terminal;
  #|           }
  #|           return null;
  #|         },
  #|         begin(duration) {
  #|           if (this.closed) return fail("CLOSED", this.terminal.message);
  #|           if (!validTimeout(duration)) return fail("INVALID_ARGUMENT", "timeout must be an integer from 1 to 2147483647 milliseconds");
  #|           if (this.active) return fail("BUSY", "one ordered request is already active");
  #|           if (socket.readableLength > 0) {
  #|             this.invalidate("IO", "unsolicited bytes before request");
  #|             return this.terminal;
  #|           }
  #|           const request = { owner: this, deadline: performance.now() + duration };
  #|           this.active = request;
  #|           request.timer = setTimeout(() => this.invalidate("TIMEOUT", "request deadline exceeded"), duration);
  #|           return ok({ request });
  #|         },
  #|         operation(request, abortSignal, start) {
  #|           const error = this.validate(request);
  #|           if (error) return Promise.resolve(error);
  #|           if (this.pending) return Promise.resolve(fail("BUSY", "a transport operation is already pending"));
  #|           return new Promise(complete => {
  #|             let cleanupOperation = () => {};
  #|             const settleOperation = result => {
  #|               if (this.pending !== settleOperation) return;
  #|               this.pending = null;
  #|               abortSignal.removeEventListener("abort", abort);
  #|               cleanupOperation();
  #|               complete(result);
  #|             };
  #|             const abort = () => this.invalidate("CANCELLED", "request cancelled");
  #|             this.pending = settleOperation;
  #|             abortSignal.addEventListener("abort", abort, { once: true });
  #|             if (abortSignal.aborted) {
  #|               abort();
  #|               return;
  #|             }
  #|             try {
  #|               cleanupOperation = start(settleOperation) || (() => {});
  #|               if (this.pending !== settleOperation) cleanupOperation();
  #|             } catch (error) {
  #|               this.invalidate("IO", error.message);
  #|             }
  #|           });
  #|         },
  #|         read(request, abortSignal) {
  #|           return this.operation(request, abortSignal, settleRead => {
  #|             this.reader = () => {
  #|               const error = this.validate(request);
  #|               if (error) { settleRead(error); return; }
  #|               const length = Math.min(socket.readableLength, 65536);
  #|               const chunk = length > 0 ? socket.read(length) : null;
  #|               if (chunk) {
  #|                 settleRead(ok({ bytes: new Uint8Array(chunk) }));
  #|               } else if (this.ended || socket.destroyed) {
  #|                 this.invalidate("EOF", "peer disconnected before response completed");
  #|               }
  #|             };
  #|             this.reader();
  #|             return () => { this.reader = null; };
  #|           });
  #|         },
  #|         write(request, bytes, abortSignal) {
  #|           return this.operation(request, abortSignal, settleWrite => {
  #|             let callbackDone = false;
  #|             let drained = false;
  #|             let returned = false;
  #|             const maybeDone = () => {
  #|               if (!returned || !callbackDone || !drained) return;
  #|               const error = this.validate(request);
  #|               settleWrite(error || ok());
  #|             };
  #|             const onDrain = () => { drained = true; maybeDone(); };
  #|             socket.on("drain", onDrain);
  #|             try {
  #|               const accepted = socket.write(Buffer.from(bytes), error => {
  #|                 if (error) this.invalidate("IO", error.message);
  #|                 else { callbackDone = true; maybeDone(); }
  #|               });
  #|               drained = accepted || drained;
  #|               returned = true;
  #|               maybeDone();
  #|             } catch (error) {
  #|               socket.removeListener("drain", onDrain);
  #|               throw error;
  #|             }
  #|             return () => socket.removeListener("drain", onDrain);
  #|           });
  #|         },
  #|         finish(request) {
  #|           const error = this.validate(request);
  #|           if (error) return error;
  #|           if (this.pending) return fail("BUSY", "a transport operation is still pending");
  #|           if (socket.readableLength > 0) {
  #|             this.invalidate("IO", "unconsumed bytes after response");
  #|             return this.terminal;
  #|           }
  #|           clearTimeout(request.timer);
  #|           this.active = null;
  #|           return ok();
  #|         }
  #|       };
  #|       const onReadable = () => {
  #|         if (!connection.active && socket.readableLength > 0) connection.invalidate("IO", "unsolicited bytes outside request");
  #|         else if (connection.reader) connection.reader();
  #|       };
  #|       const onEnd = () => { connection.ended = true; if (connection.reader) connection.reader(); };
  #|       const onSocketError = error => connection.invalidate("IO", error.message);
  #|       const onClose = () => {
  #|         connection.invalidate("EOF", "peer disconnected");
  #|         socket.removeListener("error", onSocketError);
  #|         socket.removeListener("close", onClose);
  #|       };
  #|       socket.on("readable", onReadable);
  #|       socket.on("end", onEnd);
  #|       socket.on("error", onSocketError);
  #|       socket.on("close", onClose);
  #|       // Keep ownership guarded if cancellation wins after promise resolution
  #|       // but before MoonBit resumes and claims the newly opened resource.
  #|       const abortUnclaimed = () => connection.invalidate("CANCELLED", "connection cancelled before ownership was claimed");
  #|       releaseClaim = () => signal.removeEventListener("abort", abortUnclaimed);
  #|       signal.addEventListener("abort", abortUnclaimed, { once: true });
  #|       settle({ code: "", message: "", get connection() { releaseClaim(); return connection; } });
  #|     };
  #|     signal.addEventListener("abort", onAbort, { once: true });
  #|     if (signal.aborted) { onAbort(); return; }
  #|     import("node:net").then(net => {
  #|       if (done) return;
  #|       if (performance.now() >= deadline) { settle(fail("TIMEOUT", "connection deadline exceeded")); return; }
  #|       socket = new net.Socket({ readableHighWaterMark: 65536 });
  #|       socket.setNoDelay(true);
  #|       socket.once("error", onError);
  #|       socket.once("connect", onConnect);
  #|       socket.connect({ host, port });
  #|     }).catch(onError);
  #|   });
  #| }
