#!/usr/bin/env Rscript
library(dplyr, warn.conflicts = FALSE)
library(DBI)

target_schema <- "edgar"
target_table <- "filing_docs"
filings_table <- "filings"
source("filing_docs/scrape_filing_docs_functions.R")
library(parallel)

pg <- dbConnect(RPostgres::Postgres())

rs <- dbExecute(pg, paste0("SET search_path TO ", target_schema))
rs <- dbExecute(pg, "SET work_mem = '5GB'")
rs <- dbExecute(pg, "SET max_parallel_workers = 4")
get_file_names <- function() {
    assign("new_table", !dbExistsTable(pg, target_table),
           env = .GlobalEnv)

    filings <- tbl(pg, filings_table)

    file_names <-
        filings %>%
        select(file_name)

    if (!new_table) {
        filing_docs <- tbl(pg, target_table)
        def14_a <- file_names %>% anti_join(filing_docs, by = "file_name")
    } else {
        def14_a <- file_names
    }

    def14_a %>%
        collect(n = 1000)
}

table_setup <- function() {
    pg <- dbConnect(RPostgres::Postgres())

    rs <- dbExecute(pg, paste0("SET search_path TO ", target_schema))
    rs <- dbExecute(pg, paste0("CREATE INDEX ON ", target_table, " (file_name)"))
    rs <- dbExecute(pg, paste0("ALTER TABLE ", target_table, " OWNER TO edgar"))
    rs <- dbExecute(pg, paste0("GRANT SELECT ON TABLE ", target_table,
                               " TO edgar_access"))

    rs <- dbDisconnect(pg)
}

batch <- 0
new <- lubridate::now()
while (nrow(file_names <- get_file_names()) > 0) {
    batch <- batch + 1
    cat("Processing batch", batch, "\n")

    temp <- mclapply(file_names$file_name, filing_docs_df, mc.cores = 6)
    if (length(temp) > 0) {
        df <- bind_rows(temp)

        if (nrow(df) > 0) {
            cat("Writing data ...\n")
            dbWriteTable(pg, target_table,
                         df, append = TRUE, row.names = FALSE)

        } else {
            cat("No data ...\n")
        }
    }
    old <- new; new <- lubridate::now()
    cat(difftime(new, old, units = "secs"), "seconds\n")
    temp <- unlist(temp)

    if (new_table) {
        table_setup
        new_table <- FALSE
    }
}
