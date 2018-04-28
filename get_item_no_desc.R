#!/usr/bin/env Rscript
library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)
library(stringr)

pg <- dbConnect(PostgreSQL())

rs <- dbExecute(pg, "SET search_path TO edgar")

item_no_desc <-
    read_html("https://www.sec.gov/fast-answers/answersform8khtm.html") %>%
    html_table() %>%
    .[[1]]   %>%
    select(`X1`, `X3`) %>%
    rename(item_no = `X1`,
           item_desc = `X3`) %>%
    filter(str_detect(item_no, "^Item")) %>%
    mutate(item_no = str_extract(item_no, "(?<=^Item\\s)(.*)$")) %>%
    mutate(item_desc = str_replace(item_desc, "\\(.*\\)", "")) %>%
    mutate(item_desc = str_trim(item_desc))

rs <- dbWriteTable(pg, "item_no_desc", item_no_desc,
                   overwrite = TRUE, row.names = FALSE)

rs <- dbGetQuery(pg, "ALTER TABLE item_no_desc OWNER TO edgar")
rs <- dbGetQuery(pg, "GRANT SELECT ON item_no_desc TO edgar_access")

dbDisconnect(pg)
