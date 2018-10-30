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


get_header <- function(xml_root) {

    schema <- xmlValue(getNodeSet(xml_root, 'schemaVersion')[[1]])
    doc_type <- xmlValue(getNodeSet(xml_root, 'documentType')[[1]])
    period <- xmlValue(getNodeSet(xml_root, 'periodOfReport')[[1]])

    header <- data.frame(schemaVersion = schema, documentType = doc_type, periodOfReport = period, stringsAsFactors = F)

    issuer <- get_issuer_details(xml_root)
    rep_owner <- get_rep_owner_details(xml_root)
    signature <- get_signature(xml_root)

    header <- bind_cols(header, issuer)
    header <- bind_cols(header, rep_owner)
    header <- bind_cols(header, signature)

    return(header)

}

get_nonDerivative_df <- function(xml_root) {

    nonDerivative_tran_nodes <- getNodeSet(getNodeSet(xml_root, 'nonDerivativeTable')[[1]], 'nonDerivativeTransaction')

    rest <- xmlToDataFrame(nonDerivative_tran_nodes)
    rest$seq <- rownames(rest)
    rest <- rest[, c('seq', 'securityTitle', 'transactionDate', 'postTransactionAmounts', 'ownershipNature')]

    df_cod_list <- lapply(1:length(nonDerivative_tran_nodes), function(x) {xmlToDataFrame(getNodeSet(nonDerivative_tran_nodes[[x]], 'transactionCoding'), stringsAsFactors = F)})
    df_cod <- bind_rows(df_cod_list, .id = "seq")

    df_amount_list <- lapply(1:length(nonDerivative_tran_nodes), function(x) {xmlToDataFrame(getNodeSet(nonDerivative_tran_nodes[[x]], 'transactionAmounts'), stringsAsFactors = F)})
    df_amount <- bind_rows(df_amount_list, .id = "seq")

    full_df <- rest %>% inner_join(df_cod, by = "seq") %>% inner_join(df_amount, by = "seq")

    return(full_df)

}


get_derivative_df <- function(xml_root) {

    derivative_tran_nodes <- getNodeSet(getNodeSet(xml_root, 'derivativeTable')[[1]], 'derivativeTransaction')
    rest <- xmlToDataFrame(derivative_tran_nodes)
    rest$seq <- rownames(rest)
    rest <- rest[, c('seq', 'securityTitle', 'conversionOrExercisePrice', 'transactionDate', 'exerciseDate', 'expirationDate',
                     'postTransactionAmounts', 'ownershipNature')]

    df_cod_list <- lapply(1:length(derivative_tran_nodes), function(x) {xmlToDataFrame(getNodeSet(derivative_tran_nodes[[x]], 'transactionCoding'), stringsAsFactors = F)})
    df_cod <- bind_rows(df_cod_list, .id = "seq")

    df_amount_list <- lapply(1:length(derivative_tran_nodes), function(x) {xmlToDataFrame(getNodeSet(derivative_tran_nodes[[x]], 'transactionAmounts'), stringsAsFactors = F)})
    df_amount <- bind_rows(df_amount_list, .id = "seq")

    df_usec_list <- lapply(1:length(derivative_tran_nodes), function(x) {xmlToDataFrame(getNodeSet(derivative_tran_nodes[[x]], 'underlyingSecurity'), stringsAsFactors = F)})
    df_usec <- bind_rows(df_usec_list, .id = "seq")

    full_df <- rest %>% inner_join(df_cod, by = "seq") %>% inner_join(df_amount, by = "seq") %>% inner_join(df_usec, by = "seq")

    return(full_df)

}


get_footnotes <- function(xml_root) {

    footnotes <- getNodeSet(getNodeSet(xml_root, 'footnotes')[[1]], 'footnote')
    num_footnotes <- length(footnotes)

    f_index <- c()
    f_footnote <- c()

    for(i in 1:num_footnotes) {

        f_index <- c(f_index, xmlAttrs(footnotes[[i]])[[1]])
        f_footnote <- c(f_footnote, xmlValue(footnotes[[i]]))

    }

    footnotes_df <- data.frame(index = f_index, footnote = f_footnote, stringsAsFactors = F)

    return(footnotes_df)

}


process_xml_documents <- function(xml_subset) {

    pg <- dbConnect(PostgreSQL())

    xml_subset <- xml_subset %>% rowwise() %>% mutate(doc_json = xml_url_to_json(doc_url))

    xml_subset <- xml_subset %>% filter(!is.na(doc_json)) %>% select(file_name, document, doc_json)
    num_successes <- num_successes + dim(xml_subset)[1]

    dbWriteTable(pg, c("edgar", "form_345_xml"), xml_subset, append = TRUE, row.names = FALSE)

    # Also add the successfully processed xml documents to edgar.filing_docs_processed

    processed <- xml_subset %>% select(file_name, document)

    dbWriteTable(pg, c("edgar", "filing_docs_processsed"), processed, append = TRUE, row.names = FALSE)

    dbDisconnect(pg)

    return(num_successes)


}





pg <- dbConnect(PostgreSQL())



xml_full_set <- tbl(pg, sql("SELECT * FROM edgar.filing_docs WHERE type IN ('3', '4', '5')")) %>% filter(document %~% "xml$") %>% collect()
xml_full_set <- xml_full_set %>% mutate(doc_url = get_filing_document_url(file_name, document))

num_documents <- dim(xml_full_set)[1]
num_successes <- 0
total_time <- 0

batch_size <- 200
num_batches <- ceiling(num_documents/batch_size)

for(i in 1:num_batches) {

    start = (i-1) * batch_size + 1

    if(i = num_batches) {

        finish = num_documents

    } else {

        finish = i * num_batches

    }


    batch <- xml_full_set[start:finish, ]

    time_taken <- system.time(num_successes <- num_successes + process_xml_documents(batch))
    total_time <- total_time + time_taken


    if(i %% 50 == 0) {

        print(paste0(num_successes, " successfully processed out of ", i * batch_size))
        print("Total time taken: \n")
        print(total_time)

    }


}




dbDisconnect(pg)






