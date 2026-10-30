extern "js" fn read_file(path : String) -> String? =
  #| p => { try { const f=process.getBuiltinModule('fs'); const s=f.statSync(p); if(s.size>131088)return undefined;return f.readFileSync(p).toString('hex'); } catch {return undefined;} }

extern "js" fn write_file(path : String, hex : String) -> Bool =
  #| (p,h) => { try {process.getBuiltinModule('fs').writeFileSync(p,Buffer.from(h,'hex'),{flag:'wx'});return true;}catch{return false;} }

extern "js" fn fail(text : String) -> Unit =
  #| s => { process.stderr.write(s+'\n');process.exitCode=1; }

fn bits(text : String) -> Array[Int] raise @bch.BchError {
  let out : Array[Int] = []
  for c in text {
    if c != '0' && c != '1' { raise @bch.InvalidLength }
    out.push(if c == '1' { 1 } else { 0 })
  }
  out
}

fn bit_text(values : Array[Int]) -> String {
  let out = StringBuilder()
  for b in values { out.write_string(b.to_string()) }
  out.to_string()
}

fn number(s : String) -> Int raise @bch.BchError {
  let mut n = 0
  if s.length() == 0 || s.length() > 3 { raise @bch.InvalidParameters }
  for c in s {
    if c < '0' || c > '9' { raise @bch.InvalidParameters }
    n = n * 10 + c.to_int() - 48
  }
  n
}

fn hex(bytes : Array[Int]) -> String {
  let digits = "0123456789abcdef"
  let out = StringBuilder()
  for b in bytes {
    out.write_char(digits[b >> 4].to_int().unsafe_to_char())
    out.write_char(digits[b & 15].to_int().unsafe_to_char())
  }
  out.to_string()
}

fn unhex(s : String) -> Array[Int] {
  let out : Array[Int] = []
  let mut high = 0
  for i in 0..<s.length() {
    let c = s[i].to_int()
    let n = if c <= 57 { c - 48 } else { c - 87 }
    if i % 2 == 0 { high = n } else { out.push(high * 16 + n) }
  }
  out
}

fn main {
  let args = @env.args()
  try {
    if args.length() == 6 && (args[2] == "encode" || args[2] == "decode") {
      let code = @bch.Bch::new(number(args[3]), number(args[4]))
      if args[2] == "encode" {
        println(bit_text(code.encode(bits(args[5]))))
      } else {
        let result = code.decode(bits(args[5]))
        println("message=" + bit_text(result.message))
        println("corrected=" + result.corrected_positions.length().to_string())
      }
    } else if args.length() == 7 && args[2] == "protect" {
      let raw = match read_file(args[5]) { Some(s) => unhex(s); None => raise @bch.InvalidFrame }
      let result = @bch.protect(raw, number(args[3]), number(args[4]))
      if !write_file(args[6], hex(result)) { fail("Cannot create output: path exists or write failed") }
      else { println("protected bytes=" + raw.length().to_string()) }
    } else if args.length() == 5 && args[2] == "recover" {
      let raw = match read_file(args[3]) { Some(s) => unhex(s); None => raise @bch.InvalidFrame }
      let result = @bch.recover(raw)
      if !write_file(args[4], hex(result.data)) { fail("Cannot create output: path exists or write failed") }
      else {
        println("recovered bytes=" + result.data.length().to_string())
        println("corrected bits=" + result.corrected_bits.to_string())
      }
    } else {
      fail("Usage: encode|decode <m> <t> <bits>; protect <m> <t> <input> <output>; recover <input> <output>")
    }
  } catch {
    e => fail("BCH failed: " + (match e {
      @bch.InvalidParameters => "invalid parameters or primitive polynomial"
      @bch.InvalidBit(_) => "non-binary input"
      @bch.InvalidLength => "invalid length or resource limit"
      @bch.Uncorrectable => "uncorrectable codeword"
      @bch.InvalidFrame => "invalid or truncated MBCH frame"
      @bch.ChecksumMismatch => "CRC checksum mismatch"
    }))
  }
}
