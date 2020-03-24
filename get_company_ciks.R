library(DBI)
library(dplyr, warn.conflicts = FALSE)
library(xml2)
library(XML)
source('cusip_cik/get_13D_filing_details.R')
source('forms345/forms_345_xml_functions.R')



is_matched <- function(tag_num, tags) {

    is_start_tag <- grepl('<[^/]*>', tags[tag_num])
    tag_name <- gsub('[<>/]', '', tags[tag_num])
    num_tags <- length(tags)

    if (is_start_tag) {

        start_tags_after <- which(tags[c((tag_num + 1):num_tags)] == paste0('<', tag_name, '>'))
        end_tags_after <- which(tags[c((tag_num + 1):num_tags)] == paste0('</', tag_name, '>'))

        if (length(end_tags_after) - length(start_tags_after) == 1) {

            return(TRUE)

        } else {

            return(FALSE)

        }

    } else {

        start_tags_before <- which(tags[c(1:(tag_num - 1))] == paste0('<', tag_name, '>'))
        end_tags_before <- which(tags[c(1:(tag_num - 1))] == paste0('</', tag_name, '>'))

        if (length(start_tags_before) - length(end_tags_before) == 1) {

            return(TRUE)

        } else {

            return(FALSE)

        }

    }

}

get_matched_tags_vec <- function(tags) {

    vec <- unlist(lapply(c(1:length(tags)), function(i) {is_matched(i, tags)}))

    return(vec)

}


get_clean_sgml_text <- function(sgml_url) {

    # Note: this function assumes all unmatched tags are start tags (which is the case in SEC SGML header files)

    lines <- readLines(sgml_url)
    tags <- regmatches(lines, regexpr('<(.)*>', lines))

    unmatched_vec <- !get_matched_tags_vec(tags)

    end_tags <- gsub('^<', '</', tags[unmatched_vec])

    lines[unmatched_vec] <- unlist(lapply(c(1:sum(unmatched_vec)), function(i) {paste0(lines[unmatched_vec][i], end_tags[i])}))

    text <- paste(lines, collapse = '\n')

    return(text)

}

get_xml_root <- function(file_name) {

    clean_text <- get_clean_sgml_text(getSGMLlocation(file_name))

    root <- read_html(clean_text)

    return(root)

}

is_company <- function(file_name, cik) {

    try({
    root <- get_xml_root(file_name)

    nodes <- xml_find_all(root, '//cik')

    node_ciks <- xml_integer(nodes)

    node_index <- which(node_ciks == cik)

    node <- nodes[node_index]

    sibling_names <- xml_name(xml_children(xml_parent(node)))

    result <- "state-of-incorporation" %in% sibling_names

    return(result)

    }, {return(NA)})

}



filing_per_cik_sql <- "SELECT DISTINCT ON (cik) * FROM edgar.filings ORDER BY cik, file_name"

pg <- dbConnect(RPostgreSQL::PostgreSQL())

filing_per_cik_df <- tbl(pg, sql(filing_per_cik_sql)) %>% collect()


num_ciks <- nrow(filing_per_cik_df)
batch_size <- 200
num_cores <- 12
num_batches <- floor(num_ciks/batch_size) + 1
total_time <- 0
num_success <- 0

new_table <- !dbExistsTable(pg, c("edgar", "company_ciks"))


for (i in 1:num_batches) {

    start <- (i-1) * batch_size + 1

    if(i == num_batches) {

        end <- num_ciks

    } else {

        end <- i * batch_size

    }

    batch <- filing_per_cik_df[start:end, ]

    total_time <- total_time + system.time(batch$is_company <- unlist(mclapply(1:nrow(batch), function(i) {is_company(batch$file_name[i], batch$cik[i])}, mc.cores = num_cores)))

    num_success <- num_success + sum(!is.na(batch$is_company))

    rs <- dbWriteTable(pg, c("edgar", "company_ciks"), batch, append = !new_table, row.names = FALSE)

    print(paste0(num_success, ' processed out of ', end, ' ciks'))
    print(paste0('Time taken: ', total_time))

    new_table <- FALSE

}



dbDisconnect(pg)

