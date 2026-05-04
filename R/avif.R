#'
#' Read an AVIF Image
#'
#' Read an AVIF image from a file or a raw vector into an RGB array.
#'
#' @useDynLib avif, .registration = TRUE, .fixes = "AVIF_"
#' @param source A file path or a raw vector.
#' @param ptype Prototype like raw(), 0L or 0.0 that defines the output type.
#' @param normalize If `TRUE`, output a normalized (0-1) real array.
#' @param native_raster If `TRUE`, output a nativeRaster integer matrix.
#' @param codec Codec for decoding, automatic if `NULL`.
#' @param jobs Number of decoder threads, must be greater than 0, or `NULL` for all cores.
#' @param ... Unused.
#' @return An RGB array.
#' @export
#' @examples
#' if (file.exists("8bpc.avif")) {
#'   read_avif("8bpc.avif")
#' }
#' if (file.exists("10bpc.avif")) {
#'   read_avif("10bpc.avif", ptype = 0L, native_raster = TRUE)
#' }
#' if (file.exists("12bpc.avif")) {
#'   read_avif(
#'     readBin("12bpc.avif", "raw", file.size("12bpc.avif")),
#'     ptype = 0.,
#'     normalize = TRUE
#'   )
#' }
read_avif <- function(
  source,
  ...,
  ptype = raw(),
  normalize = FALSE,
  native_raster = FALSE,
  codec = NULL,
  jobs = NULL
) {
  arguments <- new.env(parent = emptyenv())
  arguments$jobs <- jobs
  arguments$normalize <- normalize
  arguments$native_raster <- native_raster
  arguments$codec <- codec

  img <- .Call(AVIF_read_avif, source, ptype, arguments)
  if (native_raster) {
    return(img)
  }
  depth <- attr(img, "depth")
  img <- aperm(img)
  attr(img, "depth") <- depth
  attr(img, "normalized") <- normalize
  class(img) <- c("avif", class(img))
  img
}

#' Write an AVIF Image
#'
#' Create an AVIF image from an RGB array into a file or return a raw vector.
#'
#' @param image A raw or integer vector with dimensions (height, width, channel).
#' @param target A file path, or `NULL` for a raw vector.
#' @param speed Encoder speed in \[0, 10\] where 0 is the slowest, 10 is the fastest.
#' @param quality Color quality in \[0, 100\] where 100 is lossless.
#' @param alpha_quality Alpha quality in \[0, 100\] where 100 is lossless.
#' @param format YUV format, must be one of 444, 422, 420 or 400.
#' @param codec Codec for encoding, automatic if `NULL`.
#' @param jobs Number of encoder threads, must be greater than 0, or `NULL` for all cores.
#' @param ... Unused.
#' @return `NULL` if `target` is a file path, otherwise a raw vector.
#' @export
#' @examples
#' rgb_array <- hcl.colors(700) |>
#'   col2rgb() |>
#'   as.raw() |>
#'   array(c(3, 700, 100)) |>
#'   aperm()
#' save_path <- file.path(tempdir(), "8bpc.avif")
#' write_avif(rgb_array, save_path, speed = 0L, quality = 100L)
#' writeBin(write_avif(rgb_array), save_path)
write_avif <- function(
  image,
  target = NULL,
  ...,
  speed = 6L,
  quality = 60L,
  alpha_quality = 60L,
  format = 444L,
  codec = NULL,
  jobs = NULL
) {
  arguments <- new.env(parent = emptyenv())
  arguments$jobs <- jobs
  arguments$speed <- speed
  arguments$quality <- quality
  arguments$alpha_quality <- alpha_quality
  arguments$format <- format
  arguments$codec <- codec

  depth <- attr(image, "depth")
  image <- aperm(image)
  attr(image, "depth") <- depth

  bytes <- .Call(AVIF_write_avif, image, target, arguments)
  if (is.null(target)) {
    bytes
  } else {
    invisible()
  }
}

#' @importFrom grDevices as.raster
#' @export
as.raster.avif <- function(x, ..., max = NULL) {
  if (is.null(max)) {
    if (isTRUE(attr(x, "normalized"))) {
      max <- 1
    } else {
      max <- 2^attr(x, "depth") - 1
    }
  }
  as.raster(unclass(x), max = max, ...)
}

#' @export
plot.avif <- function(x, ...) {
  plot(as.raster(x), ...)
}
