///|
extern "js" fn setting(
  name : String,
  fallback : Int32,
  maximum : Int32,
) -> Int32 =
  #| (name, fallback, maximum) => {
  #|   const value = Number(process.env[name] ?? fallback);
  #|   if (!Number.isInteger(value) || value < 0 || value > maximum) throw new Error(`Invalid ${name}`);
  #|   return value;
  #| }

///|
extern "js" fn body_bytes() -> Bytes =
  #| () => {
  #|   const hex = process.env.BEANSTALKD_BENCH_BODY_HEX ?? "6d6f6f6e000d0a6265616eff80fe";
  #|   if (!/^(?:[0-9a-f]{2})*$/.test(hex) || hex.length > 8192) throw new Error("Invalid benchmark body");
  #|   return Uint8Array.from(Buffer.from(hex, "hex"));
  #| }

///|
extern "js" fn reply_bytes(body : Bytes) -> Bytes =
  #| body => Uint8Array.from(Buffer.concat([
  #|   Buffer.from(`RESERVED 18446744073709551615 ${body.length}\r\n`),
  #|   body, Buffer.from("\r\n"),
  #| ]))

///|
extern "js" fn now() -> Double =
  #| () => performance.now()

///|
extern "js" fn report(
  encode_ms : Double,
  decode_ms : Double,
  checksum : Int32,
  iterations : Int32,
  warmup : Int32,
  body : Bytes,
  encoded_bytes : Int32,
  reply : Bytes,
) -> Unit =
  #| (encode_ms, decode_ms, checksum, iterations, warmup, body, encoded_bytes, reply) => {
  #|   console.log(JSON.stringify({ encode_ms, decode_ms, checksum, iterations, warmup,
  #|     body_hex: Buffer.from(body).toString("hex"), encoded_bytes, reply_bytes: reply.length }));
  #| }

///|
fn encode_one(body : Bytes) -> Int32 raise {
  match @protocol.encode(@protocol.Put(4294967295U, 0U, 30U, body)) {
    Ok(bytes) => bytes.length()
    Err(_) => fail("benchmark command encoding failed")
  }
}

///|
fn decode_one(reply : Bytes, body : Bytes) -> Int32 raise {
  let decoder = @protocol.Decoder::new()
  assert_eq(decoder.feed(reply), Ok(()))
  match decoder.take() {
    Ok(Some(Reserved(id, actual))) => {
      assert_eq(id, 18446744073709551615UL)
      assert_eq(actual, body)
    }
    _ => fail("benchmark reply decoding failed")
  }
  assert_eq(decoder.finish(), Ok(()))
  body.length()
}

///|
fn main raise {
  let iterations = setting("BEANSTALKD_BENCH_ITERATIONS", 20000, 100000)
  assert_true(iterations > 0)
  let warmup = setting("BEANSTALKD_BENCH_WARMUP", 2000, 20000)
  let body = body_bytes()
  let reply = reply_bytes(body)
  let encoded_bytes = encode_one(body)
  let mut checksum = 0
  for _ in 0..<warmup {
    checksum += encode_one(body) + decode_one(reply, body)
  }
  let started_encode = now()
  for _ in 0..<iterations {
    checksum += encode_one(body)
  }
  let encode_ms = now() - started_encode
  let started_decode = now()
  for _ in 0..<iterations {
    checksum += decode_one(reply, body)
  }
  let decode_ms = now() - started_decode
  report(
    encode_ms, decode_ms, checksum, iterations, warmup, body, encoded_bytes, reply,
  )
}
