library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)

pg <- dbConnect(PostgreSQL())
dbGetQuery(pg, "SET search_path TO edgar")
dbGetQuery(pg, "SET work_mem='10GB'")

filings <- tbl(pg, sql("SELECT * FROM filings"))
filer_ciks <- tbl(pg, sql("SELECT * FROM filer_ciks"))

adv_count <-
    filings %>%
    filter(form_type %~% '^ADV') %>%
    group_by(cik) %>%
    summarize(num_adv_filings = n()) %>%
    compute()

sc13d_count <-
    filer_ciks %>%
    mutate(cik = as.integer(filer_cik)) %>%
    inner_join(filings %>% select(-cik), by="file_name") %>%
    group_by(cik, form_type) %>%
    summarize(num_filings = n()) %>%
    compute()

sc13d_count %>%
    mutate(cik = as.integer(cik)) %>%
    left_join(adv_count) %>%
    compute()
