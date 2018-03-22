library(dplyr)
library(curl)
library(RPostgreSQL)
library(doParallel)

pg <- dbConnect(PostgreSQL())

filing_docs  <- tbl(pg, sql("SELECT * FROM edgar.filings"))
filing_item_nos <- tbl(pg, sql("SELECT * FROM edgar.filing_item_nos"))

## IDENTIFY FILES TO READ

first_read <- !dbExistsTable(pg,c("edgar","filing_item_nos"))

form_types<-c("8-K")

if(!first_read){
files_to_read <- filing_docs %>%
    filter(form_type == filing_types) %>%
    select(cik,file_name) %>%
    anti_join(filing_item_nos) %>%
    collect()
} else {
    files_to_read <- filing_docs %>%
    filter(form_type == filing_types) %>%
        collect()}

## READ IN FILES

t<-tempfile()

extract_items<-function(file)
{
    file_name <- file$file_name
    cik <- file$cik
    file_name_sub <- gsub("\\..*","",basename(file_name))
    file_folder <- gsub("-","",file_name_sub)
    download_url <- file.path("https://www.sec.gov/Archives/edgar/data",cik,file_folder,paste0(file_name_sub,".hdr.sgml"))
    download.file(download_url, t, quiet = T)
    text<-data.frame(content = readLines(t)) %>%
        filter(grepl("<ITEMS>",content)) %>%
        mutate(content = gsub("<ITEMS>","",content))
    file %>%
        mutate(item_no = paste(text$content, collapse = " ; ")) %>%
        select(file_name,item_no)

}

dbDisconnect(pg)

cl<-makeCluster(10)
registerDoParallel(cl)
temp_results<-foreach(i=1:nrow(files_to_read), .combine = rbind, .packages = c("dplyr")) %dopar% {
    extract_items(files_to_read[i,])
    }
stopCluster(cl)


if (new_table) {
    pg <- dbConnect(PostgreSQL())
    dbWriteTable(pg, c("edgar","item_no"), temp_results, overwrite = T, row.names = F)
    dbGetQuery(pg, "CREATE INDEX ON edgar.filing_docs (file_name)")
    dbDisconnect(pg)
}
