# Usar a imagem base do Ubuntu
FROM ubuntu:20.04

# Definir variáveis de ambiente para evitar prompts durante a instalação de pacotes
ENV DEBIAN_FRONTEND=noninteractive

# Atualizar o apt-get e instalar dependências essenciais
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    gnupg \
    software-properties-common \
    apt-transport-https \
    jq

# Adicionar a chave e o repositório da Microsoft
RUN curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - && \
    curl https://packages.microsoft.com/config/ubuntu/20.04/prod.list > /etc/apt/sources.list.d/mssql-release.list

# Instalar o driver ODBC e as ferramentas do MSSQL
RUN apt-get update && ACCEPT_EULA=Y apt-get install -y \
    msodbcsql17 \
    unixodbc-dev \
    mssql-tools

# Adicionar o mssql-tools ao PATH globalmente
ENV PATH="$PATH:/opt/mssql-tools/bin"

# Limpar o cache do apt para reduzir o tamanho da imagem
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# Definir o diretório de trabalho
WORKDIR /usr/src/app

# Copiar os scripts e o arquivo de configuração para dentro do contêiner
COPY dump.sh ./
COPY config.json ./

# Definir permissões de execução para o script
RUN chmod +x dump.sh

# Definir o ponto de entrada para o script
ENTRYPOINT ["./dump.sh"]
