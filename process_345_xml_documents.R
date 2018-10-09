library(RPostgreSQL)
library(XML)
library(rjson)
library(RCurl)
library(dplyr)


xml_url_to_json <- function(url) {

    try({fileURL <- file.path(url)
    xml_parse <- xmlParse(getURL(fileURL))
    xml_root <- xmlRoot(xml_parse)
    xml_list <- xmlToList(xml_root,addAttributes = T, simplify = F)
    xml_rjson <- toJSON(xml_list)
    return(xml_rjson)}, return(NA))
}

get_filing_document_url <- function(file_name, document) {
    matches <- stringr::str_match(file_name, "/(\\d+)/(\\d{10}-\\d{2}-\\d{6})")
    cik <- matches[2]
    acc_no <- matches[3]
    path <- stringr::str_replace_all(acc_no, "[^\\d]", "")

    url <- paste0("https://www.sec.gov/Archives/edgar/data/", cik, "/", path, "/",
                  document)
    return(url)
}


get_info_from_node <- function(node) {

    subnode_names <- names(node)
    names <- c()
    values <- c()

    for(name in subnode_names) {

        subnames <- names(node[[name]])
        if(is.null(subnames)) {

            names <- c(names, name)

            if(is.null(node[[name]])) {
                values <- c(values, NA)
            } else {
                values <- c(values, node[[name]])
            }

        } else {

            subtree_df <- get_info_from_node(node[[name]])
            names <- c(names, paste(name, subtree_df$names, sep = "_"))
            values <- c(values, subtree_df$values)

        }

    }


    df <- data.frame(names, values, stringsAsFactors = FALSE)
    return(df)

}


json_to_df <- function(data_json) {

    data_list <- fromJSON(data_json)
    raw_df <- get_info_from_node(data_list)
    ncols = dim(raw_df)[1]
    data_df <- data.frame(matrix(nrow = 0, ncol = ncols))
    colnames(data_df) <- raw_df$names
    data_df[1, ] = raw_df$values

    return(data_df)

}


get_info_names_from_node <- function(node) {

    subnode_names <- names(node)
    info_names <- c()

    for(name in subnode_names) {

        subnames <- names(node[[name]])
        if(is.null(subnames)) {

            info_names <- c(info_names, name)

        } else {

            info_names <- c(info_names, get_info_names_from_node(node[[name]]))

        }

    }


    return(info_names)

}





pg <- dbConnect(PostgreSQL())


xml_subset <- tbl(pg, sql("SELECT * FROM edgar.filing_docs_test")) %>% filter(document %~% "xml$") %>% collect()
# xml_subset <- tbl(pg, sql("SELECT * FROM edgar.filing_docs WHERE type IN ('3', '4', '5')")) %>% filter(document %~% "xml$") %>% collect()

num_documents <- dim(xml_subset)[1]
num_successes <- 0
total_time <- 0

xml_subset <- xml_subset %>% mutate(doc_url = get_filing_document_url(file_name, document))

xml_subset <- xml_subset %>% rowwise() %>% mutate(doc_json = xml_url_to_json(doc_url))

xml_subset <- xml_subset %>% filter(!is.na(doc_json)) %>% select(file_name, document, doc_json)


dbWriteTable(pg, c("edgar", "form_345_xml"),
             xml_subset, append = TRUE, row.names = FALSE)





dbDisconnect(pg)






