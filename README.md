# Relógio Digital com Cronômetro (ATmega328P)

Projeto em **Assembly AVR** para Arduino Uno (ATmega328P @ 16 MHz). O firmware controla um display de 7 segmentos multiplexado de 4 dígitos, três botões, buzzer e comunicação serial, implementando relógio, cronômetro e modo de ajuste de horário.

## Funcionalidades

| Modo | Descrição |
|------|-----------|
| **1 — Relógio** | Conta o tempo continuamente (formato `MM:SS`) e envia o valor pela serial a cada segundo. |
| **2 — Cronômetro** | Contador manual com start/pause e reset. |
| **3 — Ajuste** | Permite configurar os dígitos do relógio; o dígito selecionado pisca no display. |

O botão **MODE** alterna entre os modos (1 → 2 → 3 → 1). Cada troca de modo emite um bip no buzzer.

## Hardware

### Plataforma

- Microcontrolador: **ATmega328P**
- Clock: **16 MHz** (Arduino Uno)
- Ferramentas: display 7 segmentos (4 dígitos, multiplexado), 3 push-buttons, buzzer passivo

### Pinagem

| Pino | Função |
|------|--------|
| **PB0–PB3** | Saída BCD para os segmentos do display |
| **PC0–PC3** | Seleção dos dígitos (multiplexação) |
| **PD2** | Botão **START** (interrupção externa INT0, borda de subida) |
| **PD3** | Botão **RESET** (interrupção externa INT1, borda de subida) |
| **PD4** | Botão **MODE** (PCINT20, borda detectada via Pin Change Interrupt) |
| **PD5** | Buzzer (saída) |
| **TX (PD1)** | Saída serial USART0 @ **9600 baud** |

### Formato do tempo

Os valores são armazenados em 4 bytes na SRAM, na ordem:

```
[Unidade Segundos, Dezena Segundos, Unidade Minutos, Dezena Minutos]
```

A exibição e a serial usam o formato **`MM:SS`**.

## Controles por modo

### Modo 1 — Relógio

| Botão | Ação |
|-------|------|
| MODE | Alterna para o Modo 2 |
| START | Sem efeito |
| RESET | Sem efeito |

### Modo 2 — Cronômetro

| Botão | Ação |
|-------|------|
| MODE | Alterna para o Modo 3 (zera o cronômetro ao entrar) |
| START | Inicia ou pausa a contagem (toggle) |
| RESET | Se **parado**: zera o cronômetro. Se **rodando**: apenas envia mensagem `RESET` pela serial |

### Modo 3 — Ajuste do relógio

| Botão | Ação |
|-------|------|
| MODE | Alterna para o Modo 1 |
| START | Seleciona o próximo dígito (unidade seg → dezena seg → unidade min → dezena min) |
| RESET | Incrementa o dígito selecionado |

Limites de incremento:

- Unidades (segundos e minutos): 0–9
- Dezenas (segundos e minutos): 0–5

O dígito selecionado **pisca** no display. O relógio **não avança** automaticamente enquanto estiver neste modo.

## Saída serial

Configure o monitor serial para **9600 baud, 8N1**.

Exemplos de mensagens:

```
[MODO 1] 00:00
[MODO 2] START
[MODO 2] ZERO
[MODO 3] Ajustando a unidade dos segundos
```

## Arquitetura do software

O firmware segue um modelo **orientado a flags**: as ISRs apenas sinalizam eventos, e o loop principal (`MAIN_LOOP`) processa a lógica.

```
┌─────────────────────────────────────────────────────────┐
│                    Loop principal                       │
│  FLAG_1SEC → incrementa relógio/cronômetro + serial   │
│  FLAG_START → start/pause ou seleção de dígito          │
│  FLAG_RESET → reset ou incremento de dígito            │
│  FLAG_MODE  → troca de modo                             │
└─────────────────────────────────────────────────────────┘
         ▲              ▲              ▲              ▲
         │              │              │              │
   Timer1 ISR      INT0 ISR       INT1 ISR      PCINT2 ISR
   (1 segundo)     (START)        (RESET)        (MODE)

   Timer2 ISR (~2 ms) → multiplexação do display 7 segmentos
```

### Temporizadores

| Timer | Configuração | Função |
|-------|-------------|--------|
| **Timer1** | CTC, prescaler 1024, OCR1A = 15624 | Tick de **1 segundo** |
| **Timer2** | CTC, prescaler 256, OCR2A = 125 | Multiplexação ~**2 ms** por dígito |

### Variáveis principais (SRAM)

| Variável | Descrição |
|----------|-----------|
| `MODO_ATUAL` | Modo ativo (1, 2 ou 3) |
| `VAL_REL` | Valores do relógio (4 bytes) |
| `VAL_CRON` | Valores do cronômetro (4 bytes) |
| `CRON_RODANDO` | 0 = parado, 1 = contando |
| `DIGITO_SEL` | Dígito selecionado no Modo 3 (0–3) |
| `MUX_CONT` | Índice de multiplexação (0–3) |
| `BLINK_CONT` | Controle do piscar no Modo 3 |

## Compilação e gravação

### Pré-requisitos

```bash
sudo apt install avra avrdude
```

O código inclui `m328pdef.inc` (definições do ATmega328P). Esse arquivo costuma vir com o AVR Studio / Atmel Studio. Coloque-o no mesmo diretório de `main.asm` ou informe o caminho ao montador.

### Montar

```bash
avra main.asm
```

Gera o arquivo `main.hex`.

### Gravar no Arduino Uno

Substitua `/dev/ttyACM0` pela porta serial correta:

```bash
avrdude -c arduino -p m328p -P /dev/ttyACM0 -b 115200 -U flash:w:main.hex:i
```

## Estrutura do projeto

```
projeto_relogio/
├── main.asm      # Firmware completo
└── README.md     # Este arquivo
```

## Referências de código

- **Inicialização**: configuração de I/O, USART, Timer1, Timer2 e interrupções — `RESET_START`
- **Loop principal**: processamento de flags — `MAIN_LOOP`
- **Display**: ISR de multiplexação — `TIMER2_COMPA_ISR`
- **Incremento de tempo**: lógica BCD simplificada — `ADD_TIME`
- **Serial**: formatação e envio — `SEND_FMT_TIME`, `UART_PRINT`

## Observações

- O projeto foi desenvolvido para a disciplina de **Microcontroladores (UFAL)**.
- A multiplexação do display usa seleção iniciando em **PC3** e deslocamento à direita (ver comentários em `TIMER2_COMPA_ISR`).
- Certifique-se de usar resistores limitadores nos segmentos e nos cátodos/ânodos do display, conforme o circuito montado.
