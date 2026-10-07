# -------------------------------------------------------------------------
# Setup: Load required packages
# -------------------------------------------------------------------------
library(tidyverse)

# 1. Define the input and output paths
input_dir <- "~/Desktop/input"
output_file <- "~/Desktop/combined_mitochondria_3D.csv"

# 2. Get a list of all 3D measure files in the input folder
measure_files <- list.files(path = input_dir, pattern = "-3D_measure\\.csv$", full.names = TRUE)

# 3. Define a function to process and merge a pair of cell files
process_mito_files <- function(measure_path) {
  
  # Extract the raw file name
  file_name <- basename(measure_path)
  
  # Use Regular Expressions to cleanly split the Image Name and the Cell ID.
  # This looks for everything before "-cell" as the image, and extracts the "cellXYZ" part.
  match_data <- str_match(file_name, "^(.*)-(cell\\d+)-3D_measure\\.csv$")
  
  # Fallback just in case a file name is formatted differently
  if (is.na(match_data[1, 1])) {
    image_name <- str_remove(file_name, "-3D_measure\\.csv$")
    cell_id <- "Unknown"
  } else {
    image_name <- match_data[1, 2]
    cell_id <- match_data[1, 3]
  }
  
  # Construct the expected path for the matching "quantif" file
  quantif_path <- str_replace(measure_path, "-3D_measure\\.csv$", "-3D_quantif.csv")
  
  # Skip if the matching quantif file is missing
  if (!file.exists(quantif_path)) {
    warning(paste("Matching quantif file not found for:", file_name))
    return(NULL)
  }
  
  # Read both CSVs
  df_measure <- read_csv(measure_path, show_col_types = FALSE)
  df_quantif <- read_csv(quantif_path, show_col_types = FALSE)
  
  # Clean up trailing empty columns (caused by trailing commas in ImageJ/FIJI outputs)
  df_measure <- df_measure %>% select(where(~!all(is.na(.))))
  df_quantif <- df_quantif %>% select(where(~!all(is.na(.))))
  
  # Merge the files safely by their common identifier columns
  # Because each cell has MULTIPLE mitochondria, this merges them row-by-row perfectly
  df_combined <- full_join(df_measure, df_quantif, by = c("Nb", "Name", "Label", "Type"))
  
  # Add 'Image' and 'Cell_ID' columns to the beginning of the dataframe
  df_combined <- df_combined %>%
    mutate(
      Image = image_name,
      Cell_ID = cell_id,
      .before = 1
    )
  
  return(df_combined)
}

# 4. Apply the function to all measure files and bind the rows together
final_dataset <- map_dfr(measure_files, process_mito_files)

# 5. Write the final cleaned dataset to a CSV file
write_csv(final_dataset, output_file)

cat("Success! Processed", length(measure_files), "cells and consolidated", nrow(final_dataset), "total mitochondria.\n")
cat("File saved to:", output_file, "\n")