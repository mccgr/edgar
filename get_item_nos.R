library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)
library(stringr)
library(readr)
library(parallel)

pg <- dbConnect(PostgreSQL())

filings  <- tbl(pg, sql("SELECT * FROM edgar.filings"))

# Identify files to read ----

first_read <- !dbExistsTable(pg, c("edgar", "item_no"))

form_types <- c("8-K")

if (first_read) {
    dbGetQuery(pg, "CREATE TABLE edgar.item_no (file_name text, item_no text)")
    dbGetQuery(pg, "CREATE INDEX ON edgar.item_no (file_name)")
    dbGetQuery(pg, "ALTER TABLE edgar.item_no OWNER TO edgar")
    dbGetQuery(pg, "GRANT SELECT ON edgar.item_no TO edgar_access")
}

item_no <- tbl(pg, sql("SELECT * FROM edgar.item_no"))

files_to_read <-
    filings %>%
    filter(form_type %in% form_types) %>%
    select(file_name) %>%
    anti_join(item_no)

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

    tryCatch({
        temp <- read_lines(download_url)

        items <-
            tibble(file_name = file_name,
                   item_no = str_extract(temp, "(?<=^<ITEMS>)(.*)$")) %>%
            filter(!is.na(item_no))

        file <-
            tibble(file_name = file_name) %>%
            left_join(items, by = "file_name")

        return(file)
    })
}

batch_size <- 1000L
files_remaining <- files_to_read %>% count() %>% pull()
num_batches <- ceiling(files_remaining/batch_size)
batch_num <- 0L

while(files_to_read %>% head() %>% count() %>% pull() > 0) {
    sys_time <- system.time({
        run_group <- collect(files_to_read, n = batch_size)

        batch_num <- batch_num + 1L
        cat("Processing batch", batch_num, "of", num_batches, "... ")

        try({
            temp_list <- mclapply(run_group$file_name, extract_items,
                                  mc.cores = 20, mc.preschedule = FALSE)
            temp_results <- bind_rows(temp_list)

            dbWriteTable(pg, c("edgar", "item_no"), temp_results,
                         append = TRUE, row.names = FALSE)
        })
    })
    cat(sys_time[["elapsed"]], "seconds\n")
}

dbDisconnect(pg)

