# Standard package loading
if (!requireNamespace("pacman", quietly = TRUE)) install.packages("pacman")
pacman::p_load(tidyverse, janitor, writexl, readxl)

# 1. Define Desktop Paths
home_dir    <- Sys.getenv("HOME")
input_dir   <- file.path(home_dir, "Desktop", "input")
output_file <- file.path(home_dir, "Desktop", "consolidated_cell_vol_mito_intensity_stdev.xlsx")

# 2. Extract metadata (Image ID & Cell Number) from Filenames
extract_metadata <- function(filename) {
  # Regex matches optional prefixes (M_, Q_), image ID, and cell number
  pattern <- "(?i)(?:[MQ]_)?([A-Za-z0-9_]+?)[-_]cell(\\d+)"
  match   <- stringr::str_match(filename, pattern)
  
  if (is.na(match[1, 1])) return(NULL)
  
  list(
    image       = match[1, 2],
    cell_number = sprintf("cell%03d", as.numeric(match[1, 3]))
  )
}

# 3. Parsers for specific file types
parse_vol_txt <- function(path) {
  lines <- readLines(path, warn = FALSE)
  lines <- lines[trimws(lines) != ""]
  
  parts <- stringr::str_split_fixed(lines, ":", 2)
  keys  <- trimws(parts[, 1])
  vals  <- as.numeric(trimws(parts[, 2]))
  
  # Remove "in CellXXX" text from keys before cleaning
  clean_keys <- stringr::str_remove(keys, "(?i)\\s+in\\s+cell\\d+.*")
  clean_keys <- janitor::make_clean_names(clean_keys)
  
  setNames(as.list(vals), clean_keys) %>% tibble::as_tibble()
}

parse_morph_txt <- function(path) {
  readr::read_tsv(path, show_col_types = FALSE) %>%
    janitor::clean_names() %>%
    dplyr::select(-dplyr::any_of(c("x1", "x", "unnamed_0")))
}

parse_csv_file <- function(path) {
  readr::read_csv(path, show_col_types = FALSE) %>%
    janitor::clean_names()
}

# 4. Master File Dispatcher
process_file <- function(file_path) {
  fname <- basename(file_path)
  meta  <- extract_metadata(fname)
  
  if (is.null(meta)) return(NULL)
  
  # Route parser based on filename structure
  df <- if (grepl("vol\\.txt$", fname, ignore.case = TRUE)) {
    parse_vol_txt(file_path)
  } else if (grepl("morph\\.txt$", fname, ignore.case = TRUE)) {
    parse_morph_txt(file_path)
  } else if (grepl("\\.csv$", fname, ignore.case = TRUE)) {
    parse_csv_file(file_path)
  } else if (grepl("\\.xlsx?$", fname, ignore.case = TRUE)) {
    readxl::read_excel(file_path) %>% janitor::clean_names()
  } else {
    NULL
  }
  
  if (is.null(df) || nrow(df) == 0) return(NULL)
  
  # Inject primary key columns
  df %>% mutate(image = meta$image, cell_number = meta$cell_number, .before = 1)
}

# 5. Read, Consolidate, and Export
file_paths <- list.files(input_dir, full.names = TRUE)

consolidated_df <- map(file_paths, process_file) %>%
  compact() %>%
  bind_rows() %>%
  group_by(image, cell_number) %>%
  summarise(
    across(everything(), ~ {
      valid_vals <- na.omit(.)
      if (length(valid_vals) > 0) valid_vals[1] else NA
    }),
    .groups = "drop"
  ) %>%
  arrange(image, cell_number)

# Export Excel
writexl::write_xlsx(consolidated_df, output_file)

message("Successfully consolidated ", nrow(consolidated_df), " cells across ", length(file_paths), " files.")
message("Saved to: ", output_file)