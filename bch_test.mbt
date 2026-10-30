test "BCH 15 7 2 generator is the known binary polynomial" {
  let code = Bch::new(4, 2)
  assert_eq(code.length(), 15)
  assert_eq(code.capacity(), 7)
  assert_eq(code.generator_bits(), [1,1,1,0,1,0,0,0,1])
}

test "all BCH 15 7 messages with every zero one or two errors recover" {
  let code = Bch::new(4, 2)
  let mut cases = 0
  for value in 0..<128 {
    let message = Array::make(7, 0)
    for j in 0..<7 { message[j] = (value >> (6 - j)) & 1 }
    let encoded = code.encode(message)
    assert_eq(code.decode(encoded).message, message)
    cases = cases + 1
    for a in 0..<15 {
      let corrupt = encoded.copy()
      corrupt[a] = corrupt[a] ^ 1
      assert_eq(code.decode(corrupt).message, message)
      cases = cases + 1
      for b in (a + 1)..<15 {
        let pair = corrupt.copy()
        pair[b] = pair[b] ^ 1
        let fixed = code.decode(pair)
        assert_eq(fixed.message, message)
        assert_eq(fixed.corrected_positions, [a,b])
        cases = cases + 1
      }
    }
  }
  assert_eq(cases, 15488)
}

test "shortened words, all bit locations, inputs unchanged" {
  let code = Bch::new(5, 3)
  for size in 1..<(code.capacity() + 1) {
    let message = Array::make(size, 1)
    let word = code.encode(message)
    for i in 0..<word.length() {
      let corrupt = word.copy()
      corrupt[i] = corrupt[i] ^ 1
      assert_eq(code.decode(corrupt).message, message)
      assert_eq(corrupt[i], word[i] ^ 1)
    }
  }
}

test "all supported fields validate their primitive polynomial cycles" {
  for m in 2..<13 { let code = Bch::new(m,1); assert_eq(code.capacity(),(1 << m) - 1 - m) }
  assert_true(try { ignore(Bch::new(4,2,primitive=0x15)); false } catch { _ => true })
  assert_true(try { ignore(Bch::new(1,1)); false } catch { _ => true })
  assert_true(try { ignore(Bch::new(4,8)); false } catch { _ => true })
}

test "nonbits empty and overlong words are refused" {
  let code = Bch::new(4,2)
  assert_true(try { ignore(code.encode([2])); false } catch { InvalidBit(0) => true; _ => false })
  assert_true(try { ignore(code.decode([])); false } catch { InvalidLength => true; _ => false })
  assert_true(try { ignore(code.encode(Array::make(8,0))); false } catch { InvalidLength => true; _ => false })
}

test "checksummed binary blocks recover multiple independently damaged blocks" {
  let input = [0,255,1,2,3,4,128,64,32,16,8,4,2,1]
  let frame = protect(input,5,2)
  // First codeword: two errors. Second codeword: one error.
  frame[16] = frame[16] ^ 0xc0
  frame[20] = frame[20] ^ 0x80
  let result = recover(frame)
  assert_eq(result.data,input)
  assert_eq(result.corrected_bits,3)
  assert_eq(result.corrected_blocks,2)
  assert_eq(recover(protect([],4,2)).data,[])
}

test "container rejects truncation invalid header and checksum tampering" {
  let frame = protect([1,2,3],5,2)
  let bad = frame.copy()
  ignore(bad.pop())
  assert_true(try { ignore(recover(bad)); false } catch { _ => true })
  frame[12] = frame[12] ^ 1
  assert_true(try { ignore(recover(frame)); false } catch { ChecksumMismatch => true; _ => false })
  frame[0] = 0
  assert_true(try { ignore(recover(frame)); false } catch { InvalidFrame => true; _ => false })
}

test "high-strength and largest supported fields correct all injected locations" {
  for params in [(8,32),(12,64)] {
    let code = Bch::new(params.0,params.1)
    let message = [1,0,1,1,0,0,1,0,1]
    let word = code.encode(message)
    for i in 0..<params.1 { word[i] = word[i] ^ 1 }
    let result = code.decode(word)
    assert_eq(result.message,message)
    assert_eq(result.corrected_positions.length(),params.1)
  }
}

test "CRC32 reference and frame resource limits" {
  assert_eq(crc32([49,50,51,52,53,54,55,56,57]),0xcbf43926U)
  assert_true(try { ignore(protect(Array::make(65537,0),4,2)); false } catch { InvalidLength => true; _ => false })
  let code = Bch::new(4,2,primitive=0x19)
  let w = code.encode([1,0,1]); w[0] = w[0] ^ 1
  assert_eq(code.decode(w).message,[1,0,1])
}
