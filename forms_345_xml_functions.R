library(RPostgreSQL)
library(XML)
library(rjson)
library(RCurl)
library(dplyr)
library(lubridate)


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

            df_rep_owner_id <- xmlToDataFrame(getNodeSet(node, 'reportingOwnerId'), stringsAsFactors = FALSE)
            df_rep_owner_ad <- xmlToDataFrame(getNodeSet(node, 'reportingOwnerAddress'), stringsAsFactors = FALSE)
            df_rep_owner_rel <- xmlToDataFrame(getNodeSet(node, 'reportingOwnerRelationship'), stringsAsFactors = FALSE)

            part <- bind_cols(df_rep_owner_id, bind_cols(df_rep_owner_ad, df_rep_owner_rel))

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

        sub_names <- lapply(getNodeSet(child, proper_names), xmlName)
        sub_values <- lapply(getNodeSet(child, proper_names), xmlValue)

        df <- data.frame(sub_values, stringsAsFactors = F)
        colnames(df) <- sub_names

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

        nodes_list <- list()
        if(num_tab <- length(non_derivative_table <- getNodeSet(xml_root, 'nonDerivativeTable'))) {

            for(i in 1:num_tab) {
                nodes_list[[i]] <- getNodeSet(non_derivative_table[[i]], c('nonDerivativeTransaction', 'nonDerivativeHolding'))
                num_nodes <- num_nodes + length(nodes_list[[i]])
            }

        } else {

            num_nodes <- 0

        }

        ncol_init <- 6
        rest_cols <- c('seq', 'transactionOrHolding', 'securityTitle', 'transactionDate', 'deemedExecutionDate', 'transactionTimeliness')
        df <- data.frame(matrix(nrow = 0, ncol = ncol_init), stringsAsFactors = F)

    } else if(table == 2) {

        nodes_list <- list()
        if(num_tab <- length(derivative_table <- getNodeSet(xml_root, 'derivativeTable'))) {

            for(i in 1:num_tab) {
                nodes_list[[i]] <- getNodeSet(derivative_table[[i]], c('derivativeTransaction', 'derivativeHolding'))
                num_nodes <- num_nodes + length(nodes_list[[i]])
            }

        } else {

            num_nodes <- 0

        }

        ncol_init <- 9
        rest_cols <- c('seq', 'transactionOrHolding', 'securityTitle', 'conversionOrExercisePrice', 'transactionDate', 'deemedExecutionDate',
                       'transactionTimeliness', 'exerciseDate', 'expirationDate')
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


  full_df <- data.frame(matrix(nrow = 0, ncol = 19), stringsAsFactors = F)
  nonDeriv_columns <- c('file_name', 'document', 'form_type', 'transactionOrHolding', 'seq', 'securityTitle',
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


  full_df <- data.frame(matrix(nrow = 0, ncol = 26), stringsAsFactors = F)
  deriv_columns <- c('file_name', 'document', 'form_type', 'transactionOrHolding', 'seq', 'securityTitle',
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

  if(length(derivative_table <- getNodeSet(xml_root, 'derivativeTable'))) {

    derivative_nodes <- getNodeSet(derivative_table[[1]], c('derivativeTransaction', 'derivativeHolding'))
    num_nodes <- length(derivative_nodes)

  } else {

    num_nodes <- 0

  }


  df <- data.frame(matrix(nrow = 0, ncol = 3))
  colnames(df) <- c('seq', 'footnote_variable', 'footnote_index')

  if(num_nodes) {
    for(i in 1:length(derivative_nodes)) {

      part <- get_node_footnotes(derivative_nodes[[i]])
      if(dim(part)[1] > 0) {

        part$seq <- i
        df <- bind_rows(df, part)

      }

    }

  }


  return(df)

}


get_nonDerivativeTable_footnotes <- function(xml_root) {

  if(length(non_derivative_table <- getNodeSet(xml_root, 'nonDerivativeTable'))) {

    nonDerivative_nodes <- getNodeSet(non_derivative_table[[1]], c('nonDerivativeTransaction', 'nonDerivativeHolding'))
    num_nodes <- length(nonDerivative_nodes)

  } else {

    num_nodes <- 0

  }

  df <- data.frame(matrix(nrow = 0, ncol = 3))
  colnames(df) <- c('seq', 'footnote_variable', 'footnote_index')

  if(num_nodes) {
    for(i in 1:length(nonDerivative_nodes)) {

      part <- get_node_footnotes(nonDerivative_nodes[[i]])
      if(dim(part)[1] > 0) {

        part$seq <- i
        df <- bind_rows(df, part)

      }

    }

  }

  return(df)

}


get_full_footnote_indices <- function(xml_root, file_name, document) {

  full_df <- data.frame(matrix(nrow = 0, ncol = 6))
  colnames(full_df) <- c('file_name', 'document', 'table', 'seq', 'footnote_variable', 'footnote_index')

  header <- get_header_footnotes(xml_root)
  non_deriv <- get_nonDerivativeTable_footnotes(xml_root)
  deriv <- get_derivativeTable_footnotes(xml_root)

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

  full_df <- full_df %>% bind_rows(header) %>% bind_rows(non_deriv) %>% bind_rows(deriv)

  if(nrow(full_df)) {

    full_df$file_name <- file_name
    full_df$document <- document

  }

  full_df <- full_df[, c('file_name', 'document', 'table', 'seq', 'footnote_variable', 'footnote_index')]

  return(full_df)

}


process_345_filing <- function(file_name, document, form_type) {

    pg <- dbConnect(PostgreSQL())

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
        for(i in 1:num_non_derivative_tables) {
            num_tran_i <- length(getNodeSet(non_derivative_table[[i]], 'nonDerivativeTransaction'))
            num_hold_i <- length(getNodeSet(non_derivative_table[[i]], 'nonDerivativeHolding'))
            num_non_derivative_tran <- num_non_derivative_tran + num_tran_i
            num_non_derivative_hold <- num_non_derivative_hold + num_hold_i
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
        for(i in 1:num_non_derivative_tables) {
            num_tran_i <- length(getNodeSet(derivative_table[[i]], 'derivativeTransaction'))
            num_hold_i <- length(getNodeSet(derivative_table[[i]], 'derivativeHolding'))
            num_derivative_tran <- num_derivative_tran + num_tran_i
            num_derivative_hold <- num_derivative_hold + num_hold_i
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

    try({
        if(nrow(header) & got_header) {
            dbWriteTable(pg, c("edgar", "forms345_header"), header, append = TRUE, row.names = FALSE)
        }
        wrote_header <- TRUE}, {wrote_header <- FALSE})

    try({
        if(nrow(rep_own) & got_rep_own) {
            dbWriteTable(pg, c("edgar", "forms345_reporting_owners"), header, append = TRUE, row.names = FALSE)
        }
        wrote_rep_own <- TRUE}, {wrote_rep_own <- FALSE})

    try({
        if(nrow(table1) & got_table1) {
            dbWriteTable(pg, c("edgar", "forms345_table1"), table1, append = TRUE, row.names = FALSE)
        }
        wrote_table1 <- TRUE}, {wrote_table1 <- FALSE})

    try({
        if(nrow(table2) & got_table2) {
            dbWriteTable(pg, c("edgar", "forms345_table2"), table2, append = TRUE, row.names = FALSE)
        }
        wrote_table2 <- TRUE}, {wrote_table2 <- FALSE})

    try({
        if(nrow(footnotes) & got_footnotes) {
            dbWriteTable(pg, c("edgar", "forms345_footnotes"), footnotes, append = TRUE, row.names = FALSE)
        }
        wrote_footnotes <- TRUE}, {wrote_footnotes <- FALSE})

    try({
        if(nrow(footnote_indices) & got_footnote_indices){
            dbWriteTable(pg, c("edgar", "forms345_footnote_indices"), footnote_indices, append = TRUE, row.names = FALSE)
        }
        wrote_footnote_indices <- TRUE}, {wrote_footnote_indices <- FALSE})

    try({
        if(nrow(signatures) & got_signatures){
            dbWriteTable(pg, c("edgar", "forms345_signatures"), signatures, append = TRUE, row.names = FALSE)
        }
        wrote_signatures <- TRUE}, {wrote_signatures <- FALSE})


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

    dbDisconnect(pg)

    return(process_df)

}
