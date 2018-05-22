library(RPostgreSQL)
library(dplyr, warn.conflicts = FALSE)

# File to download the subset of 8-K filings related to item number 2.05

pg <- dbConnect(PostgreSQL())

rs <- dbExecute(pg, "SET search_path TO edgar")
item_no <- tbl(pg, "item_no")


itemno205 <-
    item_no %>%
    filter(item_no == '2.05') %>%
    select(file_name) %>%
    collect()
dbDisconnect(pg)

source('download_filing_docs_functions.R')

download_filing_docs(max_files = 200, filing_subset = itemno205)
