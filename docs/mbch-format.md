# MBCH version 1

All offsets are bytes. This application container is owned by this project.

| Offset | Width | Meaning |
|---|---:|---|
| 0 | 4 | ASCII `MBCH` |
| 4 | 1 | version = 1 |
| 5 | 1 | m |
| 6 | 1 | t |
| 7 | 1 | reserved = 0 |
| 8 | 4 | original byte length, unsigned little-endian |
| 12 | 4 | IEEE reflected CRC32 of original bytes, little-endian |
| 16 | variable | concatenated full systematic BCH codewords, MSB-first |

The default field polynomial is fixed by m in `bch.mbt`. There is no custom
polynomial field in this container version. Original bytes are MSB-first bits,
divided into k-bit messages. The last message is right-padded with zero bits.
All codewords have n=2^m-1 bits; the last encoded byte is right-padded with zeros.
Both padding regions and the exact implied frame length are checked on recovery.
An empty input has no codewords and CRC32=0. Unknown versions are rejected.

Metadata is not BCH protected. This envelope demonstrates recovery of damaged
payload blocks under intact metadata. It does not claim resilience to an
arbitrary corrupted header. CRC32 detects accidental errors with a finite
collision probability; it is not cryptographic integrity or authenticity.
