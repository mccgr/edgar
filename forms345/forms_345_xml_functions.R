library(RPostgreSQL)
library(XML)
library(rjson)
library(RCurl)
library(dplyr)
library(lubridate)
library(rvest)
source('~/edgar/filing_docs/get_filing_doc_functions.R')


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


get_xml_root <- function(file_name, document) {

    try({url <- get_filing_document_url(file_name, document)
    fileURL <- file.path(url)
    xml_parse <- xmlParse(getURL(fileURL))
    xml_root <- xmlRoot(xml_parse)
    return(xml_root)}, return(NA))
}

get_filing_doc_html_link <- function(file_name, document) {

    head_url <- get_index_url(file_name)
    table <- read_html(head_url, encoding="Latin1") %>% html_nodes("table") %>% .[[1]]
    table_df <- table %>% html_table()
    doc_index <- which(table_df$Document == document)
    doc_stem <- table %>% html_nodes('tr') %>% html_nodes('a') %>% .[[doc_index]] %>% html_attr("href")
    doc_url <- paste0("https://www.sec.gov", doc_stem)

    return(doc_url)

}


get_xml_root_by_url <- function(url) {

    try({fileURL <- file.path(url)
    xml_parse <- xmlParse(getURL(fileURL))
    xml_root <- xmlRoot(xml_parse)
    return(xml_root)}, return(NA))
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


get_issuer_details <- function(xml_root) {

    df_issuer <- xmlToDataFrame(getNodeSet(xml_root, 'issuer'))

    return(df_issuer)

}

eliminate_trivial_nodes <- function(node_list) {

    new_list <- list()
    for(node in node_list) {

        sub_names <- names(node)

        if(length(sub_names)) {

            old_len <- length(new_list)
            new_list[[old_len + 1]] <- node

        }

    }

    return(new_list)

}


get_rep_owner_details_df <- function(xml_root, file_name, document) {

    rep_owner_nodes <- getNodeSet(xml_root, 'reportingOwner')

    df_rep_owner <- data.frame(matrix(nrow = 0, ncol = 19), stringsAsFactors = FALSE)
    rep_own_col_names <- c('file_name', 'document', 'seq', 'rptOwnerCik', 'rptOwnerCcc', 'rptOwnerName', 'rptOwnerStreet1',
                           'rptOwnerStreet2', 'rptOwnerCity', 'rptOwnerState', 'rptOwnerZipCode',
                           'rptOwnerStateDescription', 'rptOwnerGoodAddress', 'isDirector', 'isOfficer',
                           'isTenPercentOwner', 'isOther', 'officerTitle', 'otherText')

    colnames(df_rep_owner) <- rep_own_col_names

    if(length(rep_owner_nodes)) {

        for(node in rep_owner_nodes) {

            rep_owner_id_nodes <- getNodeSet(node, 'reportingOwnerId')
            rep_owner_id_nodes <- eliminate_trivial_nodes(rep_owner_id_nodes)
            df_rep_owner_id <- xmlToDataFrame(rep_owner_id_nodes, stringsAsFactors = FALSE)
            rep_owner_ad_nodes <- getNodeSet(node, 'reportingOwnerAddress')
            rep_owner_ad_nodes <- eliminate_trivial_nodes(rep_owner_ad_nodes)
            df_rep_owner_ad <- xmlToDataFrame(rep_owner_ad_nodes, stringsAsFactors = FALSE)
            rep_owner_rel_nodes <- getNodeSet(node, 'reportingOwnerRelationship')
            rep_owner_rel_nodes <- eliminate_trivial_nodes(rep_owner_rel_nodes)
            df_rep_owner_rel <- xmlToDataFrame(rep_owner_rel_nodes, stringsAsFactors = FALSE)

            part <- merge(df_rep_owner_id, merge(df_rep_owner_ad, df_rep_owner_rel))

            df_rep_owner <- bind_rows(df_rep_owner, part)

        }

        df_rep_owner$file_name <- file_name
        df_rep_owner$document <- document
        df_rep_owner$seq <- rownames(df_rep_owner)


        for(column in colnames(df_rep_owner)) {

            df_rep_owner[[column]] <- as.character(df_rep_owner[[column]])
            is_blank <- grepl("^[ \t\n\r]*$", df_rep_owner[[column]])
            df_rep_owner[[column]][is_blank] <- NA

        }

        logical_cols <- c('isDirector', 'isOfficer', 'isTenPercentOwner', 'isOther')

        for(column in logical_cols) {

            df_rep_owner[[column]] <- do.call("c", lapply(df_rep_owner[[column]], string_to_boolean))

        }

        df_rep_owner$seq <- as.integer(df_rep_owner$seq)

    }


    df_rep_owner <- df_rep_owner[, rep_own_col_names]

    return(df_rep_owner)

}


get_signature_df <- function(xml_root, file_name, document) {

  sig_cols <- c('file_name', 'document', 'seq', 'signatureName', 'signatureDate')

  df <- xmlToDataFrame(getNodeSet(xml_root, 'ownerSignature'))
  df$seq <- as.integer(rownames(df))
  df$file_name <- file_name
  df$document <- document
  df[['signatureDate']] <- do.call("c", lapply(df[['signatureDate']], extract_date))
  df <- df[, sig_cols]

  return(df)
}



get_header <- function(xml_root, file_name, document) {

    header <- data.frame(matrix(nrow = 0, ncol = 14))

    header_columns <- c('file_name', 'document', 'schemaVersion', 'documentType', 'periodOfReport',
                        'dateOfOriginalSubmission', 'noSecuritiesOwned', 'notSubjectToSection16',
                        'form3HoldingsReported', 'form4TransactionsReported', 'issuerCik', 'issuerName',
                        'issuerTradingSymbol', 'remarks')


    colnames(header) <- header_columns

    schema <- get_variable_value(xml_root, 'schemaVersion')
    doc_type <- get_variable_value(xml_root, 'documentType')
    period <- get_variable_value(xml_root, 'periodOfReport')
    date_orig_sub <- get_variable_value(xml_root, 'dateOfOriginalSubmission')
    no_sec_owned <- get_variable_value(xml_root, 'noSecuritiesOwned')
    no_sect_16 <- get_variable_value(xml_root, 'notSubjectToSection16')
    form_3_holdings <- get_variable_value(xml_root, 'form3HoldingsReported')
    form_4_trans <- get_variable_value(xml_root, 'form4TransactionsReported')

    part_df <- data.frame(schemaVersion = schema, documentType = doc_type, periodOfReport = period,
                          dateOfOriginalSubmission = date_orig_sub, noSecuritiesOwned = no_sec_owned,
                          notSubjectToSection16 = no_sect_16, form3HoldingsReported = form_3_holdings,
                          form4TransactionsReported = form_4_trans, stringsAsFactors = F)

    issuer <- get_issuer_details(xml_root)

    part_df <- bind_cols(part_df, issuer)

    part_df$remarks <- get_variable_value(xml_root, 'remarks')

    header <- bind_rows(header, part_df)

    header$file_name <- file_name
    header$document <- document

    for(column in colnames(header)) {

        header[[column]] <- as.character(header[[column]])
        is_blank <- (header[[column]] == "")
        header[[column]][is_blank] <- NA

    }

    boolean_cols <- c('noSecuritiesOwned', 'notSubjectToSection16', 'form3HoldingsReported', 'form4TransactionsReported')

    for(column in boolean_cols) {

        header[[column]] <- do.call("c", lapply(header[[column]], string_to_boolean))

    }

    date_cols <- c('periodOfReport', 'dateOfOriginalSubmission')

    for(column in date_cols) {

        header[[column]] <- do.call("c", lapply(header[[column]], extract_date))

    }

    return(header)

}


determine_table_entry_type <- function(xml_node) {

  # This function determines if a node in table 1 or 2 corresponds to a Transaction or a Holding

  node_name <- xmlName(xml_node)

  if(grepl('Transaction$', node_name)) {

    return('Transaction')

  } else if(grepl('Holding$', node_name)) {

    return('Holding')

  } else {

    return(NA)

  }


}

single_node_to_df <- function(node, subnode_name) {

    # This function is designed to get rid of the footnoteId/NA columns when getting the dataframe for a subnode_name

    subnode_list <- getNodeSet(node, subnode_name)

    if(length(subnode_list)) {
        child <- subnode_list[[1]]

        proper_names <- names(child)
        proper_names <- proper_names[proper_names != 'footnoteId'] # Get rid of footnotes here

        if(length(proper_names)) {

            sub_names <- lapply(getNodeSet(child, proper_names), xmlName)
            sub_values <- lapply(getNodeSet(child, proper_names), xmlValue)
            df <- data.frame(sub_values, stringsAsFactors = F)
            colnames(df) <- sub_names

        } else {

            df <- data.frame()

        }


    } else {

        df <- data.frame()

    }

    return(df)

}


get_subnode_df <- function(nodes, subnode_name) {

    df_list <- lapply(1:length(nodes), function(x) {single_node_to_df(nodes[[x]], subnode_name)})

    num_row_vec <- unlist(lapply(df_list, nrow))
    num_col_vec <- unlist(lapply(df_list, ncol))

    if(sum(num_row_vec)) {

        index <- which(num_col_vec == max(num_col_vec))[1]

        c_names <- colnames(df_list[[index]])

        na_df <- data.frame(matrix(nrow = 1, ncol = length(c_names)))
        colnames(na_df) <- c_names

        null_indices <- which(num_row_vec == 0)

        for(i in null_indices) {

            df_list[[i]] <- na_df

        }

        part <- bind_rows(df_list, .id = "seq")


    } else {

        part <- data.frame(seq = 1:length(df_list))
        part$seq <- as.character(part$seq)

    }

    return(part)


}

extract_date <- function(string) {

    if(is.na(string)) {

        return(ymd(string, quiet = TRUE))

    } else {reg_match <- regexpr('[0-9]{4}[ -/]*[0-9]{1,2}[ -/]*[0-9]{1,2}', string)
    date <- ymd(regmatches(string, reg_match), quiet = TRUE)

    return(date)

    }
}


scrape_filing_table <- function(xml_root, table) {

    # xml_root: the xml root node
    # table: an integer of 1 for Table 1 (non-derivative), or 2 for Table 2 (derivative)

    subnode_names <- c('transactionCoding', 'postTransactionAmounts', 'ownershipNature', 'transactionAmounts')

    if(table == 1) {

        num_nodes <- 0
        nodes_list <- list()
        if(num_tab <- length(non_derivative_table <- getNodeSet(xml_root, 'nonDerivativeTable'))) {

            for(i in 1:num_tab) {
                nodes_list[[i]] <- getNodeSet(non_derivative_table[[i]], c('nonDerivativeTransaction', 'nonDerivativeHolding'))
                num_nodes <- num_nodes + length(nodes_list[[i]])
            }

        }

        ncol_init <- 7
        rest_cols <- c('seq', 'tab_index', 'transactionOrHolding', 'securityTitle', 'transactionDate',
                       'deemedExecutionDate', 'transactionTimeliness')
        df <- data.frame(matrix(nrow = 0, ncol = ncol_init), stringsAsFactors = F)

    } else if(table == 2) {

        num_nodes <- 0
        nodes_list <- list()
        if(num_tab <- length(derivative_table <- getNodeSet(xml_root, 'derivativeTable'))) {

            for(i in 1:num_tab) {
                nodes_list[[i]] <- getNodeSet(derivative_table[[i]], c('derivativeTransaction', 'derivativeHolding'))
                num_nodes <- num_nodes + length(nodes_list[[i]])
            }

        }

        ncol_init <- 10
        rest_cols <- c('seq', 'tab_index', 'transactionOrHolding', 'securityTitle', 'conversionOrExercisePrice',
                       'transactionDate', 'deemedExecutionDate', 'transactionTimeliness', 'exerciseDate', 'expirationDate')
        df <- data.frame(matrix(nrow = 0, ncol = ncol_init), stringsAsFactors = F)
        subnode_names <- c(subnode_names, 'underlyingSecurity')

    } else {


        print("Error: invalid value for table number entered. Enter 1 for non-derivative or 2 for derivative")
        df <- data.frame()
        return(df)

    }

    colnames(df) <- rest_cols

    if(num_nodes > 0) {

        for(i in 1:num_tab) {

            tab_df <- data.frame(matrix(nrow = 0, ncol = ncol(df)), stringsAsFactors = F)
            colnames(tab_df) <- colnames(df)

            tab_df <- bind_rows(tab_df, xmlToDataFrame(nodes_list[[i]]))
            tab_df$seq <- rownames(tab_df)
            tab_df$tab_index <- i
            tab_df$transactionOrHolding <- unlist(lapply(nodes_list[[i]], determine_table_entry_type))
            tab_df <- tab_df[, rest_cols]


            for(j in 1:length(subnode_names)) {

                part <- get_subnode_df(nodes_list[[i]], subnode_names[j])
                tab_df <- tab_df %>% left_join(part, by = "seq")

            }

            df <- df %>% bind_rows(tab_df)

        }

        for(column in colnames(df)) {

            df[[column]] <- as.character(df[[column]])
            is_blank <- grepl("^[ \t\n\r]*$", df[[column]])
            df[[column]][is_blank] <- NA

        }

    }


    return(df)


}

string_to_boolean <- function(string) {

    # first strip spaces from string

    reduced_string <- gsub("[ \t\n\r]", '', string)

    if(grepl("^[01]$", reduced_string)) {

        return(as.logical(as.integer(reduced_string)))

    } else {

        return(as.logical(reduced_string))

    }


}


get_securities_X0101 <- function(xml_root, table) {

    # xml_root: the xml root node
    # table: an integer of 1 for Table 1 (non-derivative), or 2 for Table 2 (derivative)

    subnode_names <- c('transactionCoding', 'postTransactionAmounts', 'ownershipNature', 'transactionAmounts')

    if(table == 1) {

        nodes <- getNodeSet(xml_root, 'nonDerivativeSecurity')

        rest_cols <- c('seq', 'securityTitle', 'transactionDate', 'deemedExecutionDate', 'transactionTimeliness')
        df <- data.frame(matrix(nrow = 0, ncol = 5), stringsAsFactors = F)

    } else if(table == 2) {

        nodes <- getNodeSet(xml_root, 'derivativeSecurity')

        rest_cols <- c('seq', 'securityTitle', 'conversionOrExercisePrice', 'transactionDate', 'deemedExecutionDate',
                       'transactionTimeliness', 'exerciseDate', 'expirationDate')
        df <- data.frame(matrix(nrow = 0, ncol = 8), stringsAsFactors = F)
        subnode_names <- c(subnode_names, 'underlyingSecurity')

    } else {


        print("Error: invalid value for table number entered. Enter 1 for non-derivative or 2 for derivative")
        df <- data.frame()
        return(df)

    }


    colnames(df) <- rest_cols

    if(length(nodes)) {

        df <- bind_rows(df, xmlToDataFrame(nodes))
        df$seq <- rownames(df)
        df <- df[, rest_cols]


        for(i in 1:length(subnode_names)) {

            part <- get_subnode_df(nodes, subnode_names[i])
            df <- df %>% left_join(part, by = "seq")

        }


        for(column in colnames(df)) {

            df[[column]] <- as.character(df[[column]])
            is_blank <- grepl("^[ \t\n\r]*$", df[[column]])
            df[[column]][is_blank] <- NA

        }

        df$transactionOrHolding <- ifelse(is.na(df$transactionDate), 'Holding', 'Transaction')

    }





    return(df)


}



get_nonDerivative_df <- function(xml_root, file_name, document, form_type) {


  full_df <- data.frame(matrix(nrow = 0, ncol = 20), stringsAsFactors = F)
  nonDeriv_columns <- c('file_name', 'document', 'form_type', 'transactionOrHolding', 'seq', 'tab_index', 'securityTitle',
                        'transactionDate', 'deemedExecutionDate', 'transactionFormType', 'transactionCode',
                        'equitySwapInvolved', 'transactionTimeliness', 'transactionShares', 'transactionPricePerShare',
                        'transactionAcquiredDisposedCode', 'sharesOwnedFollowingTransaction',
                        'valueOwnedFollowingTransaction', 'directOrIndirectOwnership', 'natureOfOwnership')

  colnames(full_df) <- nonDeriv_columns


  part <- scrape_filing_table(xml_root, 1)
  part_old <- get_securities_X0101(xml_root, 1)

  if('transactionValue' %in% colnames(part_old)) {

      colnames(part_old)[colnames(part_old) == 'transactionValue'] <- 'transactionPricePerShare'

  }

  scraping_df <- bind_rows(part, part_old)

  if(nrow(scraping_df)) {

    full_df <- bind_rows(full_df, scraping_df)

    full_df$file_name <- file_name
    full_df$document <- document
    full_df$form_type <- form_type

    for(column in colnames(full_df)) {

      full_df[[column]] <- as.character(full_df[[column]])

    }


    full_df$seq <- as.integer(full_df$seq)
    full_df[['equitySwapInvolved']] <- do.call("c", lapply(full_df[['equitySwapInvolved']], string_to_boolean))

    numeric_cols <- c('transactionShares', 'transactionPricePerShare', 'sharesOwnedFollowingTransaction',
                      'valueOwnedFollowingTransaction')

    for(column in numeric_cols) {

      full_df[[column]] <- as.numeric(full_df[[column]])

    }

    date_cols <- c('transactionDate', 'deemedExecutionDate')

    for(column in date_cols) {

        full_df[[column]] <- do.call("c", lapply(full_df[[column]], extract_date))

    }

    full_df <- full_df[, nonDeriv_columns]

  }



  return(full_df)

}


get_derivative_df <- function(xml_root, file_name, document, form_type) {


  full_df <- data.frame(matrix(nrow = 0, ncol = 27), stringsAsFactors = F)
  deriv_columns <- c('file_name', 'document', 'form_type', 'transactionOrHolding', 'seq', 'tab_index', 'securityTitle',
                     'conversionOrExercisePrice', 'transactionDate', 'deemedExecutionDate', 'transactionFormType',
                     'transactionCode', 'equitySwapInvolved', 'transactionTimeliness', 'transactionShares',
                     'transactionTotalValue', 'transactionPricePerShare', 'transactionAcquiredDisposedCode',
                     'exerciseDate', 'expirationDate', 'underlyingSecurityTitle', 'underlyingSecurityShares',
                     'underlyingSecurityValue', 'sharesOwnedFollowingTransaction', 'valueOwnedFollowingTransaction',
                     'directOrIndirectOwnership', 'natureOfOwnership')

  colnames(full_df) <- deriv_columns


  part <- scrape_filing_table(xml_root, 2)
  part_old <- get_securities_X0101(xml_root, 2)

  if('transactionValue' %in% colnames(part_old)) {

      colnames(part_old)[colnames(part_old) == 'transactionValue'] <- 'transactionPricePerShare'

  }

  scraping_df <- bind_rows(part, part_old)

  if(nrow(scraping_df)) {

    full_df <- bind_rows(full_df, scraping_df)

    full_df$file_name <- file_name
    full_df$document <- document
    full_df$form_type <- form_type


    for(column in colnames(full_df)) {

      full_df[[column]] <- as.character(full_df[[column]])

    }


    full_df$seq <- as.integer(full_df$seq)
    full_df[['equitySwapInvolved']] <- do.call("c", lapply(full_df[['equitySwapInvolved']], string_to_boolean))

    numeric_cols <- c('conversionOrExercisePrice', 'transactionShares', 'transactionTotalValue', 'transactionPricePerShare',
                      'underlyingSecurityShares', 'underlyingSecurityValue', 'sharesOwnedFollowingTransaction',
                      'valueOwnedFollowingTransaction')

    for(column in numeric_cols) {

      full_df[[column]] <- as.numeric(full_df[[column]])

    }

    date_cols <- c('transactionDate', 'deemedExecutionDate', 'exerciseDate', 'expirationDate')

    for(column in date_cols) {

        full_df[[column]] <- do.call("c", lapply(full_df[[column]], extract_date))

    }

    full_df <- full_df[, deriv_columns]

  }



  return(full_df)

}


get_footnotes <- function(xml_root, file_name, document) {

  if(length(footnote_table <- getNodeSet(xml_root, 'footnotes'))) {
    footnotes <- getNodeSet(footnote_table[[1]], 'footnote')
    num_footnotes <- length(footnotes)

  } else {
    #ie. No table, no notes
    num_footnotes <- 0
  }


  f_index <- c()
  f_footnote <- c()

  if(num_footnotes) {

    for(i in 1:num_footnotes) {

      f_index <- c(f_index, xmlAttrs(footnotes[[i]])[[1]])
      f_footnote <- c(f_footnote, xmlValue(footnotes[[i]]))

    }

    footnotes_df <- data.frame(file_name = file_name, document = document, footnote_index = f_index, footnote = f_footnote, stringsAsFactors = F)

  } else {

    footnotes_df <- data.frame(matrix(nrow = 0, ncol = 4), stringsAsFactors = F)
    colnames(footnotes_df) <- c('file_name', 'document', 'footnote_index', 'footnote')

  }


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

    df <- data.frame(matrix(nrow = 0, ncol = 2), stringsAsFactors = F)
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

    non_header_nodes <- c('nonDerivativeTable', 'derivativeTable', 'nonDerivativeSecurity', 'derivativeSecurity',
                          'reportingOwner', 'footnotes', 'ownerSignature')

    if(!(name %in% non_header_nodes)) {

      part <- get_node_footnotes(child)
      if(dim(part)[1] > 0) {

        part$seq <- NA
        df <- bind_rows(df, part)

      }

    }

  }

  return(df)

}


get_table_footnotes_df <- function(nodes) {

    # This is a function for turning lists of nodes with the same name into dataframes containing the footnote
    # indices. This is relevant for the tables regarding the reporting owners, tables 1 and 2, and signatures

    num_nodes <- length(nodes)

    df <- data.frame(matrix(nrow = 0, ncol = 3))
    colnames(df) <- c('seq', 'footnote_variable', 'footnote_index')

    if(num_nodes) {
        for(i in 1:num_nodes) {

            part <- get_node_footnotes(nodes[[i]])
            if(dim(part)[1] > 0) {

                part$seq <- i
                df <- bind_rows(df, part)

            }

        }

    }

    return(df)

}

get_rep_owner_footnotes <- function(xml_root) {

    rep_owner_nodes <- getNodeSet(xml_root, 'reportingOwner')
    df <- get_table_footnotes_df(rep_owner_nodes)

    return(df)

}

get_signature_footnotes <- function(xml_root) {

    signature_nodes <- getNodeSet(xml_root, 'ownerSignature')
    df <- get_table_footnotes_df(signature_nodes)

    return(df)

}


get_derivativeTable_footnotes <- function(xml_root) {

  deriv_sec <- getNodeSet(xml_root, 'derivativeSecurity')
  deriv_sec_df <- get_table_footnotes_df(deriv_sec)

  deriv_sec_df$footnote_variable[deriv_sec_df$footnote_variable == 'transactionValue'] <- 'transactionPricePerShare'

  if(num_tab <- length(derivative_table <- getNodeSet(xml_root, 'derivativeTable'))) {

      deriv_tranhold_df <- data.frame(matrix(nrow = 0, ncol = 4))
      colnames(deriv_tranhold_df) <- c('tab_index', 'seq', 'footnote_variable', 'footnote_index')
      for(i in 1:num_tab) {

          deriv_tranhold_i <- getNodeSet(derivative_table[[1]], c('derivativeTransaction', 'derivativeHolding'))
          part <- get_table_footnotes_df(deriv_tranhold_i)
          if(nrow(part)) {

              part$tab_index <- i
              deriv_tranhold_df <- bind_rows(deriv_tranhold_df, part)

          }

      }

      full_df <- bind_rows(deriv_sec_df, deriv_tranhold_df)

  } else {

      full_df <- deriv_sec_df

  }

  return(full_df)

}


get_nonDerivativeTable_footnotes <- function(xml_root) {

    non_deriv_sec <- getNodeSet(xml_root, 'nonDerivativeSecurity')
    non_deriv_sec_df <- get_table_footnotes_df(non_deriv_sec)

    non_deriv_sec_df$footnote_variable[non_deriv_sec_df$footnote_variable == 'transactionValue'] <- 'transactionPricePerShare'

    if(num_tab <- length(non_derivative_table <- getNodeSet(xml_root, 'nonDerivativeTable'))) {

        non_deriv_tranhold_df <- data.frame(matrix(nrow = 0, ncol = 4))
        colnames(non_deriv_tranhold_df) <- c('tab_index', 'seq', 'footnote_variable', 'footnote_index')

        for(i in 1:num_tab) {

            non_deriv_tranhold_i <- getNodeSet(non_derivative_table[[i]], c('nonDerivativeTransaction', 'nonDerivativeHolding'))
            part <- get_table_footnotes_df(non_deriv_tranhold_i)
            if(nrow(part)) {

                part$tab_index <- i
                non_deriv_tranhold_df <- bind_rows(non_deriv_tranhold_df, part)

            }

        }

        full_df <- bind_rows(non_deriv_sec_df, non_deriv_tranhold_df)

    } else {

        full_df <- non_deriv_sec_df

    }


    return(full_df)

}


get_full_footnote_indices <- function(xml_root, file_name, document) {

    full_df <- data.frame(matrix(nrow = 0, ncol = 7))
    colnames(full_df) <- c('file_name', 'document', 'table', 'tab_index', 'seq', 'footnote_variable', 'footnote_index')

    header <- get_header_footnotes(xml_root)
    non_deriv <- get_nonDerivativeTable_footnotes(xml_root)
    deriv <- get_derivativeTable_footnotes(xml_root)
    rep_owner <- get_rep_owner_footnotes(xml_root)
    signature <- get_signature_footnotes(xml_root)

    # Assign table names in new column 'table' for each part, if they are not trivial

    if(nrow(header)) {
        header$table <- 'header'
    }
    if(nrow(non_deriv)) {
        non_deriv$table <- 'table1'
    }
    if(nrow(deriv)) {
        deriv$table <- 'table2'
    }
    if(nrow(rep_owner)) {
        rep_owner$table <- 'reporting_owners'
    }
    if(nrow(signature)) {
        signature$table <- 'signatures'
    }

    full_df <- full_df %>% bind_rows(header) %>% bind_rows(non_deriv) %>% bind_rows(deriv) %>% bind_rows(rep_owner) %>% bind_rows(signature)

    if(nrow(full_df)) {

        full_df$file_name <- file_name
        full_df$document <- document

    }

    full_df <- full_df[, c('file_name', 'document', 'table', 'tab_index', 'seq', 'footnote_variable', 'footnote_index')]

    return(full_df)

}


process_345_filing <- function(file_name, document, form_type) {

    pg <- dbConnect(PostgreSQL())

    try({

        try({
            xml_root <- get_xml_root(file_name, document)
            got_xml <- TRUE}, {got_xml <- FALSE})

        try({
            header <- get_header(xml_root, file_name, document)
            got_header <- TRUE}, {got_header <- FALSE})

        try({
            rep_own <- get_rep_owner_details_df(xml_root, file_name, document)
            got_rep_own <- TRUE}, {got_rep_own <- FALSE})

        try({
            table1 <- get_nonDerivative_df(xml_root, file_name, document, form_type)
            got_table1 <- TRUE}, {got_table1 <- FALSE})

        try({non_derivative_table <- getNodeSet(xml_root, 'nonDerivativeTable')
            num_non_derivative_tables <- length(non_derivative_table)

            num_non_derivative_tran <- 0
            num_non_derivative_hold <- 0

            if(num_non_derivative_tables) {

                for(i in 1:num_non_derivative_tables) {
                    num_tran_i <- length(getNodeSet(non_derivative_table[[i]], 'nonDerivativeTransaction'))
                    num_hold_i <- length(getNodeSet(non_derivative_table[[i]], 'nonDerivativeHolding'))
                    num_non_derivative_tran <- num_non_derivative_tran + num_tran_i
                    num_non_derivative_hold <- num_non_derivative_hold + num_hold_i
                }

            }

            num_non_derivative_sec <- length(getNodeSet(xml_root, 'nonDerivativeSecurity'))

            total_non_derivative_nodes <- num_non_derivative_tran + num_non_derivative_hold + num_non_derivative_sec
            }, {num_non_derivative_tables <- NA; num_non_derivative_tran <- NA; num_non_derivative_hold <- NA;
            num_non_derivative_sec <- NA; total_non_derivative_nodes <- NA})

        try({
            table2 <- get_derivative_df(xml_root, file_name, document, form_type)
            got_table2 <- TRUE}, {got_table2 <- FALSE})

        try({derivative_table <- getNodeSet(xml_root, 'derivativeTable')
            num_derivative_tables <- length(derivative_table)

            num_derivative_tran <- 0
            num_derivative_hold <- 0

            if(num_derivative_tables) {

                for(i in 1:num_derivative_tables) {
                num_tran_i <- length(getNodeSet(derivative_table[[i]], 'derivativeTransaction'))
                num_hold_i <- length(getNodeSet(derivative_table[[i]], 'derivativeHolding'))
                num_derivative_tran <- num_derivative_tran + num_tran_i
                num_derivative_hold <- num_derivative_hold + num_hold_i
                }
            }

            num_derivative_sec <- length(getNodeSet(xml_root, 'derivativeSecurity'))

            total_derivative_nodes <- num_derivative_tran + num_derivative_hold + num_derivative_sec
            }, {num_derivative_tables <- NA; num_derivative_tran <- NA; num_derivative_hold <- NA;
            num_derivative_sec <- NA; total_derivative_nodes <- NA})

        try({
            footnotes <- get_footnotes(xml_root, file_name, document)
            got_footnotes <- TRUE}, {got_footnotes <- FALSE})

        try({
            footnote_indices <- get_full_footnote_indices(xml_root, file_name, document)
            got_footnote_indices <- TRUE}, {got_footnote_indices <- FALSE})

        try({
            signatures <- get_signature_df(xml_root, file_name, document)
            got_signatures <- TRUE}, {got_signatures <- FALSE})

        if(got_header) {

            try({
                if(nrow(header)) {
                    dbWriteTable(pg, c("edgar", "forms345_header"), header, append = TRUE, row.names = FALSE)
                }
                wrote_header <- TRUE}, {wrote_header <- FALSE})

        } else {

            wrote_header <- FALSE

        }

        if(got_rep_own) {

            try({
                if(nrow(rep_own)) {
                    dbWriteTable(pg, c("edgar", "forms345_reporting_owners"), rep_own, append = TRUE, row.names = FALSE)
                }
                wrote_rep_own <- TRUE}, {wrote_rep_own <- FALSE})

        } else {

            wrote_rep_own <- FALSE

        }

        if(got_table1) {

            try({
                if(nrow(table1)) {
                    dbWriteTable(pg, c("edgar", "forms345_table1"), table1, append = TRUE, row.names = FALSE)
                }
                wrote_table1 <- TRUE}, {wrote_table1 <- FALSE})

        } else {

            wrote_table1 <- FALSE

        }

        if(got_table2) {

            try({
                if(nrow(table2)) {
                    dbWriteTable(pg, c("edgar", "forms345_table2"), table2, append = TRUE, row.names = FALSE)
                }
                wrote_table2 <- TRUE}, {wrote_table2 <- FALSE})

        } else {

            wrote_table2 <- FALSE

        }

        if(got_footnotes) {

            try({
                if(nrow(footnotes)) {
                    dbWriteTable(pg, c("edgar", "forms345_footnotes"), footnotes, append = TRUE, row.names = FALSE)
                }
                wrote_footnotes <- TRUE}, {wrote_footnotes <- FALSE})

        } else {

            wrote_footnotes <- FALSE

        }

        if(got_footnote_indices) {

            try({
                if(nrow(footnote_indices)){
                    dbWriteTable(pg, c("edgar", "forms345_footnote_indices"), footnote_indices, append = TRUE, row.names = FALSE)
                }
                wrote_footnote_indices <- TRUE}, {wrote_footnote_indices <- FALSE})

        } else {

            wrote_footnote_indices <- FALSE

        }

        if(got_signatures) {

            try({
                if(nrow(signatures)){
                    dbWriteTable(pg, c("edgar", "forms345_signatures"), signatures, append = TRUE, row.names = FALSE)
                }
                wrote_signatures <- TRUE}, {wrote_signatures <- FALSE})

        } else {

            wrote_signatures <- FALSE

        }


        process_df <- data.frame(file_name = file_name, document = document, form_type = form_type, got_xml = got_xml,
                                 got_header = got_header, got_rep_own = got_rep_own, got_table1 = got_table1,
                                 num_non_derivative_tables = num_non_derivative_tables,
                                 num_non_derivative_tran = num_non_derivative_tran, num_non_derivative_hold = num_non_derivative_hold,
                                 num_non_derivative_sec = num_non_derivative_sec, total_non_derivative_nodes = total_non_derivative_nodes,
                                 got_table2 = got_table2, num_derivative_tables = num_derivative_tables,
                                 num_derivative_tran = num_derivative_tran, num_derivative_hold = num_derivative_hold,
                                 num_derivative_sec= num_derivative_sec, total_derivative_nodes = total_derivative_nodes,
                                 got_footnotes = got_footnotes, got_footnote_indices = got_footnote_indices,
                                 got_signatures = got_signatures, wrote_header = wrote_header, wrote_rep_own = wrote_rep_own,
                                 wrote_table1 = wrote_table1, wrote_table2 = wrote_table2, wrote_footnotes = wrote_footnotes,
                                 wrote_footnote_indices = wrote_footnote_indices, wrote_signatures = wrote_signatures,
                                 stringsAsFactors = FALSE)

        dbWriteTable(pg, c("edgar", "forms345_xml_process_table"), process_df, append = TRUE, row.names = FALSE)

        fully_processed <- TRUE

    }, {fully_processed <- FALSE})

    dbDisconnect(pg)

    return(fully_processed)

}


delete_345_data <- function(file_name, document) {

    pg <- dbConnect(PostgreSQL())

    table_list <- c('forms345_header', 'forms345_reporting_owners', 'forms345_table1', 'forms345_table2',
                    'forms345_footnotes', 'forms345_footnote_indices', 'forms345_signatures',
                    'forms345_xml_process_table', 'forms345_xml_fully_processed')

    for(table_name in table_list) {

    query <- paste0("DELETE FROM edgar.", table_name, " WHERE file_name = '", file_name, "' AND document = '", document, "'")
    dbGetQuery(pg, query)

    }

    dbDisconnect(pg)

}


process_345_filing_alt <- function(file_name, document, form_type, doc_url) {

    pg <- dbConnect(PostgreSQL())

    try({

        try({
            xml_root <- get_xml_root_by_url(doc_url)
            got_xml <- TRUE}, {got_xml <- FALSE})

        try({
            header <- get_header(xml_root, file_name, document)
            got_header <- TRUE}, {got_header <- FALSE})

        try({
            rep_own <- get_rep_owner_details_df(xml_root, file_name, document)
            got_rep_own <- TRUE}, {got_rep_own <- FALSE})

        try({
            table1 <- get_nonDerivative_df(xml_root, file_name, document, form_type)
            got_table1 <- TRUE}, {got_table1 <- FALSE})

        try({non_derivative_table <- getNodeSet(xml_root, 'nonDerivativeTable')
        num_non_derivative_tables <- length(non_derivative_table)

        num_non_derivative_tran <- 0
        num_non_derivative_hold <- 0

        if(num_non_derivative_tables) {

            for(i in 1:num_non_derivative_tables) {
                num_tran_i <- length(getNodeSet(non_derivative_table[[i]], 'nonDerivativeTransaction'))
                num_hold_i <- length(getNodeSet(non_derivative_table[[i]], 'nonDerivativeHolding'))
                num_non_derivative_tran <- num_non_derivative_tran + num_tran_i
                num_non_derivative_hold <- num_non_derivative_hold + num_hold_i
            }

        }

        num_non_derivative_sec <- length(getNodeSet(xml_root, 'nonDerivativeSecurity'))

        total_non_derivative_nodes <- num_non_derivative_tran + num_non_derivative_hold + num_non_derivative_sec
        }, {num_non_derivative_tables <- NA; num_non_derivative_tran <- NA; num_non_derivative_hold <- NA;
        num_non_derivative_sec <- NA; total_non_derivative_nodes <- NA})

        try({
            table2 <- get_derivative_df(xml_root, file_name, document, form_type)
            got_table2 <- TRUE}, {got_table2 <- FALSE})

        try({derivative_table <- getNodeSet(xml_root, 'derivativeTable')
        num_derivative_tables <- length(derivative_table)

        num_derivative_tran <- 0
        num_derivative_hold <- 0

        if(num_derivative_tables) {

            for(i in 1:num_derivative_tables) {
                num_tran_i <- length(getNodeSet(derivative_table[[i]], 'derivativeTransaction'))
                num_hold_i <- length(getNodeSet(derivative_table[[i]], 'derivativeHolding'))
                num_derivative_tran <- num_derivative_tran + num_tran_i
                num_derivative_hold <- num_derivative_hold + num_hold_i
            }
        }

        num_derivative_sec <- length(getNodeSet(xml_root, 'derivativeSecurity'))

        total_derivative_nodes <- num_derivative_tran + num_derivative_hold + num_derivative_sec
        }, {num_derivative_tables <- NA; num_derivative_tran <- NA; num_derivative_hold <- NA;
        num_derivative_sec <- NA; total_derivative_nodes <- NA})

        try({
            footnotes <- get_footnotes(xml_root, file_name, document)
            got_footnotes <- TRUE}, {got_footnotes <- FALSE})

        try({
            footnote_indices <- get_full_footnote_indices(xml_root, file_name, document)
            got_footnote_indices <- TRUE}, {got_footnote_indices <- FALSE})

        try({
            signatures <- get_signature_df(xml_root, file_name, document)
            got_signatures <- TRUE}, {got_signatures <- FALSE})

        if(got_header) {

            try({
                if(nrow(header)) {
                    dbWriteTable(pg, c("edgar", "forms345_header"), header, append = TRUE, row.names = FALSE)
                }
                wrote_header <- TRUE}, {wrote_header <- FALSE})

        } else {

            wrote_header <- FALSE

        }

        if(got_rep_own) {

            try({
                if(nrow(rep_own)) {
                    dbWriteTable(pg, c("edgar", "forms345_reporting_owners"), rep_own, append = TRUE, row.names = FALSE)
                }
                wrote_rep_own <- TRUE}, {wrote_rep_own <- FALSE})

        } else {

            wrote_rep_own <- FALSE

        }

        if(got_table1) {

            try({
                if(nrow(table1)) {
                    dbWriteTable(pg, c("edgar", "forms345_table1"), table1, append = TRUE, row.names = FALSE)
                }
                wrote_table1 <- TRUE}, {wrote_table1 <- FALSE})

        } else {

            wrote_table1 <- FALSE

        }

        if(got_table2) {

            try({
                if(nrow(table2)) {
                    dbWriteTable(pg, c("edgar", "forms345_table2"), table2, append = TRUE, row.names = FALSE)
                }
                wrote_table2 <- TRUE}, {wrote_table2 <- FALSE})

        } else {

            wrote_table2 <- FALSE

        }

        if(got_footnotes) {

            try({
                if(nrow(footnotes)) {
                    dbWriteTable(pg, c("edgar", "forms345_footnotes"), footnotes, append = TRUE, row.names = FALSE)
                }
                wrote_footnotes <- TRUE}, {wrote_footnotes <- FALSE})

        } else {

            wrote_footnotes <- FALSE

        }

        if(got_footnote_indices) {

            try({
                if(nrow(footnote_indices)){
                    dbWriteTable(pg, c("edgar", "forms345_footnote_indices"), footnote_indices, append = TRUE, row.names = FALSE)
                }
                wrote_footnote_indices <- TRUE}, {wrote_footnote_indices <- FALSE})

        } else {

            wrote_footnote_indices <- FALSE

        }

        if(got_signatures) {

            try({
                if(nrow(signatures)){
                    dbWriteTable(pg, c("edgar", "forms345_signatures"), signatures, append = TRUE, row.names = FALSE)
                }
                wrote_signatures <- TRUE}, {wrote_signatures <- FALSE})

        } else {

            wrote_signatures <- FALSE

        }


        process_df <- data.frame(file_name = file_name, document = document, form_type = form_type, got_xml = got_xml,
                                 got_header = got_header, got_rep_own = got_rep_own, got_table1 = got_table1,
                                 num_non_derivative_tables = num_non_derivative_tables,
                                 num_non_derivative_tran = num_non_derivative_tran, num_non_derivative_hold = num_non_derivative_hold,
                                 num_non_derivative_sec = num_non_derivative_sec, total_non_derivative_nodes = total_non_derivative_nodes,
                                 got_table2 = got_table2, num_derivative_tables = num_derivative_tables,
                                 num_derivative_tran = num_derivative_tran, num_derivative_hold = num_derivative_hold,
                                 num_derivative_sec= num_derivative_sec, total_derivative_nodes = total_derivative_nodes,
                                 got_footnotes = got_footnotes, got_footnote_indices = got_footnote_indices,
                                 got_signatures = got_signatures, wrote_header = wrote_header, wrote_rep_own = wrote_rep_own,
                                 wrote_table1 = wrote_table1, wrote_table2 = wrote_table2, wrote_footnotes = wrote_footnotes,
                                 wrote_footnote_indices = wrote_footnote_indices, wrote_signatures = wrote_signatures,
                                 stringsAsFactors = FALSE)

        dbWriteTable(pg, c("edgar", "forms345_xml_process_table"), process_df, append = TRUE, row.names = FALSE)

        fully_processed <- TRUE

    }, {fully_processed <- FALSE})

    dbDisconnect(pg)

    return(fully_processed)

}



update_xml_fully_processed <- function(file_name, document, processed) {

    pg <- dbConnect(PostgreSQL())


    query_pt1 <- "UPDATE TABLE edgar.forms345_xml_fully_processed "
    query_pt2 <- paste0("SET fully_processed = ", as.character(processed), " ")
    query_pt3 <- paste0("WHERE file_name = ", file_name, " AND document = ", document)
    full_query <- paste0(query_pt1, query_pt2, query_pt3)

    result <- try(dbExecute(pg, full_query))

    if(!inherits(result, "try-error")) {
        success <- (result > 0)
    } else {
        success <- FALSE
    }

    dbDisconnect(pg)

    return(success)

}
