// MBCH v1 block container. Metadata is checked but not BCH protected.
pub(all) struct Recovered {
  data : Array[Int]
  corrected_bits : Int
  corrected_blocks : Int
}

pub fn crc32(bytes : Array[Int]) -> UInt {
  let mut crc = 0xffffffffU
  for b in bytes {
    crc = crc ^ b.to_uint()
    for _ in 0..<8 { crc = if (crc & 1U) != 0U { (crc >> 1) ^ 0xedb88320U } else { crc >> 1 } }
  }
  crc ^ 0xffffffffU
}

fn push_u32(out : Array[Int], value : UInt) -> Unit {
  for i in 0..<4 { out.push(((value >> (8 * i)) & 255U).to_int()) }
}

fn read_u32(bytes : Array[Int], at : Int) -> UInt {
  let mut out = 0U
  for i in 0..<4 { out = out | (bytes[at + i].to_uint() << (8 * i)) }
  out
}

pub fn protect(data : Array[Int], m : Int, t : Int) -> Array[Int] raise BchError {
  if data.length() > 65536 { raise InvalidLength }
  let code = Bch::new(m, t)
  let count = (data.length() * 8 + code.k - 1) / code.k
  if count.to_int64() * code.n.to_int64() > 1048576L { raise InvalidLength }
  let bits = bits_of_bytes(data)
  let encoded : Array[Int] = []
  let mut pos = 0
  while pos < bits.length() {
    let message = Array::make(code.k, 0)
    for j in 0..<code.k { if pos + j < bits.length() { message[j] = bits[pos + j] } }
    for bit in code.encode(message) { encoded.push(bit) }
    pos = pos + code.k
  }
  let out = [77, 66, 67, 72, 1, m, t, 0]
  push_u32(out, data.length().to_uint())
  push_u32(out, crc32(data))
  for b in bytes_of_bits(encoded) { out.push(b) }
  out
}

pub fn recover(frame : Array[Int]) -> Recovered raise BchError {
  if frame.length() < 16 || frame.length() > 131088 { raise InvalidFrame }
  for b in frame { if b < 0 || b > 255 { raise InvalidFrame } }
  if frame[0] != 77 || frame[1] != 66 || frame[2] != 67 || frame[3] != 72 || frame[4] != 1 || frame[7] != 0 { raise InvalidFrame }
  let code = Bch::new(frame[5], frame[6])
  let size = read_u32(frame, 8)
  if size > 65536U { raise InvalidFrame }
  let count = (size.to_int() * 8 + code.k - 1) / code.k
  let total = count.to_int64() * code.n.to_int64()
  if total > 1048576L { raise InvalidFrame }
  if (total + 7L) / 8L + 16L != frame.length().to_int64() { raise InvalidFrame }
  let mut corrected_bits = 0
  let mut corrected_blocks = 0
  let bits : Array[Int] = []
  for block in 0..<count {
    let word = Array::make(code.n, 0)
    for j in 0..<code.n {
      let bit = block * code.n + j
      word[j] = (frame[16 + bit / 8] >> (7 - bit % 8)) & 1
    }
    let result = code.decode(word)
    if result.corrected_positions.length() > 0 { corrected_blocks = corrected_blocks + 1 }
    corrected_bits = corrected_bits + result.corrected_positions.length()
    for bit in result.message { bits.push(bit) }
  }
  for i in (size.to_int() * 8)..<bits.length() { if bits[i] != 0 { raise InvalidFrame } }
  for bit in total.to_int()..<(8 * (frame.length() - 16)) {
    if ((frame[16 + bit / 8] >> (7 - bit % 8)) & 1) != 0 { raise InvalidFrame }
  }
  let data = Array::make(size.to_int(), 0)
  for i in 0..<(size.to_int() * 8) { data[i / 8] = data[i / 8] | (bits[i] << (7 - i % 8)) }
  if crc32(data) != read_u32(frame, 12) { raise ChecksumMismatch }
  { data, corrected_bits, corrected_blocks }
}
