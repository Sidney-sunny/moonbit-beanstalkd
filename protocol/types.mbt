///|
/// A Beanstalkd wire command. Bodies remain opaque bytes; numeric fields never
/// pass through signed integers or JavaScript numbers.
pub(all) enum Command {
  Use(String)
  Watch(String)
  Ignore(String)
  Put(UInt32, UInt32, UInt32, Bytes)
  ReserveWithTimeout(UInt32)
  Delete(UInt64)
  Release(UInt64, UInt32, UInt32)
  Bury(UInt64, UInt32)
  Kick(UInt32)
  KickJob(UInt64)
  Touch(UInt64)
  Peek(UInt64)
  PeekReady
  PeekDelayed
  PeekBuried
  Stats
  StatsJob(UInt64)
  StatsTube(String)
  ListTubes
  ListTubeUsed
  ListTubesWatched
} derive(Eq, @debug.Debug)

///|
pub extend Command with Eq::{equal, not_equal}

///|
pub extend Command with @debug.Debug::{to_repr}

///|
/// Expected server replies, including unsuccessful job operations. These are
/// distinct from malformed wire input and transport failures.
pub(all) enum ServerStatus {
  Deleted
  Released
  Buried
  Kicked
  Touched
  TimedOut
  DeadlineSoon
  NotFound
  NotIgnored
  JobTooBig
  Draining
  ExpectedCrlf
  OutOfMemory
  InternalError
  BadFormat
  UnknownCommand
} derive(Eq, @debug.Debug)

///|
pub extend ServerStatus with Eq::{equal, not_equal}

///|
pub extend ServerStatus with @debug.Debug::{to_repr}

///|
/// Exactly one decoded wire reply. OK bodies contain the server's YAML bytes;
/// use parse_stats or parse_tubes to read the documented subset.
pub(all) enum Reply {
  Inserted(UInt64)
  Buried(UInt64)
  Reserved(UInt64, Bytes)
  Found(UInt64, Bytes)
  Using(String)
  Watching(UInt64)
  Kicked(UInt64)
  Ok(Bytes)
  Status(ServerStatus)
} derive(Eq, @debug.Debug)

///|
pub extend Reply with Eq::{equal, not_equal}

///|
pub extend Reply with @debug.Debug::{to_repr}

///|
/// Local validation and framing failures. A decoder becomes unusable after
/// any framing failure; create a new decoder for a new connection.
pub(all) enum ProtocolError {
  InvalidTube(String)
  InvalidLimits
  HeaderTooLong(Int32)
  BodyTooLarge(UInt64)
  BufferTooLarge(Int32)
  MalformedHeader(String)
  IntegerOverflow(String)
  InvalidCrlf
  Truncated
  InvalidYaml(String)
} derive(Eq, @debug.Debug)

///|
pub extend ProtocolError with Eq::{equal, not_equal}

///|
pub extend ProtocolError with @debug.Debug::{to_repr}
