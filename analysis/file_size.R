library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)

pg <- dbConnect(PostgreSQL())

rs <- dbGetQuery(pg, "SET work_mem='10GB'")

filing_docs <- tbl(pg, sql("SELECT * FROM edgar.filing_docs"))
lm_10x_summaries <- tbl(pg, sql("SELECT * FROM lm.lm_10x_summaries"))

size_txt <-
    filing_docs %>%
    filter(type=='') %>%
    select(file_name, size) %>%
    rename(size_cts = size)

size_10_k <-
    filing_docs %>%
    filter(type=='10-K') %>%
    select(file_name, size) %>%
    left_join(size_txt)

graphics <-
    filing_docs %>%
    group_by(file_name) %>%
    summarize(has_graphic = bool_or(type=='GRAPHIC')) %>%
    compute()

graphics_size <-
    filing_docs %>%
    filter(type=='GRAPHIC') %>%
    group_by(file_name) %>%
    summarize(size_graphics = sum(size)) %>%
    compute()

reg_data <-
    size_10_k %>%
    inner_join(graphics) %>%
    left_join(graphics_size) %>%
    mutate(size_graphics = coalesce(size_graphics, 0L)) %>%
    compute()

graphics %>%
    count(has_graphic)

library(ggplot2)
reg_data %>%
    collect() %>%
    filter(size < 1e7) %>%
    ggplot(aes(x=size, fill=has_graphic)) +
    geom_histogram()

filing_docs %>%
    count(type) %>%
    arrange(desc(n))

merged <-
    reg_data %>%
    inner_join(lm_10x_summaries) %>%
    mutate(same_size = size_cts == grossfilesize,
           percent_graphics = 1 - size*1.0/size_cts,
           size_net = size_cts - size_graphics) %>%
    compute()

merged %>%
    count(same_size)

merged %>%
    filter(!same_size) %>%
    select(file_name, matches("size"))

merged %>%
    select(size_cts, percent_graphics) %>%
    collect() %>%
    ggplot(aes(y=size_cts, x = percent_graphics )) +
    geom_point()

merged %>%
    select(size_cts, percent_graphics) %>%
    collect() %>%
    ggplot(aes(x = percent_graphics )) +
    geom_histogram(binwidth = .05)
