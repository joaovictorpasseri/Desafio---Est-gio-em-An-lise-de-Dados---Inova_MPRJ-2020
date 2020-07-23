library(readr)
library(dplyr)
library(plyr)
library(comprehenr)
library(lubridate)
library(ggplot2)
library(randomForest)
library(gridExtra)
library(tidyr)

# Abrindo planilha Plano de Aplicação Detalhado, planilha Convenio, planilha Propostas e planilha Pagamento
# planilha .

pasta <- "C:/Users/joao passeri/Desktop/Desafio - Estágio em Análise de Dados/siconv/base"

dfs <- list.files(pasta,full.names = T) 

dfs <- to_list(for(i in dfs) if(T) read_delim(i,";", escape_double = F, locale = locale(decimal_mark = ","),
                                                          trim_ws = T))
# dfs = lista de dataframes necessarios para analise

# Juncao de planilhas e aplicacao de filtragem (subgrupo RJ, OBRA, ANO Fim >= 2015)
#(df e uma varia auxiliar que mudara durante todo o desafio)

df <- full_join(dfs[[1]],dfs[[4]],by="ID_PROPOSTA") %>%
  mutate(Ano_FIM = year(dmy(DIA_FIM_VIGENC_ORIGINAL_CONV))) %>% 
  subset(SIGLA == "RJ" & TIPO_DESPESA_ITEM == "OBRA" & Ano_FIM > 2014)

# Retirando duplicados

df <- df[!duplicated(df$ID_PROPOSTA),]

# Juncao com planilha proposta

data_base <- left_join(df,dfs[[5]],by='ID_PROPOSTA')

# Valor recebido de emenda parlamentar, agrupando por proposta

df = dfs[[2]][dfs[[2]]$ID_PROPOSTA %in% data_base$ID_PROPOSTA,]

df <- group_by(df,ID_PROPOSTA) %>%
  dplyr::summarise(VALOR_REPASSE_EMENDA = sum(VALOR_REPASSE_EMENDA))


data_base <- full_join(data_base,df,by='ID_PROPOSTA')

data_base$VALOR_REPASSE_EMENDA[is.na(data_base$VALOR_REPASSE_EMENDA)] <- 0 

# Apos leitura de documentacao e banco de dados, foram selecionadas para análise algumas variaveis

data_base <- data_base[,c("NR_CONVENIO","ID_PROPOSTA","SIT_CONVENIO","INSTRUMENTO_ATIVO",
                           'IND_OPERA_OBTV','DIA_INIC_VIGENC_CONV','DIA_FIM_VIGENC_CONV',"Ano_FIM",
                           'DIA_FIM_VIGENC_ORIGINAL_CONV',"VL_GLOBAL_CONV","VL_REPASSE_CONV","VL_CONTRAPARTIDA_CONV",
                           "VALOR_GLOBAL_ORIGINAL_CONV","VALOR_REPASSE_EMENDA","MUNICIPIO","OBJETO_PROPOSTA",
                           "NATUREZA_JURIDICA","NM_PROPONENTE","DESC_ORGAO_SUP","DESC_ORGAO")]


# Calculando obras atrasadas e % de contrapartida e % de gasto extra.

intervalo <- interval(dmy(data_base$DIA_FIM_VIGENC_ORIGINAL_CONV), dmy(data_base$DIA_FIM_VIGENC_CONV))
intervalo <- intervalo / ddays(30) # meses de atraso

data_base <- mutate(data_base, PORCENT_EMENDA = round(100*VALOR_REPASSE_EMENDA/VL_GLOBAL_CONV,2),
                               PORCENT_CONTRAPARTIDA = round(100*VL_CONTRAPARTIDA_CONV/VL_GLOBAL_CONV,2),
                               ATRASO = (intervalo!=0),
                               MESES_ATRASO = round(intervalo,0))

data_base$ATRASO[data_base$ATRASO] <- 'Sim'
data_base$ATRASO[data_base$ATRASO=='FALSE'] <- 'Nao'


write.csv(data_base,"data_base.csv")

# Composicao de atraso por ano

df <- subset(data_base, dmy(DIA_FIM_VIGENC_ORIGINAL_CONV) < dmy('23/07/2020'))
df <- df[,c("Ano_FIM","ATRASO")]
df$ATRASO[df$ATRASO=="Sim"] <- 1
df$ATRASO[df$ATRASO=='Nao'] <- 0
df$ATRASO <- as.integer(df$ATRASO)
df <- na.omit(df)
df <- group_by(df,Ano_FIM) %>%
  dplyr::summarise(Porcentagem = round(100*mean(ATRASO),2))


fig1 <- ggplot(df, aes(x=Ano_FIM, y=Porcentagem))+
  geom_bar(aes(fill = Ano_FIM), stat="identity")+
  labs(title="Atraso por ano (%)",
    x = 'Ano',
    y = 'Porcentagem')+
  guides(fill=FALSE)+
  theme_bw()


fig1

# Utilizando tabela Pagamento para encontrar fornecedores que participaram de obras com atraso

df <- dfs[[3]][dfs[[3]]$NR_CONVENIO %in% data_base$NR_CONVENIO,] # selecionando convenio
df <- na.omit(df)

df <- group_by(df,NR_CONVENIO,NOME_FORNECEDOR) %>%
  dplyr::summarise(VL_PAGO=sum(VL_PAGO)) # total recebido por fornecedor pelo convenio

df <- left_join(df,data_base[,c("NR_CONVENIO","ATRASO")], by="NR_CONVENIO") # convenio atrasado

df$ATRASO[df$ATRASO=="Sim"] <- 1
df$ATRASO[df$ATRASO=='Nao'] <- 0
df$ATRASO <- as.integer(df$ATRASO)
i <- count(df$NOME_FORNECEDOR)
names(i) <- c("NOME_FORNECEDOR","QUANTIDADE_CONTRATOS")



df <- group_by(df,NOME_FORNECEDOR) %>%
  dplyr::summarise(VL_PAGO=sum(VL_PAGO),
                   OBRAS_ATRASO=sum(ATRASO))
df <- left_join(df,i,by="NOME_FORNECEDOR")

write.csv(df,"data_fornecedor.csv")

# Maioes participantes

df <- df[df$QUANTIDADE_CONTRATOS>5,]

df$NOME_FORNECEDOR <- as.factor(df$NOME_FORNECEDOR)

df <- gather(df, "Condição", "Valor", VL_PAGO:QUANTIDADE_CONTRATOS, factor_key=TRUE) # wide to long

grid.table(df)

# Indicadores de atraso e analisando sua importancia

df <- subset(data_base, dmy(DIA_FIM_VIGENC_ORIGINAL_CONV) < dmy('23/07/2020'))
df <- df[,c("NATUREZA_JURIDICA","DESC_ORGAO_SUP",
            "PORCENT_EMENDA","PORCENT_CONTRAPARTIDA",
            "VL_GLOBAL_CONV","ATRASO")]
df$NATUREZA_JURIDICA <- as.factor(df$NATUREZA_JURIDICA)
df$DESC_ORGAO_SUP <- as.factor(df$DESC_ORGAO_SUP)
df$ATRASO <- as.factor(df$ATRASO)
df <- na.omit(df)


mod_rand <- randomForest(ATRASO ~ .,
                         ntree = 40,
                         data = df,
                         nodesize = 1,
                         replace = FALSE,
                         importance = TRUE)


# Plotando importancia indicador
i <- importance(mod_rand, type = 2, scale = F)

df <- data.frame(Var = row.names(i), Importancia = i[,1])

fig2 <- ggplot(df, aes(x = reorder(Var, Importancia), y = Importancia)) +
  geom_bar(stat = "identity", fill = "#53cfff", width = 0.65) +
  labs(title="Importância Indicador de Atraso",
       x = "",
       y = 'Importância')+
  coord_flip() + 
  theme_bw() 

fig2

