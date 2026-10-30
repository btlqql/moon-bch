# MoonBCH

Pure MoonBit primitive, narrow-sense binary BCH error correction. The library
constructs its generator from conjugate roots, systematically encodes full or
shortened messages, computes syndromes, runs Berlekamp-Massey and Chien search,
and returns corrected bits and their exact positions. No C, Python or network
service is needed at runtime.

## Why this package

Use BCH when a fixed-size binary record must survive a bounded number of
individual bit flips. This differs from Reed-Solomon byte-symbol erasure coding
and LDPC soft-decision iteration. Inputs are bits; the corrected message is
available through a reusable API, not only a demonstration executable.

The shipped MBCH v1 file tool groups bytes into BCH blocks and checks the recovered
payload with CRC32. It demonstrates a complete source-file damage/recovery task;
it is an application format, not an existing storage-device wire format.

## Run

Install MoonBit and Node.js, then clone this repository:

```sh
moon test --target js
moon run cmd/main --target js -- encode 4 2 1010101
moon run cmd/main --target js -- decode 4 2 001010111100100
moon run cmd/main --target js -- protect 8 2 input.bin protected.mbch
moon run cmd/main --target js -- recover damaged.mbch recovered.bin
```

The first command encodes to `101010111100101`. The decoder example repairs two
bit errors. Output files are created exclusively; an existing path is refused.
Failures return exit code 1 and do not write a recovered file.

## Library

```moonbit
let code = @bch.Bch::new(4, 2)
let word = code.encode([1, 0, 1, 0, 1, 0, 1])
word[0] = word[0] ^ 1
let fixed = code.decode(word)
// fixed.message = [1,0,1,0,1,0,1], fixed.corrected_positions = [0]
```

`length()`, `capacity()`, `strength()`, `parity_bits()`, `generator_bits()` and
`syndromes()` expose code parameters and inspection. Public inputs and results
are copied where needed; mutation of a result cannot change the codec tables.

## Supported class and limits

- Primitive narrow-sense binary BCH, GF(2^m), m=2..12, t=1..64 where 2t<n and k>0.
- Optional primitive polynomial; validation checks its complete multiplicative
  cycle. The default polynomial for each field is explicit in the source.
- Bits are MSB-first. Any message length 1..k uses leading-zero shortening;
  decoding rejects an inferred error in omitted positions.
- Guaranteed recovery requires at most t bit flips per codeword. Beyond t,
  bounded-distance decoders may fail or miscorrect to another codeword. CRC32
  adds accidental-corruption detection to MBCH but is not authentication.
- The library is hard-decision errors-only; no erasures, q-ary BCH, soft input,
  controller drivers, interleaving or standard NAND ECC layout is claimed.
- MBCH metadata must remain intact. Its format is documented in
  [docs/mbch-format.md](docs/mbch-format.md). Payload <=64 KiB and encoded data
  <=1,048,576 bits. File tools reject inconsistent lengths and trailing padding.

## Validation

- All 128 BCH(15,7,t=2) messages under every 0-, 1- and 2-bit error pattern:
  **15,488 recovery cases**.
- **66 independent galois 0.4.11 encoding/decoding vectors**, including full and
  shortened codes; checked-in fixtures run without installing galois.
- Additional m=12/t=64, alternative polynomial, shortening, invalid inputs,
  CRC32, multiple-block recovery and damaged-envelope tests.
- The final delivery verifier damages two bits in every BCH block of the actual
  `bch.mbt` file and checks byte-for-byte recovery and SHA-256 equality.

Reference vector regeneration: install galois 0.4.11 separately, then run
`python scripts/reference_vectors.py`. This is a development dependency only.
See [THIRD_PARTY.md](THIRD_PARTY.md). License: Apache-2.0.
