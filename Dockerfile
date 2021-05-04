FROM mcr.microsoft.com/azure-cli:2.9.1

RUN apk add --update nodejs nodejs-npm
RUN az aks install-cli

WORKDIR /app

COPY ./package*.json .
RUN npm install

COPY . .
RUN npm install -g

# Create a group and user
RUN addgroup -S boxboat && adduser -S boxboat -G boxboat
USER boxboat