library(dplyr)
library(RPostgreSQL)

pg <- src_postgres()

dbGetQuery(pg$con, "SET work_mem='10GB'")
filings <- tbl(pg, sql("SELECT * FROM filings.filings"))
acc_no_regex <- "edgar/data/\\d+/(.*)\\.txt$"
acc_nos <-
    filings %>%
    mutate(accession_no = regexp_replace(file_name, acc_no_regex, "\\1")) %>%
    mutate(cik = as.integer(cik)) %>%
    select(cik, accession_no) %>%
    compute(indexes = c("accession_no", "cik"))

shared_ciks <-
    acc_nos %>%
    inner_join(acc_nos, by="accession_no", suffix = c("_x", "_y")) %>%
    filter(cik_x != cik_y) %>%
    compute()

shared_ciks %>%
    group_by(cik_x, cik_y) %>%
    summarize(num_filings = n())
