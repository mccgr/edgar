library(dplyr)
library(curl)
library(RPostgreSQL)
library(doParallel)
library(xml2)

pg <- dbConnect(PostgreSQL())

filing_docs  <- tbl(pg, sql("SELECT * FROM edgar.filings"))
filing_item_nos <- tbl(pg, sql("SELECT * FROM edgar.item_no"))

## IDENTIFY FILES TO READ

first_read <- !dbExistsTable(pg, c("edgar", "item_no"))

form_types <- c("8-K")

if(!first_read){
    files_to_read <-
        filing_docs %>%
        filter(form_type == filing_types) %>%
        select(cik, file_name) %>%
        anti_join(filing_item_nos) %>%
        collect()
} else {
    files_to_read <-
        filing_docs %>%
        filter(form_type == filing_types) %>%
        collect()
}

# Read in files ----

extract_items <- function(file_name) {
    t<-tempfile()
    cik <- gsub('^edgar/data/|/0.*$', '', file_name)
    file_name_sub <- gsub("\\..*", "", basename(file_name))
    file_folder <- gsub("-", "", file_name_sub)
    download_url <- file.path("https://www.sec.gov/Archives/edgar/data",
                              cik, file_folder, paste0(file_name_sub,".hdr.sgml"))
    download.file(download_url, t, quiet = TRUE)
    text <-
        data.frame(content = readLines(t)) %>%
        filter(grepl("<ITEMS>", content)) %>%
        mutate(item_no = gsub("<ITEMS>", "", content)) %>%
        mutate(merge = T) %>%
        select(merge,item_no)
    file.remove(t)

    file <-
        data.frame(file_name = file_name) %>%
        mutate(merge = T) %>%
        left_join(text, by = "merge") %>%
        select(-merge)
}

dbDisconnect(pg)

for(k in 1:ceiling(nrow(files_to_read)/1000)) {

    run_group <-files_to_read[((k-1)*1000+1):(k*1000),]

    temp_results <- as.data.frame(do.call(rbind, mclapply(run_group$file_name, extract_items,
                                                          mc.cores = 15, mc.preschedule = FALSE)))

    pg <- dbConnect(PostgreSQL())

    new_table <- !dbExistsTable(pg, c("edgar", "item_no"))

    if (new_table) {
        dbWriteTable(pg, c("edgar", "item_no"), temp_results,
                     overwrite = TRUE, row.names = FALSE)
        dbGetQuery(pg, "CREATE INDEX ON edgar.filing_docs (file_name)")
    } else {
        dbWriteTable(pg, c("edgar", "item_no"), temp_results,
                     append = TRUE, row.names = FALSE)
    }

    dbDisconnect(pg)

    print(paste("uploaded batch", k, "of", ceiling(nrow(files_to_read)/1000)))
}

