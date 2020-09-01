# `edgar.cusip_cik_exceptions`

The table `edgar.cusip_cik_exceptions` is a table written to handle a number of types of exceptional cases that arise in the raw `edgar.cusip_cik` table. These, for the main part, are:

 - Mappings between `cik`s and `cusip`s for which the `cusip` is a valid 9-character cusip number, but which are incorrect or possibly incorrect.
 
 - Cases where the raw cusip is 8 characters long. For these cases, we consider the raw cusip as a valid cusip8, as well as the raw cusip padded with a zero from the left.  
 
 - Cases where the raw cusip is 7 characters long. For these cases, we consider the first six characters of the raw cusip as a valid cusip6, as well as the raw cusip padded with a zero from the left, and finally the raw cusip padded with two zeros from the left.  
 
 - Cases where the raw cusip is 6 characters long. For these cases, we consider the raw cusip as a valid cusip6, as well as the first six characters of the raw cusip padded with a zero from the left as a valid cusip6, then the raw cusip padded with two zeros from the left as a valid cusip8, and then finally the raw cusip padded with three zeros from the left as a valid cusip. 
 

 
## The fields

- `cik`: the cik number for the pair considered

- `cusip`: the cusip number for the pair considered, given as a character string. This is not always the same as the cusip string extracted from the original data in `cusip_cik`; in same cases it has been modified from the original cusip string, though the original cusip string can always be found in the later field `cusip_raw` (see below). For the sake of clarity, `cusip` is always taken to be 6, 8 or 9 characters long, depending on the `cusip_raw` and the modifications made to it to derive `cusip`. 

- `company_name`: The company name for the given cik for the row

- `issuer_name`: The issuer name for the given `cusip`, constructed from the fields `issuer_name_1`, `issuer_name_2` and `issuer_name_3` if cusip maps onto the table `cusipm.issuer`, and equal to the the field `comnam` of `crsp.stocknames` if the cusip only maps onto `stocknames`

- `issuer_adl`: This is a pasting of the fields `issuer_adl_1`, `issuer_adl_2`, `issuer_adl_3` and `issuer_adl_4` of `cusipm.issuer`, if the cusip maps onto the table, and is null if the cusip does not map to `cusipm.issuer`. This field can be very useful as it contains historical information on the company and often contains a historical name which often matches `company_name` in the cases where `company_name` appears to not match the `issuer_name`

- `company_name_norm`: the normalization of `company_name`, in the case of a valid 9-digit `cusip_raw` which maps to `cusipm.issuer`. In this normalization, letters are converted to upper case, punctuation is stripped, and common abbreviations for words are substituted (see a later section for more details). 

- `issuer_name_norm`: the normalization of `issuer_name`, in the case of valid 9-digit `cusip_raw` which maps to `cusipm.issuer`. In this normalization, letters are converted to upper case, punctuation is stripped, and common abbreviations for words are substituted (see a later section for more details). 

- `sim_index_norm`: an index between 0 and 1 which measures how well `company_name` matches `issuer_name`, with 0 corresponding to a complete non-match, and 1 corresponding to a perfect match. This is calculated using the Levenshtein distance by the function `get_name_similarity_index` (see later section). In the case of a valid 9-digit `cusip_raw` which map onto `cusipm.issuer`, this index is calculated from `company_name_norm` and `issuer_name_norm`; in the cases where a valid 9-digit `cusip_raw` only maps onto `crsp.stocknames`, it is simply calculated from `company_name` and `issuer_name`. For cases where `cusip_raw` is less than 9 digits long, this variable is not calculated (for reasons why, see later section).

- `sim_index_max`: this is the maximum of `sim_index_norm` within the data after grouping by (`cik`, `cusip`), where this is valid. This variable was used to decide which valid 9-digit raw cusips to look at for the sake of making `cusip_cik_exceptions` (we considered rows for which `sim_index_max` is less than 0.8)

- `valid_match`: a boolean variable which is `TRUE` if the (`cik`, `cusip`) pair in question was determined to be valid, `FALSE` if the pair was determined to be an incorrect match, and `NULL` if open to interpretation. Usually, the null cases are ones in which `company_name` and `issuer_name` are technically not the same entities, but are somewhat related (eg. "ISHARES INC" versus "ISHARES TRUST")

- `better_cik`: a cik which has a company name which better matches the `issuer_name` for the given `cusip` of the pair (either determined by noting that the alternate `sim_index_max` is more, or by through observation). This field is null if there is no such cik

- `better_cik_company_name`: the company name for the `better_cik`, if `better_cik` is non-null.

- `sim_ix_better_cik`: `sim_index_max`/`sim_index_norm` between `better_cik_company_name` and `issuer_name`, in cases where `cusip_raw` is 9 digits long, and the `better_cik` was found within the data by looking for rows with the given `cusip` (achieved by joining relevant dataframes). If `better_cik` was found manually, this field is usually null.  

- `better_cusip`: a cusip which has an `issuer_name` which better matches the given `company_name` for the given `cik` of the pair (either determined by noting that the alternate `sim_index_max` is more, or by through observation). This field is null if there is no such cusip

- `better_cusip_issuer_name`: the `issuer_name` for the `better_cusip`, if `better_cusip` is non-null. 

- `better_cusip_issuer_adl` : the `issuer_adl` for the `better_cusip`, if `better_cusip` is non-null, and if `better_cusip` maps onto or is derived from `cusipm.issuer`. 

- `sim_ix_better_cusip`: `sim_index_max`/`sim_index_norm` between `better_cusip_issuer_name` and `company_name`, in cases where `cusip_raw` is 9 digits long, and the `better_cusip` was found within the data by looking for rows with the given `cik` (achieved by joining relevant dataframes). If `better_cusip` was found manually, this field is usually null.  

- `better_cusip6`: Similar to `better_cusip`, but is a cusip6 (usually found from `cusipm.issuer`), which has an issuer name which better matches the `company_name`. Usually found by manually searching `cusipm.issuer`.

- `better_cusip6_issuer_name`: the `issuer_name` for `better_cusip6`, if `better_cusip6` is non-null. 

- `better_cusip6_issuer_adl`: the `issuer_adl` for `better_cusip6`, if `better_cusip6` is non-null. As `better_cusip6` is usually found manually, this field is usually null unless the `issuer_adl` was relevant to determining `valid_match`. 

- `better_cusip8`: Similar to `better_cusip`, but is a cusip8 (usually found from `crsp.stocknames`), which has an issuer name (given in the `comnam` field) which better matches the `company_name`. Usually found by manually searching `crsp.stocknames`.

- `better_cusip8_comnam`: the issuer name, or `comnam` from `crsp.stocknames`, for the `better_cusip8`, if `better_cusip8` is non-null

- `other_reason`: A text field, used to give further details/explanation in cases which were not obviously wrong, or in some cases, not obviously right. 

- `cusip_raw`: the raw cusip used to generate the candidate `cusip`. This is always equal to the extracted `cusip` from `edgar.cusip_cik`. In cases where `cusip_raw` is modified to give `cusip` in `edgar.cusip_cik_exceptions` (eg. padding with zeros from the left, cutting to 6 digits in the case of raw 7 digit cusips), `cusip` will not be equal to `cusip_raw`


## How `edgar.cusip_cik_exceptions` was initially generated

In this section, we discuss how the cusip-cik pairs to be analysed for veracity were chosen. Firstly, we should mention that in all the cases to be discussed, we restricted ourselves to cusip-cik pairs which have a frequency in `edgar.cusip_cik` above a threshold of 10. 

By far the set of cases which is the most complex is the set of valid 9-digit cusips which map onto `cusipm.issuer`, as there are 19321 of them. This turns out to be orders of magnitude larger than any of the other groups of cusip-cik pairs that we consider for the purpose of `edgar.cusip_cik_exceptions`. Thus, it is important to have some procedure of narrowing down the number of cases from these that we consider. We chose to utilize a couple of things: approximate string matching and name normalization. 

The way we use approximate string matching is to utilize a string metric called the [Levenshtein distance](https://en.wikipedia.org/wiki/Levenshtein_distance), calculate this metric between the company names and the issuer names, and then exploit its properties to map the results to ratios between 0 and 1, with 0 corresponding to a complete non-match, and 1 corresponding to a perfect match. We then select just the pairs for which this ratio is less than some threshold, which we chose to be 0.8. 

We utilize name normalization to really complement the use of approximate string matching; it can help make the procedure described in the previous paragraph much more decisive, resulting in less cusip-cik pairs having a ratio in the middle of the range between 0 and 1, and thus helping to narrow the numbers further. The first step here is to strip punctuation and to convert all letters to upper case. We then consider mappings between words appearing in the company names of `edgar.cusip_cik` and words appearing in the issuer names appearing in `cusipm.issuer`. We did this to find the common abbreviations appearing mostly in `cusipm.issuer`, and map them to the corresponding words appearing in `edgar.cusip_cik` (or vice versa, though `cusipm.issuer` makes a particularly heavy use of abbreviation of words, so this is not as common). The result is that we end up with dataframe that we call `map_df` which maps common words to their common abbreviations, such as "FUND" to "FD", "TRUST" to "TR", "HOLDINGS" to "HLDGS", "INTERNATIONAL" to "INTL", and so on. This way, we make sure that common words and their common abbreviations always appear the same form in the normalized versions of the company names in `edgar.cusip_cik` and the issuer names from `cusipm.issuer`.



### Name normalization and calculating sim_index_max using the Levenshtein distance

``` r
library(dplyr, warn.conflicts = FALSE)
library(DBI)


normalize_name_string <- function(name) {

    title_normed <- stringr::str_match_all(stringr::str_to_lower(name), '[a-z0-9]')[[1]][,1] %>% paste0(collapse = "")

    return(title_normed)

}



get_name_similarity_index <- function(name_1, name_2) {

    reduced_name_1 <- normalize_name_string(name_1)

    reduced_name_2 <- normalize_name_string(name_2)

    max_len <- max(nchar(reduced_name_1), nchar(reduced_name_2))

    ratio <- (max_len - adist(reduced_name_1, reduced_name_2))/max_len

    return(ratio)

}



get_one_bag_df <- function(match_df) {

    l_1 <- stringr::str_match_all(match_df$company_name, '[^\\s]+')
    l_2 <- stringr::str_match_all(match_df$issuer_name, '[^\\s]+')

    min_l <- unlist(lapply(1:nrow(match_df), function(i) {min(nrow(l_1[[i]]), nrow(l_2[[i]]))}))

    vec_1 <- c()
    vec_2 <- c()

    for(i in 1:length(min_l)) {

        vec_1 <- c(vec_1, l_1[[i]][1:min_l[i], 1])
        vec_2 <- c(vec_2, l_2[[i]][1:min_l[i], 1])

    }

    df <- data.frame(word1 = vec_1, word2 = vec_2)

    return(df)

}


pg <- dbConnect(RPostgres::Postgres())

cusip_cik <- tbl(pg, sql("SELECT * FROM edgar.cusip_cik_test"))

cusip_cik %>% group_by(cik, cusip) %>% summarise(freq = n()) %>% ungroup() %>% inner_join(cusip_cik) %>% count()
#> Joining, by = c("cik", "cusip")
#> # Source:   lazy query [?? x 1]
#> # Database: postgres [bdcallen@/var/run/postgresql:5432/crsp]
#>   n      
#>   <int64>
#> 1 1262828

cusip_cik %>% count()
#> # Source:   lazy query [?? x 1]
#> # Database: postgres [bdcallen@/var/run/postgresql:5432/crsp]
#>   n      
#>   <int64>
#> 1 1335995

cusip_cik %>% filter(!is.na(cusip)) %>% count()
#> # Source:   lazy query [?? x 1]
#> # Database: postgres [bdcallen@/var/run/postgresql:5432/crsp]
#>   n      
#>   <int64>
#> 1 1262828


issuers <- tbl(pg, sql('SELECT * FROM cusipm.issuer')) %>% collect()
issuers <- issuers %>% rename(cusip6 = issuer_num) # change issuer_num to cusip6

m9_issuers <- cusip_cik %>% distinct(cik, cusip, check_digit, company_name) %>% collect() %>%
    filter(nchar(cusip) == 9 & substr(cusip, 9, 9) == as.character(check_digit)) %>%
    mutate(cusip6 = substr(cusip, 1, 6)) %>%
    inner_join(issuers, by = 'cusip6')

m9_issuers <- m9_issuers %>%
    mutate(issuer_name = ifelse(is.na(issuer_name_2), issuer_name_1,
    ifelse(is.na(issuer_name_3), paste(issuer_name_1, issuer_name_2), paste(issuer_name_1, issuer_name_2, issuer_name_3))))

m9_issuers <- m9_issuers %>%
        mutate(issuer_adl = ifelse(is.na(issuer_adl_1), NA, issuer_adl_1)) %>%
        mutate(issuer_adl = ifelse(is.na(issuer_adl_2), issuer_adl, paste(issuer_adl, issuer_adl_2))) %>%
        mutate(issuer_adl = ifelse(is.na(issuer_adl_3), issuer_adl, paste(issuer_adl, issuer_adl_3))) %>%
        mutate(issuer_adl = ifelse(is.na(issuer_adl_4), issuer_adl, paste(issuer_adl, issuer_adl_4)))



m9_issuers <- m9_issuers %>% mutate(company_name_raw = stringr::str_to_upper(company_name),
                                    issuer_name_raw = stringr::str_to_upper(issuer_name)) %>%
    mutate(company_name_raw = gsub('[^A-Z0-9\\s]', ' ', company_name_raw),
           issuer_name_raw = gsub('[^A-Z0-9\\s]', ' ', issuer_name_raw)) %>%
    mutate(company_name_raw = gsub('\\s+', ' ', company_name_raw),
           issuer_name_raw = gsub('\\s+', ' ', issuer_name_raw)) %>%
    mutate(company_name_raw = gsub('\\s+', ' ', company_name_raw),
           issuer_name_raw = gsub('\\s+', ' ', issuer_name_raw)) %>%
    mutate(company_name_raw = gsub('^\\s', '', company_name_raw),
           issuer_name_raw = gsub('^\\s', '', issuer_name_raw)) %>%
    mutate(company_name_raw = gsub('\\s$', '', company_name_raw), issuer_name_raw = gsub('\\s$', '', issuer_name_raw))


m9_issuers$sim_index_raw <- unlist(lapply(1:nrow(m9_issuers),
        function(i) {get_name_similarity_index(m9_issuers$company_name_raw[i], m9_issuers$issuer_name_raw[i])}))


one_bag_df <- get_one_bag_df(m9_issuers %>% filter(sim_index_raw >= 0.6) %>%
                                 select(company_name_raw, issuer_name_raw) %>%
                                 rename(company_name = company_name_raw, issuer_name = issuer_name_raw))

one_bag_df %>% filter(word1 != word2 & nchar(word1) > 1 & nchar(word2) > 1 &
    substr(word1, 1, 1) == substr(word2, 1, 1) & nchar(word1) > nchar(word2) &
    ifelse(substr(word1, nchar(word1), nchar(word1)) == 'S', substr(word2, nchar(word2), nchar(word2)) == 'S', TRUE)) %>%
    group_by(word1, word2) %>% summarise(freq = n()) %>% arrange(desc(freq)) %>% print(n=20)
#> `summarise()` regrouping output by 'word1' (override with `.groups` argument)
#> # A tibble: 500 x 3
#> # Groups:   word1 [465]
#>    word1         word2  freq
#>    <chr>         <chr> <int>
#>  1 FUND          FD     1385
#>  2 TRUST         TR     1313
#>  3 HOLDINGS      HLDGS   967
#>  4 FINANCIAL     FINL    826
#>  5 SYSTEMS       SYS     635
#>  6 INTERNATIONAL INTL    634
#>  7 MUNICIPAL     MUN     584
#>  8 SERVICES      SVCS    462
#>  9 INDUSTRIES    INDS    426
#> 10 RESOURCES     RES     416
#> 11 CAPITAL       CAP     373
#> 12 HOLDING       HLDG    234
#> 13 REALTY        RLTY    225
#> 14 MEDICAL       MED     222
#> 15 PROPERTIES    PPTYS   179
#> 16 ENTERTAINMENT ENTMT   178
#> 17 PRODUCTS      PRODS   173
#> 18 INVESTMENT    INVT    163
#> 19 POWER         PWR     163
#> 20 DIVIDEND      DIVID   156
#> # … with 480 more rows


bad_maps <- c(181, 198, 213, 218, 219, 227, 228, 238, 241, 242)

map_df <- one_bag_df %>% filter(word1 != word2 & nchar(word1) > 1 & nchar(word2) > 1 &
        substr(word1, 1, 1) == substr(word2, 1, 1) & nchar(word1) > nchar(word2) &
    ifelse(substr(word1, nchar(word1), nchar(word1)) == 'S', substr(word2, nchar(word2), nchar(word2)) == 'S', TRUE)) %>%
    group_by(word1, word2) %>% summarise(freq = n()) %>%
    filter(freq >= 3) %>% arrange(desc(freq)) %>% ungroup() %>% slice(-bad_maps) %>% select(word1, word2)
#> `summarise()` regrouping output by 'word1' (override with `.groups` argument)


one_bag_df %>% filter(word1 != word2 & nchar(word1) > 1 & nchar(word2) > 1 &
    substr(word1, 1, 1) == substr(word2, 1, 1) & nchar(word1) > nchar(word2) &
    ifelse(substr(word1, nchar(word1), nchar(word1)) == 'S', substr(word2, nchar(word2), nchar(word2)) == 'S', TRUE)) %>%
    group_by(word1, word2) %>% summarise(freq = n()) %>%
    filter(freq >= 3) %>% arrange(desc(freq)) %>% ungroup() %>% slice(bad_maps)
#> `summarise()` regrouping output by 'word1' (override with `.groups` argument)
#> # A tibble: 10 x 3
#>    word1        word2   freq
#>    <chr>        <chr>  <int>
#>  1 "INCOME"     II         5
#>  2 "CORP"       CAP        4
#>  3 "PUBLIC"     PLC        4
#>  4 "COM"        CO         3
#>  5 "DEUTSCHE"   DWS        3
#>  6 "INC\\"      INC        3
#>  7 "INSURED"    INVT       3
#>  8 "SIMPLETECH" SIMPLE     3
#>  9 "TERM"       TR         3
#> 10 "TREE"       TR         3


map_df$regex1 <- paste0('(?:\\s|^)', map_df$word1, '(?:\\s|$)')
map_df$regex2 <- paste0(' ', map_df$word2, ' ')


m9_issuers$company_name_norm <- stringi::stri_replace_all_regex(m9_issuers$company_name_raw,
                                                                map_df$regex1, map_df$regex2, vectorize_all = FALSE) %>%
    gsub('^\\s', '', .) %>% gsub('\\s$', '', .)

m9_issuers$issuer_name_norm <- stringi::stri_replace_all_regex(m9_issuers$issuer_name_raw,
                                                               map_df$regex1, map_df$regex2, vectorize_all = FALSE) %>%
    gsub('^\\s', '', .) %>% gsub('\\s$', '', .)



m9_issuers %>% select(company_name, company_name_norm, issuer_name, issuer_name_norm) %>% print(n=20)
#> # A tibble: 40,256 x 4
#>    company_name      company_name_norm   issuer_name        issuer_name_norm    
#>    <chr>             <chr>               <chr>              <chr>               
#>  1 K TRON INTERNATI… K TRON INTL INC     FIRST FID BANCORP… FIRST FID BANCORPOR…
#>  2 K TRON INTERNATI… K TRON INTL INC     K TRON INTL INC    K TRON INTL INC     
#>  3 AAR CORP          AAR CO              AAR CORP           AAR CO              
#>  4 TRANZONIC COMPAN… TRANZONIC COS       TRANZONIC COS      TRANZONIC COS       
#>  5 TRANZONIC COMPAN… TRANZONIC COS       TRANZONIC COS      TRANZONIC COS       
#>  6 ABBOTT LABORATOR… ABBOTT LABS         ABBOTT LABS        ABBOTT LABS         
#>  7 ABERDEEN IDAHO M… ABERDEEN IDAHO MNG… ABERDEEN MNG CO    ABERDEEN MNG CO     
#>  8 ABRAMS INDUSTRIE… ABRAMS INDS INC     ABRAMS INDS INC    ABRAMS INDS INC     
#>  9 SERVIDYNE, INC.   SERVIDYNE INC       SERVIDYNE INC      SERVIDYNE INC       
#> 10 WORLDS INC        WORLDS INC          WORLDS INC         WORLDS INC          
#> 11 WORLDS COM INC    WORLDS COM INC      WORLDS INC         WORLDS INC          
#> 12 WORLDS INC        WORLDS INC          WORLDS INC         WORLDS INC          
#> 13 AMETECH INC       AMETECH INC         AMETECH INC        AMETECH INC         
#> 14 ACCEL INTERNATIO… ACCEL INTL CO       ACCEL INTL CORP    ACCEL INTL CO       
#> 15 ACETO CORP        ACETO CO            ACETO CORP         ACETO CO            
#> 16 ACETO CORP        ACETO CO            ALAMO GROUP INC    ALAMO GRP INC       
#> 17 ACETO CORP        ACETO CO            AUTODESK INC       AUTODESK INC        
#> 18 ACMAT CORP        ACMAT CO            ACMAT CORP         ACMAT CO            
#> 19 ACMAT CORP        ACMAT CO            ACMAT CORP         ACMAT CO            
#> 20 ACME CLEVELAND C… ACME CLEVELAND CO   ACME CLEVELAND CO… ACME CLEVELAND CO N…
#> # … with 40,236 more rows



m9_issuers$sim_index_norm <- unlist(lapply(1:nrow(m9_issuers),
            function(i) {get_name_similarity_index(m9_issuers$company_name_norm[i], m9_issuers$issuer_name_norm[i])}))




m9_issuers %>% distinct(cik, cusip) %>% count()
#> # A tibble: 1 x 1
#>       n
#>   <int>
#> 1 35559


m9_issuers %>% group_by(cik, cusip) %>% summarise(sim_index_raw_max = max(sim_index_raw)) %>%
    ungroup() %>% filter(sim_index_raw_max >= 0.8) %>% count()
#> `summarise()` regrouping output by 'cik' (override with `.groups` argument)
#> # A tibble: 1 x 1
#>       n
#>   <int>
#> 1 21672

m9_issuers %>% group_by(cik, cusip) %>% summarise(sim_index_norm_max = max(sim_index_norm)) %>%
    ungroup() %>% filter(sim_index_norm_max >= 0.8) %>% count()
#> `summarise()` regrouping output by 'cik' (override with `.groups` argument)
#> # A tibble: 1 x 1
#>       n
#>   <int>
#> 1 29127

m9_issuers %>% group_by(cik, cusip) %>% summarise(sim_index_raw_max = max(sim_index_raw)) %>%
    ungroup() %>% filter(sim_index_raw_max < 0.3) %>% count()
#> `summarise()` regrouping output by 'cik' (override with `.groups` argument)
#> # A tibble: 1 x 1
#>       n
#>   <int>
#> 1  3109

m9_issuers %>% group_by(cik, cusip) %>% summarise(sim_index_norm_max = max(sim_index_norm)) %>%
    ungroup() %>% filter(sim_index_norm_max < 0.3) %>% count()
#> `summarise()` regrouping output by 'cik' (override with `.groups` argument)
#> # A tibble: 1 x 1
#>       n
#>   <int>
#> 1  3066

m9_issuers %>% group_by(cik, cusip) %>% summarise(sim_index_raw_max = max(sim_index_raw)) %>%
    ungroup() %>% filter(sim_index_raw_max >= 0.4 & sim_index_raw_max <= 0.7) %>% count()
#> `summarise()` regrouping output by 'cik' (override with `.groups` argument)
#> # A tibble: 1 x 1
#>       n
#>   <int>
#> 1  5566

m9_issuers %>% group_by(cik, cusip) %>% summarise(sim_index_norm_max = max(sim_index_norm)) %>%
    ungroup() %>% filter(sim_index_norm_max >= 0.4 & sim_index_norm_max <= 0.7) %>% count()
#> `summarise()` regrouping output by 'cik' (override with `.groups` argument)
#> # A tibble: 1 x 1
#>       n
#>   <int>
#> 1  1491


m9_issuers %>% group_by(cik, cusip) %>% summarise(sim_index_norm_max = max(sim_index_norm)) %>%
    ungroup() %>% filter(sim_index_norm_max >= 0.9) %>% inner_join(m9_issuers) %>% filter(sim_index_norm == sim_index_norm_max) %>%
    select(cik, cusip, company_name, issuer_name, issuer_adl, sim_index_norm)
#> `summarise()` regrouping output by 'cik' (override with `.groups` argument)
#> Joining, by = c("cik", "cusip")
#> # A tibble: 26,993 x 6
#>      cik cusip  company_name    issuer_name issuer_adl            sim_index_norm
#>    <int> <chr>  <chr>           <chr>       <chr>                          <dbl>
#>  1    20 48273… K TRON INTERNA… K TRON INT… <NA>                               1
#>  2  1750 00036… AAR CORP        AAR CORP    <NA>                               1
#>  3  1761 89412… TRANZONIC COMP… TRANZONIC … ACQUIRED BY LINSALAT…              1
#>  4  1761 89412… TRANZONIC COMP… TRANZONIC … ACQUIRED BY LINSALAT…              1
#>  5  1800 00282… ABBOTT LABORAT… ABBOTT LABS <NA>                               1
#>  6  1923 00378… ABRAMS INDUSTR… ABRAMS IND… FORMERLY ABRAMS A R …              1
#>  7  1923 81765… SERVIDYNE, INC. SERVIDYNE … <NA>                               1
#>  8  1961 98159… WORLDS INC      WORLDS INC  <NA>                               1
#>  9  1961 98191… WORLDS INC      WORLDS INC  NAME CHANGED TO WORL…              1
#> 10  1969 03109… AMETECH INC     AMETECH INC <NA>                               1
#> # … with 26,983 more rows

m9_issuers %>% group_by(cik, cusip) %>% summarise(sim_index_norm_max = max(sim_index_norm)) %>%
    ungroup() %>% filter(sim_index_norm_max >= 0.8 & sim_index_norm_max < 0.9) %>% inner_join(m9_issuers) %>% filter(sim_index_norm == sim_index_norm_max) %>%
    select(cik, cusip, company_name, issuer_name, issuer_adl, sim_index_norm)
#> `summarise()` regrouping output by 'cik' (override with `.groups` argument)
#> Joining, by = c("cik", "cusip")
#> # A tibble: 2,789 x 6
#>      cik cusip  company_name      issuer_name   issuer_adl        sim_index_norm
#>    <int> <chr>  <chr>             <chr>         <chr>                      <dbl>
#>  1  2066 00462… ACME CLEVELAND C… ACME CLEVELA… FORMERLY ACME CL…          0.833
#>  2  2457 00750… ADVANCE ROSS CORP ADVANCE ROSS… <NA>                       0.812
#>  3  2969 00915… AIR PRODUCTS & C… AIR PRODS & … <NA>                       0.889
#>  4  3000 00926… AIRBORNE FREIGHT… AIRBORNE FGH… ACQUIRED BY AIRB…          0.875
#>  5  3000 00926… AIRBORNE INC /DE/ AIRBORNE INC  <NA>                       0.846
#>  6  3202 01165… ALASKA AIRLINES … ALASKA AIR G… <NA>                       0.8  
#>  7  3303 01234… ALBANY INTERNATI… ALBANY INTL … <NA>                       0.867
#>  8  3327 01307… ALBERTO CULVER CO ALBERTO-CULV… ACQUIRED BY UNIL…          0.833
#>  9  3333 01310… ALBERTSONS INC /… ALBERTSONS I… <NA>                       0.867
#> 10  3642 01675… ALLCITY INSURANC… ALLCITY INS … <NA>                       0.857
#> # … with 2,779 more rows

m9_issuers %>% group_by(cik, cusip) %>% summarise(sim_index_norm_max = max(sim_index_norm)) %>%
    ungroup() %>% filter(sim_index_norm_max < 0.3) %>% inner_join(m9_issuers) %>% filter(sim_index_norm == sim_index_norm_max) %>%
    select(cik, cusip, company_name, issuer_name, issuer_adl, sim_index_norm)
#> `summarise()` regrouping output by 'cik' (override with `.groups` argument)
#> Joining, by = c("cik", "cusip")
#> # A tibble: 3,073 x 6
#>      cik cusip  company_name    issuer_name      issuer_adl       sim_index_norm
#>    <int> <chr>  <chr>           <chr>            <chr>                     <dbl>
#>  1    20 32019… K TRON INTERNA… FIRST FID BANCO… ACQUIRED BY FIR…          0.2  
#>  2  2034 01131… ACETO CORP      ALAMO GROUP INC  <NA>                      0.182
#>  3  2034 05276… ACETO CORP      AUTODESK INC     <NA>                      0.182
#>  4  2308 18272… ADDMASTER CORP  CLARY CORP       <NA>                      0.273
#>  5  2648 30158… AETNA LIFE & C… EXECUTIVE RISK … ACQUIRED BY CHU…          0.188
#>  6  2648 44490… AETNA LIFE & C… HUMAN GENOME SC… <NA>                      0.227
#>  7  2648 56509… AETNA LIFE & C… MAPCO INC        MERGED INTO WIL…          0.143
#>  8  2648 67741… AETNA LIFE & C… OHIO PWR CO      <NA>                      0.214
#>  9  2648 67741… AETNA LIFE & C… OHIO PWR CO      <NA>                      0.214
#> 10  2648 81764… AETNA LIFE & C… SERVICO INC FLA  REORGANIZED AS …          0.143
#> # … with 3,063 more rows

m9_issuers %>% group_by(cik, cusip) %>% summarise(sim_index_norm_max = max(sim_index_norm)) %>%
    ungroup() %>% filter(sim_index_norm_max >= 0.4 & sim_index_norm_max <= 0.7) %>% inner_join(m9_issuers) %>% filter(sim_index_norm == sim_index_norm_max) %>%
    select(cik, cusip, company_name, issuer_name, issuer_adl, sim_index_norm) %>% print(n=20)
#> `summarise()` regrouping output by 'cik' (override with `.groups` argument)
#> Joining, by = c("cik", "cusip")
#> # A tibble: 1,509 x 6
#>      cik cusip  company_name     issuer_name    issuer_adl        sim_index_norm
#>    <int> <chr>  <chr>            <chr>          <chr>                      <dbl>
#>  1  2648 00811… AETNA SERVICES … AETNA INC      MERGED INTO ING …          0.571
#>  2  2648 00817… AETNA SERVICES … AETNA INC NEW  FORMERLY AETNA U…          0.5  
#>  3  2668 00103… AFA PROTECTIVE … AFA PROT SYS … <NA>                       0.684
#>  4  3449 01448… ALEXANDER & ALE… ALEXANDER & B… REORGANIZED AS A…          0.56 
#>  5  3662 86707… SUNBEAM CORP/FL/ SUNBEAM CORP … FORMERLY SUNBEAM…          0.667
#>  6  5099 92095… VAN KAMPEN CONV… VAN KAMPEN AM… MERGED INTO VAN …          0.607
#>  7  5103 02637… AMERICAN GENERA… AMERICAN GEN … <NA>                       0.571
#>  8  5611 02886… FINA INC         AMERICAN PETR… NAME CHANGED TO …          0.412
#>  9  5907 00206… AT&T CORP        AT&T INC       <NA>                       0.5  
#> 10  6201 00176… AMR CORP         AMR CORP DEL   NAME CHANGED TO …          0.625
#> 11  6201 00176… AMR CORP         AMR CORP DEL   NAME CHANGED TO …          0.625
#> 12  6260 03237… ANACOMP INC      ANACOMP INC I… <NA>                       0.625
#> 13  8063 04990… ASTRONICS CORP   ATRION CORP    <NA>                       0.545
#> 14 11821 08655… BEST PRODUCTS C… BEST PRODS IN… <NA>                       0.667
#> 15 12659 09367… H&R BLOCK INC    BLOCK H & R I… <NA>                       0.6  
#> 16 14707 11523… BROWN SHOE CO I… BROWN & BROWN… <NA>                       0.643
#> 17 14707 11573… BROWN SHOE CO I… BROWN SHOE IN… <NA>                       0.667
#> 18 14707 11573… BROWN SHOE CO I… BROWN SHOE IN… <NA>                       0.667
#> 19 14957 11742… BRUSH WELLMAN I… BRUSH ENGINEE… NAME CHANGED TO …          0.478
#> 20 16387 14052… CAPITAL TRUST    CAPITAL TR IN… NAME CHANGED TO …          0.5  
#> # … with 1,489 more rows


# These are the valid 9s with a frequency above 10, our given threshold
valid9s_above_10 <- cusip_cik %>% group_by(cik, cusip) %>% summarise(freq = n()) %>% ungroup() %>% inner_join(cusip_cik) %>%
    filter(nchar(cusip) == 9 & substr(cusip, 9, 9) == as.character(check_digit) & freq >= 10) %>% collect() %>%
    distinct(cik, cusip, company_name)
#> Joining, by = c("cik", "cusip")

valid9s_above_10 <- valid9s_above_10 %>% mutate(cusip6 = substr(cusip, 1, 6))


valid9s_above_10_w_issuers <- valid9s_above_10 %>% inner_join(issuers)
#> Joining, by = "cusip6"

valid9s_above_10_w_issuers %>% distinct(cik, cusip) %>% count()
#> # A tibble: 1 x 1
#>       n
#>   <int>
#> 1 19321


valid9s_above_10_w_issuers <- valid9s_above_10_w_issuers %>%
    mutate(issuer_name = ifelse(is.na(issuer_name_2), issuer_name_1,
    ifelse(is.na(issuer_name_3), paste(issuer_name_1, issuer_name_2), paste(issuer_name_1, issuer_name_2, issuer_name_3))))

valid9s_above_10_w_issuers <- valid9s_above_10_w_issuers %>%
    mutate(issuer_adl = ifelse(is.na(issuer_adl_1), NA, issuer_adl_1)) %>%
    mutate(issuer_adl = ifelse(is.na(issuer_adl_2), issuer_adl, paste(issuer_adl, issuer_adl_2))) %>%
    mutate(issuer_adl = ifelse(is.na(issuer_adl_3), issuer_adl, paste(issuer_adl, issuer_adl_3))) %>%
    mutate(issuer_adl = ifelse(is.na(issuer_adl_4), issuer_adl, paste(issuer_adl, issuer_adl_4)))


valid9s_above_10_w_issuers <- valid9s_above_10_w_issuers %>% mutate(company_name_raw = stringr::str_to_upper(company_name),
                                                issuer_name_raw = stringr::str_to_upper(issuer_name)) %>%
    mutate(company_name_raw = gsub('[^A-Z0-9\\s]', ' ', company_name_raw),
           issuer_name_raw = gsub('[^A-Z0-9\\s]', ' ', issuer_name_raw)) %>%
    mutate(company_name_raw = gsub('\\s+', ' ', company_name_raw),
           issuer_name_raw = gsub('\\s+', ' ', issuer_name_raw)) %>%
    mutate(company_name_raw = gsub('\\s+', ' ', company_name_raw),
           issuer_name_raw = gsub('\\s+', ' ', issuer_name_raw)) %>%
    mutate(company_name_raw = gsub('^\\s', '', company_name_raw),
           issuer_name_raw = gsub('^\\s', '', issuer_name_raw)) %>%
    mutate(company_name_raw = gsub('\\s$', '', company_name_raw), issuer_name_raw = gsub('\\s$', '', issuer_name_raw))


valid9s_above_10_w_issuers$company_name_norm <- stringi::stri_replace_all_regex(valid9s_above_10_w_issuers$company_name_raw,
                                                                      map_df$regex1, map_df$regex2, vectorize_all = FALSE) %>%
    gsub('^\\s', '', .) %>% gsub('\\s$', '', .)

valid9s_above_10_w_issuers$issuer_name_norm <- stringi::stri_replace_all_regex(valid9s_above_10_w_issuers$issuer_name_raw,
                                                                     map_df$regex1, map_df$regex2, vectorize_all = FALSE) %>%
    gsub('^\\s', '', .) %>% gsub('\\s$', '', .)



valid9s_above_10_w_issuers$sim_index_norm <- unlist(lapply(1:nrow(valid9s_above_10_w_issuers),
        function(i) {get_name_similarity_index(valid9s_above_10_w_issuers$company_name_norm[i],
                                               valid9s_above_10_w_issuers$issuer_name_norm[i])}))



valid9s_above_10_w_issuers %>% distinct(cik, cusip) %>% count()
#> # A tibble: 1 x 1
#>       n
#>   <int>
#> 1 19321

sim_index_max <- valid9s_above_10_w_issuers %>% group_by(cik, cusip) %>%
                    summarise(sim_index_max = max(sim_index_norm)) %>% ungroup()
#> `summarise()` regrouping output by 'cik' (override with `.groups` argument)

sim_index_max %>% filter(sim_index_max == 1) %>% count()
#> # A tibble: 1 x 1
#>       n
#>   <int>
#> 1 15884

sim_index_max %>% filter(sim_index_max < 0.8) %>% count()
#> # A tibble: 1 x 1
#>       n
#>   <int>
#> 1  1249

sim_index_max %>% filter(sim_index_max >= 0.6 & sim_index_max < 0.8) %>% count()
#> # A tibble: 1 x 1
#>       n
#>   <int>
#> 1   792

sim_index_max %>% filter(sim_index_max < 0.3) %>% count()
#> # A tibble: 1 x 1
#>       n
#>   <int>
#> 1   177

valid9s_above_10_w_issuers <- valid9s_above_10_w_issuers %>% inner_join(sim_index_max)
#> Joining, by = c("cik", "cusip")


dbDisconnect(pg)
```

<sup>Created on 2020-09-01 by the [reprex package](https://reprex.tidyverse.org) (v0.3.0)</sup>



