#!/usr/bin/env Rscript
library(dplyr, warn.conflicts = FALSE)
library(DBI)
library(rvest, quietly = TRUE)
source('filing_docs/get_filing_doc_functions.R')

pg <- dbConnect(RPostgres::Postgres())

rs <- dbExecute(pg, "SET work_mem = '5GB'")
rs <- dbExecute(pg, "SET search_path TO edgar, public")

filings <- tbl(pg, "filings")

def14_a <-
    filings %>%
    # filter(form_type %~% "^(10-[QK]|SC 13[DG](/A)?|DEF 14|8-K|6-K|13|[345](/A)?$)") %>%
    select(file_name)

new_table <- !dbExistsTable(pg, "filing_docs")

if (!new_table) {
    filing_docs <- tbl(pg, "filing_docs")
    def14_a <- def14_a %>% anti_join(filing_docs, by = "file_name")
}

get_file_names <- function() {
    def14_a %>%
        collect(n = 100)
}

library(parallel)

batch <- 0
while(nrow(file_names <- get_file_names()) > 0) {
    batch <- batch + 1
    cat("Processing batch", batch, "\n")
    temp <- mclapply(file_names$file_name, filing_docs_df, mc.cores = 6)
    if (length(temp) > 0) {
        df <- bind_rows(temp)

        if (nrow(df) > 0) {
            cat("Writing data ...\n")
            dbWriteTable(pg, "filing_docs",
                         df, append = TRUE, row.names = FALSE)

        } else {
            cat("No data ...\n")
        }
    }
}

if (new_table) {
    pg <- dbConnect(RPostgres::Postgres())

    rs <- dbExecute(pg, "SET search_path TO edgar, public")
    rs <- dbExecute(pg, "CREATE INDEX ON filing_docs (file_name)")
    rs <- dbExecute(pg, "ALTER TABLE filing_docs OWNER TO edgar")
    rs <- dbExecute(pg, "GRANT SELECT ON TABLE filing_docs TO edgar_access")

    rs <- dbDisconnect(pg)
}

temp <- unlist(temp)
