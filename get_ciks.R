#!/usr/bin/env Rscript
library(DBI)
library(dplyr, warn.conflicts = FALSE)
library(stringr)

parse_text <- function(lines) {
    mat <- str_split_fixed(lines, ":(?=(\\d{10}|$))", 3)
    colnames(mat) <- c("company_name", "cik", "nothing")
    as_tibble(mat) %>% select(1:2)
}

url <- "https://www.sec.gov/Archives/edgar/cik-lookup-data.txt"

ciks <- parse_text(readLines(url, encoding = 'latin1'))

ciks$cik <- as.integer(ciks$cik)

ciks <- ciks[, c('cik', 'company_name')]


pg <- dbConnect(RPostgreSQL::PostgreSQL())

rs <- dbWriteTable(pg, c("edgar", "ciks"), ciks, overwrite = TRUE, row.names = FALSE, encoding = "latin1")

rs <- dbExecute(pg, "ALTER TABLE edgar.ciks OWNER TO edgar")

rs <- dbExecute(pg, "GRANT SELECT ON edgar.ciks TO edgar_access")


dbDisconnect(pg)
