library(RPostgreSQL)
library(dplyr, warn.conflicts = FALSE)
library(parallel)

source(file.path("https://raw.githubusercontent.com",
                 "iangow-public/edgar/master",
                 "download_filing_docs_functions.R"))

# Code to download the subset of 8-K filings related to item number 2.05

# Get list of files to download ----
pg <- dbConnect(PostgreSQL())

rs <- dbExecute(pg, "SET search_path TO edgar")
item_no <- tbl(pg, "item_no")
filing_docs <- tbl(pg, "filing_docs")

itemno205 <-
    item_no %>%
    filter(item_no == '2.05') %>%
    select(file_name) %>%
    inner_join(filing_docs) %>%
    select(file_name, document) %>%
    collect() %>%
    mutate(file_path = get_file_path(file_name, document))
dbDisconnect(pg)

# Download files from list ----
itemno205$downloaded <- unlist(mclapply(itemno205$file_path,
                                        get_filing_docs, mc.cores = 12))

# browse_filing_doc(itemno205$file_path[100])
