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


get_xml_root <- function(url) {

    try({fileURL <- file.path(url)
    xml_parse <- xmlParse(getURL(fileURL))
    xml_root <- xmlRoot(xml_parse)
    return(xml_root)}, return(NA))
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

get_issuer_details <- function(xml_root) {

    df_issuer <- xmlToDataFrame(getNodeSet(xml_root, 'issuer'))

    return(df_issuer)

}

get_rep_owner_details <- function(xml_root) {

    df_rep_owner_id <- xmlToDataFrame(getNodeSet(getNodeSet(xml_root, 'reportingOwner')[[1]], 'reportingOwnerId'))
    df_rep_owner_ad <- xmlToDataFrame(getNodeSet(getNodeSet(xml_root, 'reportingOwner')[[1]], 'reportingOwnerAddress'))
    df_rep_owner_rel <- xmlToDataFrame(getNodeSet(getNodeSet(xml_root, 'reportingOwner')[[1]], 'reportingOwnerRelationship'))

    df_rep_owner <- bind_cols(df_rep_owner_id, bind_cols(df_rep_owner_ad, df_rep_owner_rel))

    return(df_rep_owner)

}

get_signature <- function(xml_root) {

    df <- xmlToDataFrame(getNodeSet(xml_root, 'ownerSignature'))

    return(df)
}


get_variable_value <- function(node, variable_name) {

    # This is a function for extracting the values from fields which ONLY APPEAR ONCE under a node
    # Returns the value in the field if it exists, returns NA if the field does not exist

    variable_node_list <- getNodeSet(node, variable_name)

    if(length(variable_node_list) == 0) {

        return(NA)

    } else{

        value <- xmlValue(variable_node_list[[1]])

        return(value)

    }

}


get_header <- function(xml_root, file_name, document) {

    header <- data.frame(matrix(nrow = 0, ncol = 32))
    colnames(header) <- c('file_name', 'document', 'schemaVersion', 'documentType', 'periodOfReport', 'dateOfOriginalSubmission', 'noSecuritiesOwned', 'notSubjectToSection16', 'form3HoldingsReported', 'form4TransactionsReported', 'issuerCik', 'issuerName', 'issuerTradingSymbol', 'rptOwnerCik', 'rptOwnerCcc', 'rptOwnerName', 'rptOwnerStreet1', 'rptOwnerStreet2', 'rptOwnerCity', 'rptOwnerState', 'rptOwnerZipCode', 'rptOwnerStateDescription', 'rptOwnerGoodAddress', 'isDirector', 'isOfficer', 'isTenPercentOwner', 'isOther', 'officerTitle', 'otherText', 'remarks', 'signatureName', 'signatureDate')


    schema <- get_variable_value(xml_root, 'schemaVersion')
    doc_type <- get_variable_value(xml_root, 'documentType')
    period <- get_variable_value(xml_root, 'periodOfReport')
    date_orig_sub <- get_variable_value(xml_root, 'dateOfOriginalSubmission')
    no_sec_owned <- get_variable_value(xml_root, 'noSecuritiesOwned')
    no_sect_16 <- get_variable_value(xml_root, 'notSubjectToSection16')
    form_3_holdings <- get_variable_value(xml_root, 'form3HoldingsReported')
    form_4_trans <- get_variable_value(xml_root, 'form4TransactionsReported')

    part_df <- data.frame(schemaVersion = schema, documentType = doc_type, periodOfReport = period, dateOfOriginalSubmission = date_orig_sub, noSecuritiesOwned = no_sec_owned, notSubjectToSection16 = no_sect_16, form3HoldingsReported = form_3_holdings, form4TransactionsReported = form_4_trans, stringsAsFactors = F)

    issuer <- get_issuer_details(xml_root)
    rep_owner <- get_rep_owner_details(xml_root)
    signature <- get_signature(xml_root)

    part_df <- bind_cols(part_df, issuer)
    part_df <- bind_cols(part_df, rep_owner)

    part_df$remarks <- get_variable_value(xml_root, 'remarks')

    part_df <- bind_cols(part_df, signature)

    header <- bind_rows(header, part_df)

    header$file_name <- file_name
    header$document <- document

    return(header)

}


scrape_filing_table <- function(xml_root, table, type) {

    # xml_root: the xml root node
    # table: an integer of 1 for Table 1 (non-derivative), or 2 for Table 2 (derivative)
    # type: a string specifying whether an element/row represents a 'Transaction' or a 'Holding'

    subnode_names <- c('transactionCoding', 'postTransactionAmounts', 'ownershipNature')

    if(table == 1) {

        if(type == 'Transaction') {

            nodes <- getNodeSet(getNodeSet(xml_root, 'nonDerivativeTable')[[1]], 'nonDerivativeTransaction')

            rest_cols <- c('seq', 'securityTitle', 'transactionDate', 'deemedExecutionDate', 'transactionTimeliness')
            df <- data.frame(matrix(nrow = 0, ncol = 5))
            subnode_names <- c(subnode_names, 'transactionAmounts')

        } else if(type == 'Holding') {


            nodes <- getNodeSet(getNodeSet(xml_root, 'nonDerivativeTable')[[1]], 'nonDerivativeHolding')

            rest_cols <- c('seq', 'securityTitle')
            df <- data.frame(matrix(nrow = 0, ncol = 2))

        } else {

            print("Error: Invalid type entered: enter 'Transaction' or 'Holding' ")
            df <- data.frame()
            return(df)

        }


    } else if(table == 2) {

        if(type == 'Transaction') {

            nodes <- getNodeSet(getNodeSet(xml_root, 'derivativeTable')[[1]], 'derivativeTransaction')

            rest_cols <- c('seq', 'securityTitle', 'conversionOrExercisePrice', 'transactionDate', 'deemedExecutionDate', 'transactionTimeliness', 'exerciseDate', 'expirationDate')
            df <- data.frame(matrix(nrow = 0, ncol = 8))
            subnode_names <- c(subnode_names, 'transactionAmounts')



        } else if(type == 'Holding') {


            nodes <- getNodeSet(getNodeSet(xml_root, 'derivativeTable')[[1]], 'derivativeHolding')

            rest_cols <- c('seq', 'securityTitle', 'conversionOrExercisePrice', 'exerciseDate', 'expirationDate')
            df <- data.frame(matrix(nrow = 0, ncol = 5))

        } else {

            print("Error: Invalid type entered: enter 'Transaction' or 'Holding' ")
            df <- data.frame()
            return(df)

        }


        subnode_names <- c(subnode_names, 'underlyingSecurity')




    } else {


        print("Error: invalid value for table number entered. Enter 1 for nonDerivative or 2 for derivative")
        df <- data.frame()
        return(df)

    }


    colnames(df) <- rest_cols


    if(length(nodes) > 0) {
        df <- bind_rows(df, xmlToDataFrame(nodes))
        df$seq <- rownames(df)
        df <- df[, rest_cols]

        for(i in 1:length(subnode_names)) {


            df_list <- lapply(1:length(nodes), function(x) {xmlToDataFrame(getNodeSet(nodes[[x]], subnode_names[i]), stringsAsFactors = F)})
            part <- bind_rows(df_list, .id = "seq")
            df <- df %>% left_join(part, by = "seq")

        }

    }



    return(df)


}



get_nonDerivative_df <- function(xml_root, file_name, document, form_type) {


    full_df <- data.frame(matrix(nrow = 0, ncol = 19))
    colnames(full_df) <- c('file_name', 'document', 'form_type', 'transactionOrHolding', 'seq', 'securityTitle', 'transactionDate', 'deemedExecutionDate', 'transactionFormType', 'transactionCode',
                           'equitySwapInvolved', 'transactionTimeliness', 'transactionShares', 'transactionPricePerShare', 'transactionAcquiredDisposedCode', 'sharesOwnedFollowingTransaction',
                           'valueOwnedFollowingTransaction', 'directOrIndirectOwnership', 'natureOfOwnership')


    transaction_df <- scrape_filing_table(xml_root, 1, "Transaction")

    if(dim(transaction_df)[1] > 0) {

        transaction_df$transactionOrHolding <- 'Transaction'
        full_df <- bind_rows(full_df, transaction_df)

    }

    holding_df <- scrape_filing_table(xml_root, 1, "Holding")

    if(dim(holding_df)[1] > 0) {

        holding_df$transactionOrHolding <- 'Holding'
        full_df <- bind_rows(full_df, holding_df)

    }


    full_df$file_name <- file_name
    full_df$document <- document
    full_df$form_type <- form_type

    return(full_df)

}


get_derivative_df <- function(xml_root, file_name, document, form_type) {


    full_df <- data.frame(matrix(nrow = 0, ncol = 26))
    colnames(full_df) <- c('file_name', 'document', 'form_type', 'transactionOrHolding', 'seq', 'securityTitle', 'conversionOrExercisePrice',
                           'transactionDate', 'deemedExecutionDate', 'transactionFormType', 'transactionCode', 'equitySwapInvolved',
                           'transactionTimeliness', 'transactionShares', 'transactionTotalValue', 'transactionPricePerShare',
                           'transactionAcquiredDisposedCode', 'exerciseDate', 'expirationDate', 'underlyingSecurityTitle',
                           'underlyingSecurityShares', 'underlyingSecurityValue', 'sharesOwnedFollowingTransaction',
                           'valueOwnedFollowingTransaction', 'directOrIndirectOwnership', 'natureOfOwnership')


    transaction_df <- scrape_filing_table(xml_root, 2, "Transaction")

    if(dim(transaction_df)[1] > 0) {

        transaction_df$transactionOrHolding <- 'Transaction'
        full_df <- bind_rows(full_df, transaction_df)

    }

    holding_df <- scrape_filing_table(xml_root, 2, "Holding")

    if(dim(holding_df)[1] > 0) {

        holding_df$transactionOrHolding <- 'Holding'
        full_df <- bind_rows(full_df, holding_df)

    }


    full_df$file_name <- file_name
    full_df$document <- document
    full_df$form_type <- form_type

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


get_node_footnotes <- function(node) {

    footnotes <- getNodeSet(node, 'footnoteId')

    if(length(footnotes) != 0) {
        name <- xmlName(node)
        footnote_index <- unlist(lapply(footnotes, function (x) {xmlGetAttr(x, 'id')}))

        df <- data.frame(footnote_index, stringsAsFactors = F)
        df$footnote_variable <- name

        return(df[ , c('footnote_variable', 'footnote_index')])

    } else {

        df <- data.frame(matrix(nrow = 0, ncol = 2))
        colnames(df) <- c('footnote_variable', 'footnote_index')

        for(nd in xmlChildren(node)) {

            part <- get_node_footnotes(nd)

            df <- bind_rows(df, part)


        }

        return(df)

    }

}


get_header_footnotes <- function(xml_root) {

    df <- data.frame(matrix(nrow = 0, ncol = 3))
    colnames(df) <- c('seq', 'footnote_variable', 'footnote_index')

    for(child in xmlChildren(xml_root)){

        name <- xmlName(child)

        if(!(name %in% c('nonDerivativeTable', 'derivativeTable', 'footnotes'))) {

            part <- get_node_footnotes(child)
            if(dim(part)[1] > 0) {

                part$seq <- NA
                df <- bind_rows(df, part)

            }

        }

    }

    return(df)

}


get_derivativeTable_footnotes <- function(xml_root) {

    derivative_tran_nodes <- getNodeSet(getNodeSet(xml_root, 'derivativeTable')[[1]], 'derivativeTransaction')

    df <- data.frame(matrix(nrow = 0, ncol = 3))
    colnames(df) <- c('seq', 'footnote_variable', 'footnote_index')

    for(i in 1:length(derivative_tran_nodes)) {

        part <- get_node_footnotes(derivative_tran_nodes[[i]])
        if(dim(part)[1] > 0) {

            part$seq <- i
            df <- bind_rows(df, part)

        }

    }

    return(df)

}


get_nonDerivativeTable_footnotes <- function(xml_root) {

    nonDerivative_tran_nodes <- getNodeSet(getNodeSet(xml_root, 'nonDerivativeTable')[[1]], 'nonDerivativeTransaction')

    df <- data.frame(matrix(nrow = 0, ncol = 3))
    colnames(df) <- c('seq', 'footnote_variable', 'footnote_index')

    for(i in 1:length(nonDerivative_tran_nodes)) {

        part <- get_node_footnotes(nonDerivative_tran_nodes[[i]])
        if(dim(part)[1] > 0) {

            part$seq <- i
            df <- bind_rows(df, part)

        }

    }

    return(df)

}


get_full_footnote_indices <- function(xml_root) {

    full_df <- data.frame(matrix(nrow = 0, ncol = 4))
    colnames(full_df) <- c('table', 'seq', 'footnote_variable', 'footnote_index')

    header <- get_header_footnotes(xml_root)
    non_deriv <- get_nonDerivativeTable_footnotes(xml_root)
    deriv <- get_derivativeTable_footnotes(xml_root)

    # Assign table names in new column 'table' for each part, if they are not trivial

    if(dim(header)[1] > 0) {
        header$table <- 'header'
    }
    if(dim(non_deriv)[1] > 0) {
        non_deriv$table <- 'table1'
    }
    if(dim(deriv)[1] > 0) {
        deriv$table <- 'table2'
    }

    full_df <- full_df %>% bind_rows(header) %>% bind_rows(non_deriv) %>% bind_rows(deriv) %>% select(table, seq, footnote_variable, footnote_index)

    return(full_df)

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






