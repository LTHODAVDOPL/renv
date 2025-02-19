
R <- function() {
  bin <- R.home("bin")
  exe <- if (renv_platform_windows()) "R.exe" else "R"
  file.path(bin, exe)
}

r_exec <- function(package, args, label) {

  # ensure R_LIBS is set
  rlibs <- paste(renv_libpaths_all(), collapse = .Platform$path.sep)
  renv_scope_envvars(R_LIBS = rlibs, R_LIBS_USER = "", R_LIBS_SITE = "")

  # ensure Rtools is on the PATH for Windows
  renv_scope_rtools()

  # do the install
  output <- suppressWarnings(system2(R(), args, stdout = TRUE, stderr = TRUE))

  # check for successful install
  status <- attr(output, "status") %||% 0L
  if (!identical(status, 0L))
    r_exec_error(package, output, label)

  output

}

r_exec_error <- function(package, output, label) {

  # installation failed; write output for user
  fmt <- "Error %sing package '%s':"
  header <- sprintf(fmt, label, package)

  lines <- paste(rep("=", nchar(header)), collapse = "")
  all <- c(header, lines, "", output)

  # try to add diagnostic information if possible
  diagnostics <- r_exec_error_diagnostics(package, output)
  if (!empty(diagnostics)) {
    size <- min(getOption("width"), 78L)
    dividers <- paste(rep.int("-", size), collapse = "")
    all <- c(all, paste(dividers, diagnostics, collapse = "\n\n"))
  }

  # stop with an error
  message <- sprintf("%s of package '%s' failed", label, package)
  error <- simpleError(message = message)
  error$output <- all
  stop(error)

}

r_exec_error_diagnostics_fortran <- function() {

  checker <- function(output) {
    pattern <- "library not found for -l(quadmath|gfortran|fortran)"
    idx <- grep(pattern, output)
    if (length(idx))
      return(output[idx])
  }

  suggestion <- "
R was unable to find one or more FORTRAN libraries during compilation.
This often implies that the FORTRAN compiler has not been properly configured.
Please see https://stackoverflow.com/q/35999874 for more information.
"

  list(
    checker = checker,
    suggestion = suggestion
  )

}

r_exec_error_diagnostics <- function(package, output) {

  diagnostics <- list(
    r_exec_error_diagnostics_fortran()
  )

  suggestions <- uapply(diagnostics, function(diagnostic) {

    check <- catch(diagnostic$checker(output))
    if (!is.character(check))
      return()

    suggestion <- diagnostics$suggestion
    reasons <- paste("-", shQuote(check), collapse = "\n")
    paste(diagnostic$suggestion, "Reason(s):", reasons, sep = "\n")

  })

  as.character(suggestions)

}

r_cmd_install <- function(package, path, library, ...) {

  path <- renv_path_normalize(path, winslash = "/", mustWork = TRUE)

  # prefer using a short path name for the library on Windows,
  # to help avoid issues caused by overly-long paths
  library <- if (renv_platform_windows())
    utils::shortPathName(library)
  else
    renv_path_normalize(library, winslash = "/", mustWork = TRUE)

  args <- c(
    "--vanilla",
    "CMD", "INSTALL", "--preclean", "--no-multiarch",
    r_cmd_install_option(package, "configure.args", TRUE),
    r_cmd_install_option(package, "configure.vars", TRUE),
    r_cmd_install_option(package, "install.opts", FALSE),
    "-l", shQuote(library),
    ...,
    shQuote(path)
  )

  output <- r_exec(package, args, "install")

  installpath <- file.path(library, package)
  if (!file.exists(installpath))
    r_exec_error(package, output, "install")

  installpath

}

r_cmd_build <- function(package, path, ...) {

  path <- renv_path_normalize(path, winslash = "/", mustWork = TRUE)
  args <- c("--vanilla", "CMD", "build", "--md5", ..., shQuote(path))
  output <- r_exec(package, args, "build")

  pasted <- paste(output, collapse = "\n")
  pattern <- "[*] building .([a-zA-Z0-9_.-]+)."
  matches <- regexec(pattern, pasted)
  text <- regmatches(pasted, matches)

  tarball <- text[[1]][[2]]
  if (!file.exists(tarball))
    r_exec_error(package, output, "build")

  file.path(getwd(), tarball)

}

r_cmd_install_option <- function(package, option, configure) {

  # read option
  value <- getOption(option)
  if (is.null(value))
    return(NULL)

  # check for named values
  if (!is.null(names(value))) {
    value <- value[[package]]
    if (is.null(value))
      return(NULL)
  }

  # if this is a configure option, format specially
  if (configure) {
    confkey <- sub(".", "-", option, fixed = TRUE)
    confval <- shQuote(paste(value, collapse = " "))
    return(sprintf("--%s=%s", confkey, confval))
  }

  # otherwise, just paste it
  paste(value, collapse = " ")

}
