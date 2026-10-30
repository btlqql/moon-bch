# References and attribution

The finite-field arithmetic, conjugate-root generator construction,
Berlekamp-Massey decoder, Chien search and container in this repository are
original implementation code for this submission. They implement established
coding-theory algorithms; they are not claimed to be novel algorithms.

Independent development reference: [galois 0.4.11](https://github.com/mhostetter/galois),
MIT license. [BCH documentation](https://mhostetter.github.io/galois/latest/api/galois.BCH/).
`scripts/reference_vectors.py` uses its public API to create data vectors with
author-selected deterministic messages and error locations. No galois source is
copied or imported by the MoonBit runtime. The generated fixture data records
the exact reference version and seed. Python, NumPy, Numba and LLVM are not
runtime dependencies of this package.

The CRC32 polynomial 0xedb88320 is the reflected IEEE polynomial. CRC32 is used
only to check accidental corruption in the application container.
