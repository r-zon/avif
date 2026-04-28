#'
#' Read an AVIF image
#'
#' Read an AVIF image from a file or a raw vector into an RGB array.
#'
#' @useDynLib avif, .registration = TRUE, .fixes = "AVIF_"
#' @param source A file path or a raw vector.
#' @param ptype Prototype such as raw(), 0L or 0.0 that defines the output type.
#' @param normalize If `TRUE`, output a normalized (0-1) array.
#' @return An RGB array.
#' @export
#' @examples
#' read_avif("8bpc.avif")
#' read_avif("10bpc.avif", ptype = 0L)
#' read_avif(readBin("12bpc.avif", "raw", file.size("12bpc.avif")), ptype = 0., normalize = TRUE)
read_avif <- function(
  source,
  ...,
  ptype = raw(),
  normalize = FALSE,
  native_raster = FALSE,
  jobs = NULL
) {
  arguments <- new.env(parent = emptyenv())
  arguments$jobs <- jobs
  arguments$normalize <- normalize
  arguments$native_raster <- native_raster

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

#' Write an AVIF image
#'
#' Create an AVIF image from an RGB array into a file or return a raw vector.
#'
#' @param image A raw vector with dimensions (height, width, channel).
#' @param target A file path, or `NULL` for a raw vector.
#' @return `NULL` if `target` is a file path, or a raw vector.
#' @export
#' @examples
#' rgb_array <- hcl.colors(700) |>
#'   col2rgb() |>
#'   as.raw() |>
#'   array(c(3, 700, 100)) |>
#'   aperm()
#' write_avif(rgb_array, "8bpc.avif")
#' writeBin(write_avif(rgb_array), "8bpc.avif")
write_avif <- function(
  image,
  target = NULL,
  ...,
  speed = 6L,
  quality = 60L,
  alpha_quality = 60L,
  format = 444L,
  jobs = NULL
) {
  arguments <- new.env(parent = emptyenv())
  arguments$jobs <- jobs
  arguments$speed <- speed
  arguments$quality <- quality
  arguments$alpha_quality <- alpha_quality
  arguments$format <- format

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
