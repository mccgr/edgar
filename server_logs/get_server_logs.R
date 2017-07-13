library(readr)

library(stringr)

url <- "https://www.sec.gov/files/EDGAR%20Log%20File%20Data%20thru%20Sept2016.html"

file_list <- stringr::str_split(read_file(url), "\r\n")[[1]]
file_list <- tibble(url = file_list[-1])

head(file_list)

get_server_log_raw <- function(url) {
    library(curl)
    t <- tempfile()

    curl_download(url, t)

    fn <- unzip(t, list=TRUE)$Name[1]
    read_csv(unz(t, fn),
             col_types = "cctddccdddddddc")
}

get_server_log <- function(url) {
    server_log_raw <-
        get_server_log_raw(url) %>%
        mutate_at(vars(idx, norefer, noagent, crawler), funs(as.logical))

    robots <-
        server_log %>%
        group_by(ip) %>%
        summarize(num_downloads = n()) %>%
        filter(num_downloads >= 50)

    server_log_raw %>%
        filter(!crawler, !idx, code < 300,
               !is.na(cik), !is.na(accession), !is.na(date)) %>%
        anti_join(robots, by="ip") %>%
        rename(extension = extention)
}

process_server_log <- function(url) {

    library(RPostgreSQL)

    pg <- dbConnect(PostgreSQL())

    server_log <- get_server_log(url)


    dbWriteTable(pg, c("edgar", "server_log_processed"),
                 tibble(url = url), row.names = FALSE, append=TRUE)

    dbWriteTable(pg, c("edgar", "server_log"),
                 server_log, row.names = FALSE, append=TRUE)

    dbDisconnect(pg)
}

pg <- src_postgres()

processed_files <-
    tbl(pg, sql("SELECT * FROM edgar.server_log_processed")) %>%
    collect()

unprocessed_files <-
    file_list %>%
    anti_join(processed_files)

lapply(unprocessed_files$url[40:50], process_server_log)
