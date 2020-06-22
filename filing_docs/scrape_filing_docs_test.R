#!/usr/bin/env Rscript
library(dplyr, warn.conflicts = FALSE)
library(DBI)

target_schema <- "edgar_test"
target_table <- "filing_docs_test"

source("filing_docs/scrape_filing_docs_functions.R")
library(parallel)

pg <- dbConnect(RPostgres::Postgres())

rs <- dbExecute(pg, "SET search_path TO edgar_test, edgar, public")
rs <- dbExecute(pg, "SET work_mem = '5GB'")

get_file_names <- function() {
    new_table <- !dbExistsTable(pg, "filing_docs_test")

    filings <- tbl(pg, "test_sample")

    file_names <-
        filings %>%
        select(file_name)

    if (!new_table) {
        filing_docs <- tbl(pg, "filing_docs_test")
        def14_a <- file_names %>% anti_join(filing_docs, by = "file_name")
    } else {
        def14_a <- file_names
    }

    def14_a %>%
        collect(n = 1000)
}

table_setup <- function() {
    pg <- dbConnect(RPostgres::Postgres())

    rs <- dbExecute(pg, "SET search_path TO edgar, public")
    rs <- dbExecute(pg, "CREATE INDEX ON filing_docs_test (file_name)")
    rs <- dbExecute(pg, "ALTER TABLE filing_docs_test OWNER TO edgar")
    rs <- dbExecute(pg, "GRANT SELECT ON TABLE filing_docs_test TO edgar_access")

    rs <- dbDisconnect(pg)
}

batch <- 0
new <- lubridate::now()
while(nrow(file_names <- get_file_names()) > 0) {
    batch <- batch + 1
    cat("Processing batch", batch, "\n")

    temp <- mclapply(file_names$file_name, filing_docs_df, mc.cores = 6)
    if (length(temp) > 0) {
        df <- bind_rows(temp)

        if (nrow(df) > 0) {
            cat("Writing data ...\n")
            dbWriteTable(pg, "filing_docs_test",
                         df, append = TRUE, row.names = FALSE)

        } else {
            cat("No data ...\n")
        }
    }
    old <- new; new <- lubridate::now()
    cat(difftime(new, old, units = "secs"), "seconds\n")
    temp <- unlist(temp)

    if(new_table) {
        table_setup
        new_table <- FALSE
    }
}
