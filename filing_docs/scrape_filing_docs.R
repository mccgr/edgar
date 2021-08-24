#!/usr/bin/env Rscript
library(dplyr, warn.conflicts = FALSE)
library(DBI)
library(parallel)

target_schema <- "edgar"
target_table <- "filing_docs"

source("filing_docs/scrape_filing_docs_functions.R")

pg <- dbConnect(RPostgres::Postgres())

rs <- dbExecute(pg, "SET search_path TO edgar, public")
rs <- dbExecute(pg, "SET work_mem = '5GB'")

filings <- tbl(pg, "filings")

file_names <-
    filings %>%
    select(file_name)

new_table <- !dbExistsTable(pg, "filing_docs")

if (!new_table) {
    filing_docs <- tbl(pg, "filing_docs")
    def14_a <- file_names %>% anti_join(filing_docs, by = "file_name", copy = TRUE)
} else {
    def14_a <- file_names
}

get_file_names <- function() {
    def14_a %>%
        collect(n = 1000)
}

batch <- 0
new <- lubridate::now()
while(nrow(file_names <- get_file_names()) > 0) {
    def14_a <-
        def14_a %>%
        anti_join(file_names, by = "file_name", copy = TRUE)

    batch <- batch + 1
    cat("Processing batch", batch, "\n")

    temp <- mclapply(file_names$file_name, filing_docs_df, mc.cores = 2)

    # temp <- lapply(file_names$file_name, filing_docs_df)

    # SEC rule: no more than 10 requests per second per IP, otherwise lock IP for 10 min
    Sys.sleep(0.5)

    if (length(temp) > 0) {
        df <- bind_rows(temp)

        if (nrow(df) > 0) {
            cat("Writing data ...\n")

            print(df %>% dim())
            dbWriteTable(pg, "filing_docs",
                         df %>% select(-document_note, -url), append = TRUE, row.names = FALSE)

        } else {
            cat("No data ...\n")
        }
    }
    old <- new; new <- lubridate::now()
    cat(difftime(new, old, units = "secs"), "seconds\n")
    temp <- unlist(temp)
}

if (new_table) {
    pg <- dbConnect(RPostgres::Postgres())

    rs <- dbExecute(pg, "SET search_path TO edgar, public")
    rs <- dbExecute(pg, "CREATE INDEX ON filing_docs (file_name)")
    rs <- dbExecute(pg, "ALTER TABLE filing_docs OWNER TO edgar")
    rs <- dbExecute(pg, "GRANT SELECT ON TABLE filing_docs TO edgar_access")

    rs <- dbDisconnect(pg)
}
