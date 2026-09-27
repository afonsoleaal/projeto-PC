# AgarioLike - Jogo Multiplayer Cliente/Servidor

Este projeto consiste no desenvolvimento de um jogo multiplayer inspirado no Agar.io. A arquitetura divide-se num servidor construído em Erlang (para gestão concorrente de salas, jogadores, matchmaking e pontuações) e um cliente gráfico desenvolvido em Java.

## Identificação

**Universidade:** Universidade do Minho
**Unidade Curricular:** Programação Concorrente (PC)
**Ano Letivo:** 2025/2026

### Autores

| Nome | Número |
|:--- |:--- |
| Vasco Ferreira Leite | A108399 |
| Gustavo da Silva Faria | A108575 |
| Afonso Henrique Cerqueira Leal | A108472 |

## Enunciado do Projeto

O objetivo deste projeto é que os alunos desenvolvam uma aplicação cliente/servidor que demonstre a aplicação prática de conceitos de programação concorrente.

O servidor (Erlang) deve ser capaz de aceitar múltiplas ligações TCP em simultâneo, gerir sessões de jogadores, tratar do matchmaking em diferentes salas de jogo e garantir a consistência do estado partilhado (pontuações, posições) utilizando o modelo de atores. O cliente (Java) conecta-se ao servidor para interagir e renderizar o estado do jogo em tempo real.

## Como Executar

### Pré-requisitos

Para executar este projeto, é necessário ter instalado:

* **Erlang/OTP** (para compilar e correr o Servidor)

* **Java Development Kit (JDK)** (para compilar e correr o Cliente)

### Utilização

**1. Iniciar o Servidor (Erlang):**
Abra o terminal na pasta `Server` e utilize o script de inicialização disponibilizado:

```
cd Server
./start.sh

```

**2. Iniciar o Cliente (Java):**

```
javac GameApp.java
java GameApp

```
