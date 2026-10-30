pub(all) suberror BchError {
  InvalidParameters
  InvalidBit(Int)
  InvalidLength
  Uncorrectable
  InvalidFrame
  ChecksumMismatch
}

// Internal field tables cannot be mutated by consumers.
pub struct Bch {
  n : Int
  k : Int
  t : Int
  m : Int
  exp : Array[Int]
  log : Array[Int]
  generator : Array[Int]
}

pub(all) struct Decoded {
  message : Array[Int]
  codeword : Array[Int]
  corrected_positions : Array[Int]
}

pub fn Bch::length(self : Bch) -> Int { self.n }
pub fn Bch::capacity(self : Bch) -> Int { self.k }
pub fn Bch::strength(self : Bch) -> Int { self.t }
pub fn Bch::parity_bits(self : Bch) -> Int { self.n - self.k }

fn mul(code : Bch, a : Int, b : Int) -> Int {
  if a == 0 || b == 0 { 0 } else { code.exp[(code.log[a] + code.log[b]) % code.n] }
}

fn divide(code : Bch, a : Int, b : Int) -> Int {
  if a == 0 { 0 } else { code.exp[(code.log[a] - code.log[b] + code.n) % code.n] }
}

// The caller may select an alternative primitive polynomial. Full cycle
// validation rejects reducible and irreducible-but-nonprimitive polynomials.
pub fn Bch::new(m : Int, t : Int, primitive? : Int = 0) -> Bch raise BchError {
  if m < 2 || m > 12 || t < 1 || t > 64 { raise InvalidParameters }
  let n = (1 << m) - 1
  if 2 * t >= n { raise InvalidParameters }
  let defaults = [0, 0, 0x7, 0xb, 0x13, 0x25, 0x43, 0x83, 0x11d, 0x211, 0x409, 0x805, 0x1053]
  let poly = if primitive == 0 { defaults[m] } else { primitive }
  if poly < (1 << m) || poly >= (1 << (m + 1)) || (poly & 1) == 0 { raise InvalidParameters }
  let exp = Array::make(n, 0)
  let log = Array::make(n + 1, -1)
  let mut x = 1
  for i in 0..<n {
    if x == 0 || log[x] >= 0 { raise InvalidParameters }
    exp[i] = x
    log[x] = i
    x = x << 1
    if (x & (1 << m)) != 0 { x = x ^ poly }
  }
  if x != 1 { raise InvalidParameters }
  let root = Array::make(n, false)
  for i in 1..<(2 * t + 1) {
    let mut j = i
    while !root[j] {
      root[j] = true
      j = (j * 2) % n
    }
  }
  let mut generator : Array[Int] = [1]
  let field = { n, k: 0, t, m, exp, log, generator: [] }
  // Product of all Frobenius-conjugate roots; coefficients descend in degree.
  for r in 0..<n {
    if root[r] {
      let next = Array::make(generator.length() + 1, 0)
      for j in 0..<generator.length() {
        next[j] = next[j] ^ generator[j]
        next[j + 1] = next[j + 1] ^ mul(field, generator[j], exp[r])
      }
      generator = next
    }
  }
  for coefficient in generator {
    if coefficient != 0 && coefficient != 1 { raise InvalidParameters }
  }
  let k = n - generator.length() + 1
  if k <= 0 { raise InvalidParameters }
  { n, k, t, m, exp, log, generator }
}

fn check_bits(bits : Array[Int]) -> Unit raise BchError {
  for i in 0..<bits.length() { if bits[i] != 0 && bits[i] != 1 { raise InvalidBit(i) } }
}

pub fn Bch::generator_bits(self : Bch) -> Array[Int] { self.generator.copy() }

// Messages and codewords use most-significant-bit first. Shortening is implicit:
// a message of s <= k bits represents k-s leading zero message bits omitted.
pub fn Bch::encode(self : Bch, message : Array[Int]) -> Array[Int] raise BchError {
  if message.length() < 1 || message.length() > self.k { raise InvalidLength }
  check_bits(message)
  let parity = self.parity_bits()
  let work = Array::make(message.length() + parity, 0)
  for i in 0..<message.length() { work[i] = message[i] }
  for i in 0..<message.length() {
    if work[i] == 1 {
      for j in 0..<self.generator.length() { work[i + j] = work[i + j] ^ self.generator[j] }
    }
  }
  for i in 0..<message.length() { work[i] = message[i] }
  work
}

pub fn Bch::syndromes(self : Bch, word : Array[Int]) -> Array[Int] raise BchError {
  if word.length() <= self.parity_bits() || word.length() > self.n { raise InvalidLength }
  check_bits(word)
  let out = Array::make(2 * self.t, 0)
  for j in 1..<(out.length() + 1) {
    let mut s = 0
    for bit in word { s = mul(self, s, self.exp[j % self.n]) ^ bit }
    out[j - 1] = s
  }
  out
}

pub fn Bch::decode(self : Bch, received : Array[Int]) -> Decoded raise BchError {
  let s = self.syndromes(received)
  let locator = Array::make(2 * self.t + 1, 0)
  let mut previous = Array::make(2 * self.t + 1, 0)
  locator[0] = 1
  previous[0] = 1
  let mut degree = 0
  let mut distance = 1
  let mut scale = 1
  // Berlekamp-Massey computes the minimum recurrence of the syndrome sequence.
  for step in 0..<s.length() {
    let mut discrepancy = s[step]
    for j in 1..<(degree + 1) { discrepancy = discrepancy ^ mul(self, locator[j], s[step - j]) }
    if discrepancy == 0 {
      distance = distance + 1
    } else {
      let saved = locator.copy()
      let ratio = divide(self, discrepancy, scale)
      for j in 0..<(locator.length() - distance) {
        locator[j + distance] = locator[j + distance] ^ mul(self, ratio, previous[j])
      }
      if 2 * degree <= step {
        degree = step + 1 - degree
        previous = saved
        scale = discrepancy
        distance = 1
      } else { distance = distance + 1 }
    }
  }
  if degree > self.t { raise Uncorrectable }
  let fixed = received.copy()
  let positions : Array[Int] = []
  // Chien search covers the full parent code, including omitted leading bits.
  for power in 0..<self.n {
    let x = self.exp[(self.n - power) % self.n]
    let mut value = locator[degree]
    for j = degree - 1; j >= 0; j = j - 1 { value = mul(self, value, x) ^ locator[j] }
    if value == 0 {
      let index = received.length() - 1 - power
      if index < 0 { raise Uncorrectable }
      positions.push(index)
      fixed[index] = fixed[index] ^ 1
    }
  }
  if positions.length() != degree { raise Uncorrectable }
  for value in self.syndromes(fixed) { if value != 0 { raise Uncorrectable } }
  positions.sort()
  let message = Array::make(fixed.length() - self.parity_bits(), 0)
  for i in 0..<message.length() { message[i] = fixed[i] }
  { message, codeword: fixed, corrected_positions: positions }
}

pub fn bits_of_bytes(bytes : Array[Int]) -> Array[Int] raise BchError {
  let out : Array[Int] = []
  for b in bytes {
    if b < 0 || b > 255 { raise InvalidFrame }
    for i in 0..<8 { out.push((b >> (7 - i)) & 1) }
  }
  out
}

pub fn bytes_of_bits(bits : Array[Int]) -> Array[Int] raise BchError {
  check_bits(bits)
  let out = Array::make((bits.length() + 7) / 8, 0)
  for i in 0..<bits.length() { out[i / 8] = out[i / 8] | (bits[i] << (7 - i % 8)) }
  out
}
