#!/usr/bin/env Rscript
library(dplyr, warn.conflicts = FALSE)
library(DBI)
library(stringr)
library(readr)
library(parallel)

pg <- dbConnect(RPostgres::Postgres())

rs <- dbExecute(pg, "SET search_path TO edgar")

filings  <- tbl(pg, "filings")

# Identify files to read ----

first_read <- !dbExistsTable(pg, "item_no")

form_types <- c("8-K")

if (first_read) {
    dbExecute(pg, "CREATE TABLE item_no (file_name text, item_no text)")
    dbExecute(pg, "CREATE INDEX ON item_no (file_name)")
    dbExecute(pg, "ALTER TABLE item_no OWNER TO edgar")
    dbExecute(pg, "GRANT SELECT ON item_no TO edgar_access")
}

item_no <- tbl(pg, "item_no")

files_to_read <-
    filings %>%
    filter(form_type %in% form_types) %>%
    select(file_name) %>%
    anti_join(item_no, by = "file_name")

# Read in files ----
# This function was borrowed from get_filer_ciks.R
get_sgml_url <- function(file_name) {
    matches <- str_match(file_name, "edgar/data/(\\d+)/(\\d{10})-(\\d{2})-(\\d{6}).txt")
    url <- paste0("https://www.sec.gov/Archives/edgar/data/",
                  matches[2], "/",
                  paste0(matches[3:5], collapse=""), "/",
                  matches[3], "-", matches[4], "-", matches[5],
                  ".hdr.sgml")
    return(url)
}

extract_items <- function(file_name) {

    download_url <- get_sgml_url(file_name)

    temp <- read_lines(download_url)

    items <-
        tibble(file_name = file_name,
               item_no = str_extract(temp, "(?<=^<ITEMS>)(.*)$")) %>%
        filter(!is.na(item_no))

    file <-
        tibble(file_name = file_name) %>%
        left_join(items, by = "file_name")

    return(file)
}

batch_size <- 100L
files_remaining <- files_to_read %>% count() %>% pull()
num_batches <- ceiling(files_remaining/batch_size)
batch_num <- 0L

while(files_to_read %>% head() %>% count() %>% pull() > 0) {
    sys_time <- system.time({
        run_group <- collect(files_to_read, n = batch_size)

        batch_num <- batch_num + 1L
        cat("Processing batch", batch_num, "of", num_batches, "... ")

        try({
            temp_list <- mclapply(run_group$file_name, extract_items, mc.cores = 1)
            temp_results <- bind_rows(temp_list)

            if (nrow(temp_results) > 0) {
                dbWriteTable(pg, "item_no", temp_results,
                             append = TRUE, row.names = FALSE)
            }
        })
    })
    cat(sys_time[["elapsed"]], "seconds\n")
}

rs <- dbDisconnect(pg)

