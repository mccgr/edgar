library(RPostgreSQL)
library(XML)
library(rjson)
library(RCurl)
library(dplyr)
library(lubridate)
library(parallel)
source('forms_345_xml_functions.R')


get_345_xml_docs <- function(num_docs = Inf) {

    pg <- dbConnect(PostgreSQL())


    xml_full_set <- tbl(pg, sql("SELECT file_name, document, type AS form_type FROM edgar.filing_docs WHERE type IN ('3', '4', '5')")) %>% filter(document %~% "xml$")

    new_table <- !dbExistsTable(pg, c("edgar", "xml_process_table"))


    if(new_table) {

        xml_subset <- xml_full_set %>% collect(n = num_docs)

    } else {

        xml_subset <- xml_full_set %>% collect(n = num_docs)

        xml_process_table <- tbl(pg, sql("SELECT file_name, document FROM edgar.xml_process_table"))

        xml_subset <- xml_full_set %>% anti_join(xml_process_table, by = c('file_name', 'document')) %>% collect(n = num_docs)

    }



    dbDisconnect(pg)


    return(xml_subset)

}

num_full_success = 0
total_processed = 0
total_time = 0

logical_cols <- c('got_xml', 'got_header', 'got_table1', 'got_table2', 'got_footnotes', 'got_footnote_indices', 'got_signatures',
                  'wrote_header', 'wrote_table1', 'wrote_table2', 'wrote_footnotes', 'wrote_footnote_indices', 'wrote_signatures')

pg <- dbConnect(PostgreSQL())

new_table <- !dbExistsTable(pg, c("edgar", "xml_process_table"))
while((batch_size <- nrow(batch <- get_345_xml_docs(num_docs = 100))) & total_processed < 10000) {


    time_taken <- system.time(temp <- bind_rows(mclapply(1:batch_size, function(j) {process_345_filing(batch[["file_name"]][j], batch[["document"]][j], batch[["form_type"]][j])}, mc.cores =  24)))
    total_time <- total_time + time_taken
    num_full_success <- num_full_success + sum(rowSums(temp[, logical_cols]) == 13)
    total_processed <- total_processed + batch_size
    dbWriteTable(pg, c("edgar", "xml_process_table"), temp, append = !new_table, row.names = FALSE)

    if(new_table) {

        dbGetQuery(pg, "ALTER TABLE edgar.xml_process_table OWNER TO edgar")
        dbGetQuery(pg, "GRANT SELECT ON TABLE edgar.xml_process_table TO edgar_access")
        new_table <- FALSE

    }

    print("Total time taken: \n")
    print(total_time)
    print("Number of full successes: \n")
    print(num_full_success)
    print("Number of filings processed: \n")
    print(total_processed)




}


dbDisconnect(pg)
