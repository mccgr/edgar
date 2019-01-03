library(RPostgreSQL)
library(XML)
library(rjson)
library(RCurl)
library(dplyr)
library(lubridate)
library(parallel)
source('forms_345_xml_functions.R')

set_permissions_access <- function(table_name) {

    pg <- dbConnect(PostgreSQL())

    dbGetQuery(pg, paste0("ALTER TABLE edgar.", table_name, " OWNER TO edgar"))
    dbGetQuery(pg, paste0("GRANT SELECT ON TABLE edgar.", table_name, " TO edgar_access"))

    dbDisconnect(pg)

}


make_table_comment <- function(table_name, table_comment) {

    pg <- dbConnect(PostgreSQL())

    dbGetQuery(pg, paste0("COMMENT ON TABLE edgar.", table_name, " IS '", table_comment, "'"))

    dbDisconnect(pg)

}


get_345_xml_docs <- function(num_docs = Inf) {

    pg <- dbConnect(PostgreSQL())


    xml_full_set <- tbl(pg, sql("SELECT file_name, document, type AS form_type FROM edgar.filing_docs WHERE type IN ('3', '4', '5')")) %>% filter(document %~% "xml$")

    new_table <- !dbExistsTable(pg, c("edgar", "xml_fully_processed"))


    if(new_table) {

        xml_subset <- xml_full_set %>% collect(n = num_docs)

    } else {

        xml_subset <- xml_full_set %>% collect(n = num_docs)

        xml_fully_processed_table <- tbl(pg, sql("SELECT file_name, document FROM edgar.xml_fully_processed"))

        xml_subset <- xml_full_set %>% anti_join(xml_fully_processed_table, by = c('file_name', 'document')) %>% collect(n = num_docs)

    }



    dbDisconnect(pg)


    return(xml_subset)

}



table_list <- c('forms345_header', 'forms345_reporting_owners', 'forms345_table1', 'forms345_table2', 'forms345_footnotes',
                'forms345_footnote_indices', 'forms345_signatures', 'xml_process_table', 'xml_fully_processed')

pg <- dbConnect(PostgreSQL())

form345_xml_docs_to_process <- get_345_xml_docs(num_docs = 1000000)

new_table <- !dbExistsTable(pg, c("edgar", "xml_fully_processed"))

num_filings <- dim(form345_xml_docs_to_process)[1]
batch_size <- 100
num_batches <- ceiling(num_filings/batch_size)
num_full_success <- 0
total_processed <- 0
total_time <- 0

for(i in 1:num_batches) {

    start <- (i - 1) * batch_size + 1

    if(i == num_batches){

        batch <- form345_xml_docs_to_process[start:num_filings, ]

    } else {

        finish <- i * batch_size
        batch <- form345_xml_docs_to_process[start:finish, ]

    }

    time_taken <- system.time(temp <- unlist(mclapply(1:dim(batch)[1], function(j) {process_345_filing(batch[["file_name"]][j], batch[["document"]][j], batch[["form_type"]][j])}, mc.cores =  24)))
    total_time <- total_time + time_taken
    num_full_success <- num_full_success + sum(temp)
    total_processed <- total_processed + dim(batch)[1]

    fully_processed <- data.frame(file_name = batch$file_name, document = batch$document, fully_processed = temp)

    dbWriteTable(pg, c("edgar", "xml_fully_processed"), fully_processed, append = TRUE, row.names = FALSE)

    if(new_table) {

        # if xml_fully_processed is a new table, so are the rest of them. Hence set permissions and access for all tables in table_list

        for(tab_name in table_list) {

            set_permissions_access(tab_name)

        }


        new_table <- FALSE

    }


    if(total_processed %% 10000 == 0 | i == num_batches) {

        print("Total time taken: \n")
        print(total_time)
        print("Number of full successes: \n")
        print(num_full_success)
        print("Number of filings processed: \n")
        print(total_processed)

    }


}


table_comment <- paste0("Created/Updated by process_345_xml_documents.R on ", as.character(now()))

for(tab_name in table_list) {

    make_table_comment(tab_name, table_comment)

}

dbDisconnect(pg)


