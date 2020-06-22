library(DBI)
library(dplyr, warn.conflicts = FALSE)
library(parallel)

source(file.path("https://raw.githubusercontent.com",
                 "mccgr/edgar/master/filing_docs",
                 "download_filing_docs_functions.R"))

# Code to download the subset of 8-K filings related to item number 2.05

# Get list of files to download ----
pg <- dbConnect(RPostgres::Postgres())

rs <- dbExecute(pg, "SET search_path TO edgar_test, edgar")
filing_docs <- tbl(pg, "filing_docs")
filing_docs_alt <- tbl(pg, "filing_docs_alt")
filings <- tbl(pg, "filings")

filing_docs_full <-
    filing_docs %>%
    left_join(filing_docs_alt)

dbExecute(pg, "DROP TABLE IF EXISTS test_sample")

test_sample <-
    filing_docs_full %>%
    inner_join(filings) %>%
    filter(date_filed >= "2020-01-01") %>%
    collect(n=1000) %>%
    mutate(file_path = coalesce(path_alt, get_file_path(file_name, document))) %>%
    select(file_name, document, file_path) %>%
    copy_to(pg, ., name="test_sample", temporary = FALSE) %>%
    collect()

dbExecute(pg, "ALTER TABLE test_sample OWNER TO edgar")

dbDisconnect(pg)

# Download files from list ----
system.time(test_sample$downloaded <- unlist(mclapply(test_sample$file_path,
                                                      get_filing_docs, mc.cores = 12)))

test_sample %>% count(downloaded)

test_sample %>%
    filter(!downloaded) %>%
    select(file_name, document)
