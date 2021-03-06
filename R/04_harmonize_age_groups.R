.rs.restartR()
source("R/00_Functions.R")
# prelims to get offsets

inputCounts <- readRDS("Data/inputCounts.rds")
Offsets     <- readRDS("Data/Offsets.rds")

inputCounts <- 
  inputCounts %>% 
  arrange(Country, Region, Measure, Sex, Age)

 iL <- split(inputCounts,
              list(inputCounts$Code,
                   inputCounts$Sex,
                   inputCounts$Measure),
              drop =TRUE)

iLout <- mclapply(iL, 
          harmonize_age_p,
          Offsets = Offsets,
          N = 5,
          OAnew = 100,
          mc.cores = 6)

 # make parallel wrapper with everything in try()
 # remove try error elements, then bind and process.
 

  n <- lapply(iLout,function(x){length(x) == 1}) %>% unlist() %>% which()
 
(problem_codes <-  iLout[n])

# TR: now include rescale
outputCounts_5 <-
    iLout[-n] %>% 
    bind_rows() %>% 
    mutate(Value = ifelse(is.nan(Value),0,Value)) %>% 
    group_by(Code, Measure) %>% 
    # Newly added
    do(rescale_sexes_post(chunk = .data)) %>% 
    ungroup() %>%
    pivot_wider(names_from = Measure,
                values_from = Value) %>% 
    mutate(date = dmy(Date)) %>% 
    arrange(Country, Region, date, Sex, Age) %>% 
    select(-date) 


# round output for csv
outputCounts_5_rounded <- 
  outputCounts_5 %>% 
  mutate(Cases = round(Cases,1),
         Deaths = round(Deaths,1),
         Tests = round(Tests,1))

header_msg <- paste("Counts of Cases, Deaths, and Tests in harmonized 5-year age groups:",timestamp(prefix="",suffix=""))
write_lines(header_msg, path = "Data/Output_5.csv")
write_csv(outputCounts_5_rounded, path = "Data/Output_5.csv", append = TRUE, col_names = TRUE)

saveRDS(outputCounts_5, "Data/Output_5.rds")


# Repeat for 10-year age groups
 outputCounts_10 <- 
  outputCounts_5 %>% 
  mutate(Age = Age - Age %% 10) %>% 
  group_by(Country, Region, Code, Date, Sex, Age) %>% 
  summarize(Cases = sum(Cases),
            Deaths = sum(Deaths),
            Tests = sum(Tests)) %>% 
  ungroup() %>% 
  mutate(AgeInt = ifelse(Age == 100, 5, 10)) 
outputCounts_10 <- outputCounts_10[, colnames(outputCounts_5)]

# round output for csv
outputCounts_10_rounded <- 
  outputCounts_10 %>% 
  mutate(Cases = round(Cases,1),
         Deaths = round(Deaths,1),
         Tests = round(Tests,1))

header_msg <- paste("Counts of Cases, Deaths, and Tests in harmonized 10-year age groups:",timestamp(prefix="",suffix=""))
write_lines(header_msg, path = "Data/Output_10.csv")
write_csv(outputCounts_10_rounded, path = "Data/Output_10.csv", append = TRUE, col_names = TRUE)
saveRDS(outputCounts_10, "Data/Output_10.rds")


spot_checks <- FALSE
if (spot_checks){
# Once-off diagnostic plot:
  
  
# populations with > 100 deaths,
# but no deaths in ages > 70 is weird.
  outputCounts_10 %>% 
    group_by(Country, Region, Code, Sex) %>% 
    mutate(D = sum(Deaths),
           D70 = sum(Deaths[Age >=70])) %>% 
    ungroup() %>% 
    filter(D >= 100,
           D70 == 0) %>%
    View()
  outputCounts_10 %>% pull(Age) %>% table()
  outputCounts_10 %>% filter(is.na(Deaths)) %>% View()
  
ASCFR5 <- 
outputCounts_5 %>% 
    group_by(Country, Region, Code, Sex) %>% 
    mutate(D = sum(Deaths)) %>% 
    ungroup() %>% 
    mutate(ASCFR = Deaths / Cases,
           ASCFR = na_if(ASCFR, Deaths == 0)) %>% 
    filter(!is.na(ASCFR),
           Sex == "b",
           D >= 100) 
ASCFR5 %>% 
  ggplot(aes(x=Age, y = ASCFR, group = interaction(Country, Region, Code))) + 
  geom_line(alpha=.05) + 
  scale_y_log10() + 
  xlim(30,100) + 
  geom_quantile(ASCFR5,
                mapping=aes(x=Age, y = ASCFR), 
                method = "rqss",
                quantiles=c(.025,.25,.5,.75,.975), 
                lambda = 2,
                inherit.aes = FALSE,
                color = "tomato",
                size = 1)

outputCounts_5 %>% 
  group_by(Country, Region, Code, Sex) %>% 
  mutate(D = sum(Deaths)) %>% 
  ungroup() %>% 
  mutate(ASCFR = Deaths / Cases,
         ASCFR = na_if(ASCFR, Deaths == 0)) %>% 
  filter(!is.na(ASCFR),
         Sex == "m",
         D >= 100,
         Age >= 90,
         Deaths ==0) 


outputCounts_5 %>% 
  mutate(ASCFR = Deaths / Cases,
         ASCFR = na_if(ASCFR, Deaths == 0)) %>% 
  filter(Age == 40,
         !is.na(ASCFR),
         ASCFR > 1e-2)

outputCounts_5 %>% 
  mutate(ASCFR = Deaths / Cases,
         ASCFR = na_if(ASCFR, Deaths == 0)) %>% 
  filter(!is.na(Deaths),
         Age == 90,
         ASCFR < 1e-2) %>% View()

outputCounts_5 %>% 
  group_by(Country, Region, Code, Sex) %>% 
  mutate(D = sum(Deaths)) %>% 
  ungroup() %>% 
  filter(D >= 100) %>% 
  mutate(ASCFR = Deaths / Cases,
         ASCFR = na_if(ASCFR, Deaths == 0)) %>% 
  filter(!is.na(ASCFR),
         Sex == "f",
         D >= 100) %>% 
  filter(Age==40,
         ASCFR > .01)

#####
Test <- outputCounts_5 %>% 
  pivot_longer(cols=c(Cases,Deaths),
               names_to = "Measure",
               values_to = "Value") %>% 
  group_by(Country, Code, Date, Sex, Measure) %>% 
  summarize(TOTout = sum(Value)) %>% 
  ungroup()

inputCounts %>% 
  group_by(Country, Code, Date, Sex, Measure) %>% 
  summarize(TOTin = sum(Value)) %>% 
  ungroup() %>% 
  left_join(Test) %>% 
  mutate(Diff = TOTout - TOTin) %>% 
  pull(Diff) %>% 
  summary()
}

# 
# NYCpop2 <- c(NYCpop[1:85],yhat[86:length(yhat)])
# 
# CC <- inputCounts %>% 
#   filter(Code == "NYC06.04.2020",
#          Measure == "Cases") %>% 
#   pull(Value)
# 
# x <- inputCounts %>% 
#   filter(Code == "NYC06.04.2020",
#          Measure == "Cases") %>% 
#   pull(Age) %>% 
#   as.integer()
# nlast <- 105 - x[length(x)]
# 
# Cx<- pclm(x,CC,nlast=nlast,offset = NYCpop2)$fitted
# Cx <- Cx * NYCpop2
# DD <- inputCounts %>% 
#   filter(Code == "NYC06.04.2020",
#          Measure == "Deaths") %>% 
#   pull(Value)
# 
# #Dx1 <- pclm(x,DD,nlast=nlast,offset = Cx)$fitted
# Dx2 <- pclm(x,DD,nlast=nlast,offset = NYCpop2)$fitted
# 
# plot(0:104, Dx1 * Cx)
# lines(0:104, Dx2 * NYCpop2)

# plot(0:104, NYCpop2)

# step 1: get single age offsets for each country.


