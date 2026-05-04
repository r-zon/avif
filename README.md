# AVIF

An easy interface to read and write AV1 Image File Format in R, for both files and in-memory raw vectors.

## Installation

Dependencies:

- [Zig 0.16.0](https://ziglang.org/download/#release-0.16.0) (for building)
- libavif

Install `avif` with:

```R
pak::pkg_install("r-zon/avif")
```

## Usage

Read an AVIF file:

```R
read_avif("foo.avif")
```

Save an RGB array into an AVIF file:

```R
rgb_array <- hcl.colors(700) |>
  col2rgb() |>
  as.raw() |>
  array(c(3, 700, 100)) |>
  aperm()
write_avif(rgb_array, "8bpc.avif")
```

`read_avif` and `write_avif` can also output raw vectors:

```R
write_avif(rgb_array) |> read_avif() |> plot()
```

## Supported Formats

### Read

- [x] 8bpc
- [x] 10bpc
- [x] 12bpc

### Write

- [x] 8bpc
- [x] 10bpc
- [x] 12bpc
