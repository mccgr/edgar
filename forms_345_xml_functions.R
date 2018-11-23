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

get_rep_owner_details <- function(xml_root) {

    rep_owner_node <- getNodeSet(xml_root, 'reportingOwner')[[1]]

    df_rep_owner_id <- xmlToDataFrame(getNodeSet(rep_owner_node, 'reportingOwnerId'))
    df_rep_owner_ad <- xmlToDataFrame(getNodeSet(rep_owner_node, 'reportingOwnerAddress'))
    df_rep_owner_rel <- xmlToDataFrame(getNodeSet(rep_owner_node, 'reportingOwnerRelationship'))

    df_rep_owner <- bind_cols(df_rep_owner_id, bind_cols(df_rep_owner_ad, df_rep_owner_rel))

    return(df_rep_owner)

}


get_signature_df <- function(xml_root, file_name, document) {
  
  sig_cols <- c('file_name', 'document', 'seq', 'signatureName', 'signatureDate')
  
  df <- xmlToDataFrame(getNodeSet(xml_root, 'ownerSignature'))
  df$seq <- as.integer(rownames(df))
  df$file_name <- file_name
  df$document <- document
  df$signatureDate <- ymd(df$signatureDate, quiet = TRUE)
  df <- df[, sig_cols]
  
  return(df)
}



get_header <- function(xml_root, file_name, document) {
  
  header <- data.frame(matrix(nrow = 0, ncol = 30))
  
  header_columns <- c('file_name', 'document', 'schemaVersion', 'documentType', 'periodOfReport',
                      'dateOfOriginalSubmission', 'noSecuritiesOwned', 'notSubjectToSection16',
                      'form3HoldingsReported', 'form4TransactionsReported', 'issuerCik', 'issuerName',
                      'issuerTradingSymbol', 'rptOwnerCik', 'rptOwnerCcc', 'rptOwnerName', 'rptOwnerStreet1',
                      'rptOwnerStreet2', 'rptOwnerCity', 'rptOwnerState', 'rptOwnerZipCode', 'rptOwnerStateDescription',
                      'rptOwnerGoodAddress', 'isDirector', 'isOfficer', 'isTenPercentOwner', 'isOther', 'officerTitle',
                      'otherText', 'remarks')
  
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
  rep_owner <- get_rep_owner_details(xml_root)
  
  part_df <- bind_cols(part_df, issuer)
  part_df <- bind_cols(part_df, rep_owner)
  
  part_df$remarks <- get_variable_value(xml_root, 'remarks')
  
  header <- bind_rows(header, part_df)
  
  header$file_name <- file_name
  header$document <- document
  
  for(column in colnames(header)) {
    
    header[[column]] <- as.character(header[[column]])
    is_blank <- (header[[column]] == "")
    header[[column]][is_blank] <- NA
    
  }
  
  boolean_cols <- c('noSecuritiesOwned', 'notSubjectToSection16', 'form3HoldingsReported', 'form4TransactionsReported',
                    'rptOwnerGoodAddress', 'isDirector', 'isOfficer', 'isTenPercentOwner', 'isOther')
  
  for(column in boolean_cols) {
    
    header[[column]] <- as.logical(as.integer(header[[column]]))
    
  }
  
  date_cols <- c('periodOfReport', 'dateOfOriginalSubmission')
  
  for(column in date_cols) {
    
    header[[column]] <- ymd(header[[column]], quiet = TRUE)
    
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


get_subnode_df <- function(nodes, subnode_name) {
  
  df_list <- lapply(1:length(nodes), function(x) {xmlToDataFrame(getNodeSet(nodes[[x]], subnode_name), stringsAsFactors = F)})
  
  num_row_vec <- unlist(lapply(df_list, nrow))
  
  if(sum(num_row_vec)) {
    
    index <- which(num_row_vec > 0)[1]
    
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




scrape_filing_table <- function(xml_root, table) {
  
  # xml_root: the xml root node
  # table: an integer of 1 for Table 1 (non-derivative), or 2 for Table 2 (derivative)
  
  subnode_names <- c('transactionCoding', 'postTransactionAmounts', 'ownershipNature', 'transactionAmounts')
  
  if(table == 1) {
    
    if(length(non_derivative_table <- getNodeSet(xml_root, 'nonDerivativeTable'))) {
      
      nodes <- getNodeSet(non_derivative_table[[1]], c('nonDerivativeTransaction', 'nonDerivativeHolding'))
      num_nodes <- length(nodes)
      
    } else {
      
      num_nodes <- 0
      
    }
    
    rest_cols <- c('seq', 'transactionOrHolding', 'securityTitle', 'transactionDate', 'deemedExecutionDate', 'transactionTimeliness')
    df <- data.frame(matrix(nrow = 0, ncol = 6), stringsAsFactors = F)
    
  } else if(table == 2) {
    
    if(length(derivative_table <- getNodeSet(xml_root, 'derivativeTable'))) {
      
      nodes <- getNodeSet(derivative_table[[1]], c('derivativeTransaction', 'derivativeHolding'))
      num_nodes <- length(nodes)
      
    } else {
      
      num_nodes <- 0
      
    }
    
    rest_cols <- c('seq', 'transactionOrHolding', 'securityTitle', 'conversionOrExercisePrice', 'transactionDate', 'deemedExecutionDate',
                   'transactionTimeliness', 'exerciseDate', 'expirationDate')
    df <- data.frame(matrix(nrow = 0, ncol = 9), stringsAsFactors = F)
    subnode_names <- c(subnode_names, 'underlyingSecurity')
    
  } else {
    
    
    print("Error: invalid value for table number entered. Enter 1 for non-derivative or 2 for derivative")
    df <- data.frame()
    return(df)
    
  }
  
  
  colnames(df) <- rest_cols
  
  if(num_nodes > 0) {
    
    df <- bind_rows(df, xmlToDataFrame(nodes))
    df$seq <- rownames(df)
    df$transactionOrHolding <- unlist(lapply(nodes, determine_table_entry_type))
    df <- df[, rest_cols]
    
    
    for(i in 1:length(subnode_names)) {
      
      part <- get_subnode_df(nodes, subnode_names[i])
      df <- df %>% left_join(part, by = "seq")
      
    }
    
  }
  
  
  for(column in colnames(df)) {
    
    df[[column]] <- as.character(df[[column]])
    is_blank <- (df[[column]] == "")
    df[[column]][is_blank] <- NA
    
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
  
  
  scraping_df <- scrape_filing_table(xml_root, 1)
  
  if(nrow(scraping_df)) {
    
    full_df <- bind_rows(full_df, scraping_df)
    
    full_df$file_name <- file_name
    full_df$document <- document
    full_df$form_type <- form_type
    
    for(column in colnames(full_df)) {
      
      full_df[[column]] <- as.character(full_df[[column]])
      
    }
    
    
    full_df$seq <- as.integer(full_df$seq)
    full_df$equitySwapInvolved <- as.logical(as.integer(full_df$equitySwapInvolved))
    
    numeric_cols <- c('transactionShares', 'transactionPricePerShare', 'sharesOwnedFollowingTransaction',
                      'valueOwnedFollowingTransaction')
    
    for(column in numeric_cols) {
      
      full_df[[column]] <- as.numeric(full_df[[column]])
      
    }
    
    date_cols <- c('transactionDate', 'deemedExecutionDate')
    
    for(column in date_cols) {
      
      full_df[[column]] <- ymd(full_df[[column]], quiet = TRUE)
      
    }
    
  }
  
  full_df <- full_df[, nonDeriv_columns]
  
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
  
  
  scraping_df <- scrape_filing_table(xml_root, 2)
  
  if(nrow(scraping_df)) {
    
    full_df <- bind_rows(full_df, scraping_df)
    
    full_df$file_name <- file_name
    full_df$document <- document
    full_df$form_type <- form_type
    
    
    for(column in colnames(full_df)) {
      
      full_df[[column]] <- as.character(full_df[[column]])
      
    }
    
    
    full_df$seq <- as.integer(full_df$seq)
    full_df$equitySwapInvolved <- as.logical(as.integer(full_df$equitySwapInvolved))
    
    numeric_cols <- c('conversionOrExercisePrice', 'transactionShares', 'transactionTotalValue', 'transactionPricePerShare',
                      'underlyingSecurityShares', 'underlyingSecurityValue', 'sharesOwnedFollowingTransaction',
                      'valueOwnedFollowingTransaction')
    
    for(column in numeric_cols) {
      
      full_df[[column]] <- as.numeric(full_df[[column]])
      
    }
    
    date_cols <- c('transactionDate', 'deemedExecutionDate', 'exerciseDate', 'expirationDate')
    
    for(column in date_cols) {
      
      full_df[[column]] <- ymd(full_df[[column]], quiet = TRUE)
      
    }
    
  }
  
  full_df <- full_df[, deriv_columns]
  
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
    table1 <- get_nonDerivative_df(xml_root, file_name, document, form_type)
    got_table1 <- TRUE}, {got_table1 <- FALSE})
  
  try({
    table2 <- get_derivative_df(xml_root, file_name, document, form_type)
    got_table2 <- TRUE}, {got_table2 <- FALSE})
  
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
                           got_header = got_header, got_table1 = got_table1, got_table2 = got_table2,
                           got_footnotes = got_footnotes, got_footnote_indices = got_footnote_indices, 
                           got_signatures = got_signatures, wrote_header = wrote_header, wrote_table1 = wrote_table1, 
                           wrote_table2 = wrote_table2, wrote_footnotes = wrote_footnotes, 
                           wrote_footnote_indices = wrote_footnote_indices, wrote_signatures = wrote_signatures,
                           stringsAsFactors = FALSE)
  
  dbDisconnect(pg)
  
  return(process_df)
  
}



