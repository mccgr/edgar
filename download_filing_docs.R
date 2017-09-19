
raw_directory <- Sys.getenv("EDGAR_DIR")

library(RPostgreSQL)
library(dplyr)

pg <- dbConnect(PostgreSQL())

all_files<-tbl(pg, sql("select * from edgar.filing_docs limit 140"))
files_downloaded<-tbl(pg, sql("select * from edgar.filing_docs_processed limit 120"))

if(exists("files_downloaded")){files<-all_files %>% anti_join(files_downloaded %>% filter(downloaded == TRUE)) %>% collect() %>% mutate(html_link = file.path(gsub("-","",gsub(".txt","",file_name)),document)) } else {files<-all_files %>% collect() %>% mutate(html_link = file.path(gsub("-","",gsub(".txt","",file_name)),document)) }

get_filing_docs <- function(path) {

    local_filename <- file.path(raw_directory, path)

    # Only download the file if we don't already have a local copy

    download.text <- function(path) {

        link <- file.path("https://www.sec.gov/Archives", path)
        dir.create(dirname(local_filename), showWarnings=FALSE, recursive=TRUE)
        if (!file.exists(local_filename)) {
            try(download.file(url=link, destfile=local_filename, quiet=TRUE))
        }
    }

    #     print(path[!file.exists(local_filename) & !is.na(path)])
    lapply(path, download.text)

    # Return the local filename if the file exists
    return(file.exists(local_filename))

}

files$downloaded<-lapply(files$html_link, get_filing_docs)

dbWriteTable(pg, c("edgar", "filing_docs_processed"), files, append = TRUE, row.names = FALSE)

dbDisconnect(pg)
