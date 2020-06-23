library(DBI)
library(dplyr, warn.conflicts = FALSE)

# Code to download a subset of filings from 2020
pg <- dbConnect(RPostgres::Postgres())

rs <- dbExecute(pg, "SET search_path TO edgar_test, edgar")
filings <- tbl(pg, "filings")

rs <- dbExecute(pg, "DROP TABLE IF EXISTS test_sample")

test_sample <-
    filings %>%
    filter(date_filed >= "2020-01-01") %>%
    select(file_name) %>%
    collect(n=1000) %>%
    copy_to(pg, ., name="test_sample", temporary = FALSE)

rs <- dbExecute(pg, "ALTER TABLE test_sample OWNER TO edgar")

dbDisconnect(pg)
