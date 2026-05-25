.include "m328pdef.inc"

; --- Definições de Memória ---
.dseg
.org 0x0100
MODO_ATUAL:     .byte 1    ; 1, 2 ou 3
VAL_REL:        .byte 4    ; Un. Seg, Dez. Seg, Un. Min, Dez. Min (Relógio)
VAL_CRON:       .byte 4    ; Un. Seg, Dez. Seg, Un. Min, Dez. Min (Cronômetro)
CRON_RODANDO:   .byte 1    ; 0 = parado, 1 = rodando
DIGITO_SEL:     .byte 1    ; 0 a 3 (Modo 3)
MUX_CONT:       .byte 1    ; Contador para multiplexação (0-3)
BLINK_CONT:     .byte 1    ; Contador para piscar dígito no Modo 3

; --- Flags para o Main Loop ---
FLAG_1SEC:      .byte 1 ;flag para aumentar 1 segundo
FLAG_START:     .byte 1 ;flag para o botão start
FLAG_RESET:     .byte 1 ;flag para o botão reset
FLAG_MODE:      .byte 1 ;flag para o botão mode

; --- Vetores de Interrupção ---
.cseg ; usa memoria flash
.org 0x0000 ; inicio do programa, ao iniciar o programa, o programa vai para o RESET_START
    rjmp RESET_START 
.org INT0addr             ; START (PD2)
    rjmp INT0_HANDLER
.org INT1addr             ; RESET (PD3)
    rjmp INT1_HANDLER
.org PCI2addr             ; MODE (PD4 via PCINT2)
    rjmp PCINT2_HANDLER
.org OC2Aaddr             ; Multiplexação (~2ms)
    rjmp TIMER2_COMPA_ISR
.org OC1Aaddr             ; 1 Segundo (CTC)
    rjmp TIMER1_COMPA_ISR

; --- Strings Serial (Flash) - Alinhadas (Pares) ---
STR_M1:    .db "[MODO 1] ", 0           ; 10 bytes
STR_M2:    .db "[MODO 2] ", 0           ; 10 bytes
STR_M3:    .db "[MODO 3] ", 0           ; 10 bytes
STR_START: .db "START", 13, 10, 0       ; 8 bytes
STR_RESET: .db "RESET", 13, 10, 0       ; 8 bytes
STR_ZERO:  .db "ZERO", 13, 10, 0, 0     ; 8 bytes
STR_A_US:  .db "Ajustando a unidade dos segundos", 13, 10, 0, 0 ; 36 bytes
STR_A_DS:  .db "Ajustando a dezena dos segundos", 13, 10, 0     ; 34 bytes
STR_A_UM:  .db "Ajustando a unidade dos minutos", 13, 10, 0     ; 34 bytes
STR_A_DM:  .db "Ajustando a dezena dos minutos", 13, 10, 0, 0   ; 34 bytes
STR_SEP:   .db ":", 0                   ; 2 bytes
STR_NL:    .db 13, 10, 0, 0             ; 4 bytes

; ================================================================================
; --- Inicialização do Sistema ---
; ================================================================================
RESET_START: ; inicio do programa
    ldi r16, high(RAMEND) ; carrega o endereço de fim da RAM na pilha
    out SPH, r16
    ldi r16, low(RAMEND) ; carrega o endereço de fim da RAM na pilha
    out SPL, r16

    ; I/O Config
    ldi r16, 0x0F ; carrega o valor 0x0F em r16
    out DDRB, r16    ; PB0-3 Saída BCD
    out DDRC, r16    ; PC0-3 Saída Seleção Dígitos
    ldi r16, (1<<PD5) ; Buzzer Saída, Outros Entrada
    out DDRD, r16
    
    ; USART Config (9600 @ 16MHz) -> UBRR = 103
    ldi r16, 103 ; carrega o valor 103 em r16
    sts UBRR0L, r16 ; carrega o valor de r16 no registrador UBRR0L
    ldi r16, (1<<TXEN0) ; carrega o valor 0x02 em r16
    sts UCSR0B, r16 ; carrega o valor de r16 no registrador UCSR0B
    ldi r16, (3<<UCSZ00) ; carrega o valor 0x06 em r16
    sts UCSR0C, r16 ; carrega o valor de r16 no registrador UCSR0C

    ; Timer1 Config (1s @ 16MHz) - CTC, Prescaler 1024
    ldi r16, high(15624) ; carrega a parte alta do valor 15624 em r16
    sts OCR1AH, r16
    ldi r16, low(15624) ; carrega a parte baixa do valor 15624 em r16
    sts OCR1AL, r16
    ldi r16, (1<<WGM12)|(1<<CS12)|(1<<CS10) ; carrega o valor 0x09 em r16
    sts TCCR1B, r16 ; carrega o valor de r16 no registrador TCCR1B
    ldi r16, (1<<OCIE1A) ; carrega o valor 0x02 em r16
    sts TIMSK1, r16 ; carrega o valor de r16 no registrador TIMSK1

    ; Timer2 Config (Multiplexação ~2ms)
    ldi r16, 125 ; carrega o valor 125 em r16
    sts OCR2A, r16 ; carrega o valor de r16 no registrador OCR2A
    ldi r16, (1<<WGM21) ; carrega o valor 0x02 em r16
    sts TCCR2A, r16 ; carrega o valor de r16 no registrador TCCR2A
    ldi r16, (1<<CS22)|(1<<CS21) ; Prescaler 256
    sts TCCR2B, r16 ; carrega o valor de r16 no registrador TCCR2B
    ldi r16, (1<<OCIE2A) ; carrega o valor 0x02 em r16
    sts TIMSK2, r16 ; carrega o valor de r16 no registrador TIMSK2

    ; Interrupções Externas
    ldi r16, (1<<ISC01)|(1<<ISC00)|(1<<ISC11)|(1<<ISC10) ; Borda subida
    sts EICRA, r16 ; carrega o valor de r16 no registrador EICRA
    ldi r16, (1<<INT0)|(1<<INT1)
    out EIMSK, r16 ; carrega o valor de r16 no registrador EIMSK
    
    ; PCINT para MODE (PD4)
    ldi r16, (1<<PCIE2) ; carrega o valor 0x02 em r16, pois precisa habilitar a interrupção para o PCINT2
    sts PCICR, r16 ; carrega o valor de r16 no registrador PCICR
    ldi r16, (1<<PCINT20) ; carrega o valor 0x02 em r16, pois precisa habilitar a interrupção para o PCINT20
    sts PCMSK2, r16 ; carrega o valor de r16 no registrador PCMSK2

    ; Inicialização Variáveis e Flags
    ldi r16, 1 ; carrega o valor 1 em r16
    sts MODO_ATUAL, r16 ; carrega o valor de r16 no registrador MODO_ATUAL
    clr r16 ; limpa o registrador r16
    sts CRON_RODANDO, r16 ; inicializa o cronômetro como parado
    sts DIGITO_SEL, r16 ; inicializa o dígito selecionado como 0
    sts FLAG_1SEC, r16 ; inicializa a flag de 1 segundo como 0
    sts FLAG_START, r16 ; inicializa a flag de start como 0
    sts FLAG_RESET, r16 ; inicializa a flag de reset como 0
    sts FLAG_MODE, r16 ; inicializa a flag de mode como 0
    sei ; habilita as interrupções

; ================================================================================
; --- Loop Principal (Processamento Baseado em Flags) ---
; ================================================================================
MAIN_LOOP:
    ; Verifica Flag Timer 1 (1 Segundo)
    lds r16, FLAG_1SEC ; carrega o valor do registrador FLAG_1SEC em r16
    tst r16 ; testa o valor de r16
    breq SKIP_1SEC ; se o valor de r16 for 0, pula para o SKIP_1SEC
    rjmp PROC_1SEC ; se o valor de r16 for diferente de 0, pula para o PROC_1SEC
SKIP_1SEC:
    ; Verifica Flag START
    lds r16, FLAG_START ; carrega o valor do registrador FLAG_START em r16
    tst r16 ; testa o valor de r16
    breq SKIP_START ; se o valor de r16 for 0, pula para o SKIP_START
    rjmp PROC_START ; se o valor de r16 for diferente de 0, pula para o PROC_START
SKIP_START:
    ; Verifica Flag RESET
    lds r16, FLAG_RESET ; carrega o valor do registrador FLAG_RESET em r16
    tst r16 ; testa o valor de r16
    breq SKIP_RESET ; se o valor de r16 for 0, pula para o SKIP_RESET
    rjmp PROC_RESET ; se o valor de r16 for diferente de 0, pula para o PROC_RESET
SKIP_RESET:
    ; Verifica Flag MODE
    lds r16, FLAG_MODE ; carrega o valor do registrador FLAG_MODE em r16
    tst r16 ; testa o valor de r16
    breq SKIP_MODE ; se o valor de r16 for 0, pula para o SKIP_MODE
    rjmp PROC_MODE ; se o valor de r16 for diferente de 0, pula para o PROC_MODE
SKIP_MODE:
    ; se nenhuma flag foi ativada, pula para o MAIN_LOOP
    rjmp MAIN_LOOP

; --- Processa Flag de 1 Segundo ---
PROC_1SEC: ; processa a flag de 1 segundo
    clr r16 ; limpa o registrador r16
    sts FLAG_1SEC, r16 ; limpa a flag de 1 segundo

    lds r16, MODO_ATUAL ; carrega o valor do registrador MODO_ATUAL em r16
    cpi r16, 3 ; compara o valor de r16 com 3
    breq chk_cr_1sec  ; se o valor de r16 for 3, pula para o chk_cr_1sec
    
    rcall INC_REL ; incrementa o relógio
    lds r16, MODO_ATUAL ; carrega o valor do registrador MODO_ATUAL em r16
    cpi r16, 1 ; compara o valor de r16 com 1
    breq chk_cr_1sec ; se o valor de r16 for 1, pula para o chk_cr_1sec
    rcall SEND_TIME_REL ; envia o tempo do relógio

    rjmp MAIN_LOOP ; pula para o MAIN_LOOP

chk_cr_1sec: ;
    lds r16, MODO_ATUAL ; carrega o valor do registrador MODO_ATUAL em r16
    cpi r16, 2 ; compara o valor de r16 com 2
    brne ml_out1 ; se o valor de r16 for diferente de 2, pula para o ml_out1
    lds r16, CRON_RODANDO ; carrega o valor do registrador CRON_RODANDO em r16
    tst r16 ; testa o valor de r16
    breq ml_out1 ; se o valor de r16 for 0, pula para o ml_out1
    rcall INC_CRON ; incrementa o cronômetro
    rcall SEND_TIME_CRON ; envia o tempo do cronômetro
ml_out1:
    rjmp MAIN_LOOP ; pula para o MAIN_LOOP

; --- Processa Flag START (INT0) ---
PROC_START: ; processa a flag de start
    clr r16 ; limpa o registrador r16
    sts FLAG_START, r16 ; limpa a flag de start
    rcall DEBOUNCE ; debounce do botão start, espera para evitar falsos clicks
    
    lds r16, MODO_ATUAL ; carrega o valor do registrador MODO_ATUAL em r16
    cpi r16, 2 ; compara o valor de r16 com 2
    breq start_c_logic ; se o valor de r16 for 2, pula para o start_c_logic
    cpi r16, 3 ; compara o valor de r16 com 3
    breq next_d_logic ; se o valor de r16 for 3, pula para o next_d_logic
    rjmp MAIN_LOOP ; pula para o MAIN_LOOP

start_c_logic: ; processa a lógica do start no cronômetro
    rcall BIP ; bip do buzzer
    lds r16, CRON_RODANDO ; carrega o valor do registrador CRON_RODANDO em r16
    ldi r17, 1 ; carrega o valor 1 em r17
    eor r16, r17 ; inverte o valor de r16
    sts CRON_RODANDO, r16 ; carrega o valor de r16 no registrador CRON_RODANDO
    ldi ZH, high(STR_M2 << 1) ; carrega a parte alta do endereço da string STR_M2 em ZH
    ldi ZL, low(STR_M2 << 1) ; carrega a parte baixa do endereço da string STR_M2 em ZL
    rcall UART_PRINT ; envia a string STR_M2 pela serial
    ldi ZH, high(STR_START << 1) ; carrega a parte alta do endereço da string STR_START em ZH
    ldi ZL, low(STR_START << 1) ; carrega a parte baixa do endereço da string STR_START em ZL
    rcall UART_PRINT ; envia a string STR_START pela serial
    rjmp MAIN_LOOP ; pula para o MAIN_LOOP

next_d_logic: ; processa a lógica do next no dígito
    lds r16, DIGITO_SEL ; carrega o valor do registrador DIGITO_SEL em r16
    inc r16 ; incrementa o valor de r16
    andi r16, 0x03 ; aplica a máscara 0x03 em r16
    sts DIGITO_SEL, r16 ; carrega o valor de r16 no registrador DIGITO_SEL
    rcall SEND_MSG_AJUSTE ; envia a mensagem de ajuste
    rjmp MAIN_LOOP ; pula para o MAIN_LOOP

; --- Processa Flag RESET (INT1) ---
PROC_RESET: ; processa a flag de reset
    clr r16
    sts FLAG_RESET, r16 ; limpa a flag de reset
    rcall DEBOUNCE ; debounce do botão reset, espera para evitar falsos clicks

    lds r16, MODO_ATUAL ; carrega o valor do registrador MODO_ATUAL em r16
    cpi r16, 2 ; compara o valor de r16 com 2
    breq reset_c_logic ; se o valor de r16 for 2, pula para o reset_c_logic
    cpi r16, 3 ; compara o valor de r16 com 3
    breq inc_d_logic ; se o valor de r16 for 3, pula para o inc_d_logic
    rjmp MAIN_LOOP ; pula para o MAIN_LOOP

reset_c_logic: ; processa a lógica do reset no cronômetro
    rcall BIP ; chama o BIP
    lds r16, CRON_RODANDO ; carrega o valor do registrador CRON_RODANDO em r16
    tst r16 ; testa o valor de r16
    brne rst_msg_only ; se o valor de r16 for diferente de 0, pula para o rst_msg_only
    ldi ZH, high(VAL_CRON) ; carrega a parte alta do endereço da string VAL_CRON em ZH
    ldi ZL, low(VAL_CRON) ; carrega a parte baixa do endereço da string VAL_CRON em ZL
    clr r17 ; limpa o registrador r17
    st Z+, r17 ; carregar valor 0 em Z+ e incrementar Z
    st Z+, r17 ; carregar valor 0 em Z+ e incrementar Z
    st Z+, r17 ; carregar valor 0 em Z+ e incrementar Z
    st Z, r17 ; carregar valor 0 em Z
    ldi ZH, high(STR_M2 << 1) ; carrega a parte alta do endereço da string STR_M2 em ZH
    ldi ZL, low(STR_M2 << 1) ; carrega a parte baixa do endereço da string STR_M2 em ZL
    rcall UART_PRINT ; envia a string STR_M2 pela serial
    ldi ZH, high(STR_ZERO << 1) ; carrega a parte alta do endereço da string STR_ZERO em ZH
    ldi ZL, low(STR_ZERO << 1) ; carrega a parte baixa do endereço da string STR_ZERO em ZL
    rcall UART_PRINT ; envia a string STR_ZERO pela serial
    rjmp MAIN_LOOP ; pula para o MAIN_LOOP

rst_msg_only: ; processa a lógica do reset no cronômetro
    ldi ZH, high(STR_M2 << 1) ; carrega a parte alta do endereço da string STR_M2 em ZH
    ldi ZL, low(STR_M2 << 1) ; carrega a parte baixa do endereço da string STR_M2 em ZL
    rcall UART_PRINT ; envia a string STR_M2 pela serial
    ldi ZH, high(STR_RESET << 1) ; carrega a parte alta do endereço da string STR_RESET em ZH
    ldi ZL, low(STR_RESET << 1) ; carrega a parte baixa do endereço da string STR_RESET em ZL
    rcall UART_PRINT ; envia a string STR_RESET pela serial
    rjmp MAIN_LOOP ; pula para o MAIN_LOOP

inc_d_logic: ; processa a lógica do incremento no dígito
    lds r17, DIGITO_SEL
    ldi ZH, high(VAL_REL) ; carrega a parte alta do endereço da string VAL_REL em ZH
    ldi ZL, low(VAL_REL) ; carrega a parte baixa do endereço da string VAL_REL em ZL
    add ZL, r17 ; adiciona o valor de r17 a ZL
    clr r16 ; limpa o registrador r16
    adc ZH, r16 ; adiciona o valor de r16 a ZH
    ld r18, Z ; carrega o valor de Z em r18
    inc r18 ; incrementa o valor de r18
    cpi r17, 1 ; compara o valor de r17 com 1
    breq lim_6 ; se o valor de r17 for 1, pula para o lim_6
    cpi r17, 3 ; compara o valor de r17 com 3
    breq lim_6 ; se o valor de r17 for 3, pula para o lim_6
    cpi r18, 10 ; compara o valor de r18 com 10
    brne save_digit ; se o valor de r18 for diferente de 10, pula para o save_digit
    clr r18 ; limpa o registrador r18
    rjmp save_digit ; pula para o save_digit
lim_6: ; processa a lógica do limite 6
    cpi r18, 6 ; compara o valor de r18 com 6
    brne save_digit ; se o valor de r18 for diferente de 6, pula para o save_digit
    clr r18 ; limpa o registrador r18
save_digit: ; processa a lógica do save_digit
    st Z, r18 ; carrega o valor de r18 em Z
    rjmp MAIN_LOOP ; pula para o MAIN_LOOP

; --- Processa Flag MODE (PCINT2) ---
PROC_MODE: ; processa a flag de mode
    clr r16 ; limpa o registrador r16
    sts FLAG_MODE, r16 ; limpa a flag de mode
    rcall DEBOUNCE ; debounce do botão mode, espera para evitar falsos clicks
    rcall BIP ; bip
    
    lds r16, MODO_ATUAL ; carrega o valor do registrador MODO_ATUAL em r16
    inc r16 ; incrementa o valor de r16
    cpi r16, 4 ; compara o valor de r16 com 4
    brne m_switched ; se o valor de r16 for diferente de 4, pula para o m_switched
    ldi r16, 1 ; carrega o valor 1 em r16
m_switched: ; processa a lógica do m_switched
    sts MODO_ATUAL, r16 ; carrega o valor de r16 no registrador MODO_ATUAL
    cpi r16, 2 ; compara o valor de r16 com 2
    breq e_mode2 ; se o valor de r16 for 2, pula para o e_mode2
    cpi r16, 3 ; compara o valor de r16 com 3
    breq i_mode3 ; se o valor de r16 for 3, pula para o i_mode3
    rjmp MAIN_LOOP ; pula para o MAIN_LOOP

e_mode2: ; processa a lógica do e_mode2
    ldi ZH, high(VAL_CRON) ; carrega a parte alta do endereço da string VAL_CRON em ZH
    ldi ZL, low(VAL_CRON) ; carrega a parte baixa do endereço da string VAL_CRON em ZL
    clr r17 ; limpa o registrador r17
    st Z+, r17 ; carregar valor 0 em Z+ e incrementar Z
    st Z+, r17 ; carregar valor 0 em Z+ e incrementar Z
    st Z+, r17 ; carregar valor 0 em Z+ e incrementar Z
    st Z, r17 ; carregar valor 0 em Z
    sts CRON_RODANDO, r17 ; carrega o valor de r17 no registrador CRON_RODANDO
    ldi ZH, high(STR_M2 << 1) ; carrega a parte alta do endereço da string STR_M2 em ZH
    ldi ZL, low(STR_M2 << 1) ; carrega a parte baixa do endereço da string STR_M2 em ZL
    rcall UART_PRINT ; envia a string STR_M2 pela serial
    ldi ZH, high(STR_ZERO << 1) ; carrega a parte alta do endereço da string STR_ZERO em ZH
    ldi ZL, low(STR_ZERO << 1) ; carrega a parte baixa do endereço da string STR_ZERO em ZL
    rcall UART_PRINT ; envia a string STR_ZERO pela serial
    rjmp MAIN_LOOP ; pula para o MAIN_LOOP

i_mode3: ; processa a lógica do i_mode3
    clr r17 ; limpa o registrador r17
    sts DIGITO_SEL, r17 ; carrega o valor de r17 no registrador DIGITO_SEL
    rcall SEND_MSG_AJUSTE ; envia a mensagem de ajuste
    rjmp MAIN_LOOP ; pula para o MAIN_LOOP

; --- Interrupções (Apenas Marcam Flags e Limpam Contexto) ---

TIMER1_COMPA_ISR:

    ; Conforme visto em sala de aula, salva o contexto do SREG antes de tratar
    ; a interrupção.

    push r16
    in r16, SREG
    push r16

    ldi r16, 1
    sts FLAG_1SEC, r16    ; Seta flag de 1S para ativa - 1

    ; Restaura o contexto do SREG. 
    pop r16
    out SREG, r16
    pop r16
    reti

INT0_HANDLER:
    push r16
    in r16, SREG 
    push r16

    ldi r16, 1
    sts FLAG_START, r16 ; Seta flag do start para ativa - 1

    pop r16
    out SREG, r16
    pop r16
    reti

INT1_HANDLER:
    push r16
    in r16, SREG
    push r16

    ldi r16, 1
    sts FLAG_RESET, r16  ; Seta a flag de reset para ativa - 1

    pop r16
    out SREG, r16
    pop r16
    reti

PCINT2_HANDLER:
    push r16
    in r16, SREG
    push r16

    in r16, PIND
    sbrs r16, 4         ; processa a interrupção de PCINT apenas no pino D4
    rjmp p2_out
    ldi r16, 1
    sts FLAG_MODE, r16    ; Seta flag de mode para ativa - 
p2_out:
    pop r16
    out SREG, r16
    pop r16
    reti

; --- Interrupção Multiplexação (Timer 2) ---
TIMER2_COMPA_ISR:
    push r16
    in r16, SREG    ; Salva contexto e registradores utilizados na interrupção 
    push r16
    push r17
    push r18
    push r19
    push ZH
    push ZL

    ; Apaga todos os dígitos
    clr r16
    out PORTC, r16

    lds r17, MUX_CONT ; Carrega o elemento para ser exibido
    inc r17
    andi r17, 0x03    ; Valor circular de seleção [0,3]
    sts MUX_CONT, r17 ; Salva na memória o valor utilizado

    ; Seleciona Dados
    lds r16, MODO_ATUAL    ; Verifica os modos ( modo 3 tem tratamento especial )
    cpi r16, 2
    breq load_cron         ; Caso seja modo 2, carregue os dados do cronometro
    ldi ZH, high(VAL_REL)  ; Caso contrário, carregue os dados do relógio
    ldi ZL, low(VAL_REL)
    rjmp process_mux
load_cron:
    ldi ZH, high(VAL_CRON)
    ldi ZL, low(VAL_CRON)

process_mux:
    add ZL, r17           ; Operação com o Z (dado vetor de dados da memória referente aos dados
    clr r16               ; qual valor irá exibir)
    adc ZH, r16
    ld r18, Z

    lds r16, MODO_ATUAL  
    cpi r16, 3            ; Se o modo atual não for 3, exibe os dados
    brne display_on
    lds r16, DIGITO_SEL   ; Caso seja o modo 3, tem que tratar se o número exibido é o num selecionado para editar.
    cp r16, r17
    brne display_on
    
    lds r16, BLINK_CONT   ; Uso do contador BLINK_CONT para desligar o display ( efeito de piscar )
    inc r16
    sts BLINK_CONT, r16
    sbrc r16, 7           ; Vai desligar o display quando o bit mais significativo de BLINK_CONT for 1.
    rjmp display_off

display_on:
    out PORTB, r18
    ldi r16, 8       ; Carrega o valor para seleção da multiplexação (0b0001)
    mov r19, r17     ; R19 serve como um seletor, sendo a qtd de shitleft para chegar no elemento correto
    tst r19
    breq shift_done
shift_loop:
    lsr r16          ; Vai deslocando o display a ser exibido da direita para esquerda.
    dec r19
    brne shift_loop
shift_done:
    out PORTC, r16

display_off:
    pop ZL
    pop ZH
    pop r19
    pop r18
    pop r17
    pop r16
    out SREG, r16
    pop r16
    reti

; --- Funções Auxiliares ---
; Serve apenas para alterar o registrador Z para a exibição
INC_REL:
    ldi ZH, high(VAL_REL)    ; Carrega os dados do relógio
    ldi ZL, low(VAL_REL)
    rcall ADD_TIME
    ret

INC_CRON:
    ldi ZH, high(VAL_CRON)    ; Carrega os dados do cronometro
    ldi ZL, low(VAL_CRON)
    rcall ADD_TIME
    ret

ADD_TIME:         ; Faz o tratamento de caso para somar 1 a unidade até 10
    ld r16, Z     ; Quando chega em 10, zera o valor e soma 1 a Dezena. 
    inc r16       ; E assim segue da unidade de segundo > dezena de segundo > unidade minuto > dezena segundo
    cpi r16, 10   ; Sempre que o valor é válido, envia direto sem atualizar os demais dados.
    brne s0       ; Quando alcança o maior valor, zera o elemento e inc o próximo 
    clr r16
    st Z+, r16
    ld r16, Z
    inc r16
    cpi r16, 6
    brne s1
    clr r16
    st Z+, r16
    ld r16, Z
    inc r16
    cpi r16, 10
    brne s2
    clr r16
    st Z+, r16
    ld r16, Z
    inc r16
    cpi r16, 6
    brne s3
    clr r16
s3: st Z, r16
    ret
s2: st Z, r16
    ret
s1: st Z, r16
    ret
s0: st Z, r16
    ret

BIP:
    sbi PORTD, 5        ; Ativa o pino 5 da PORTD - buzzer
    ldi r18, 100
delay_bip:              ; Delay para ser o tempo de atuação
    ldi r19, 255
delay_inner: 
    dec r19
    brne delay_inner
    dec r18
    brne delay_bip
    cbi PORTD, 5        ; desliga o buzzer
    ret

DEBOUNCE:
    ldi r18, 50
d_loop: ldi r19, 255     ; Delay para evitar erros na entrada.
dl2: dec r19
    brne dl2
    dec r18
    brne d_loop
    ret

UART_PRINT:              ; Carrega os dados de Z até que leia 0 e encerra
    lpm r16, Z+
    tst r16
    breq up_end
wait_tx:
    lds r17, UCSR0A
    sbrs r17, UDRE0
    rjmp wait_tx        ; Enquanto enviar os dados, aguarda 
    sts UDR0, r16       ; Joga o dado no buffer
    rjmp UART_PRINT
up_end:
    ret

SEND_TIME_REL:
    ldi ZH, high(STR_M1 << 1)     ; Carrega string do modo 1
    ldi ZL, low(STR_M1 << 1)
    rcall UART_PRINT
    ldi ZH, high(VAL_REL)         ; Carrega os dados do relógio
    ldi ZL, low(VAL_REL)
    rcall SEND_FMT_TIME           ; subrotina para enviar msg
    ret

SEND_TIME_CRON:
    ldi ZH, high(STR_M2 << 1)
    ldi ZL, low(STR_M2 << 1)
    rcall UART_PRINT
    ldi ZH, high(VAL_CRON)
    ldi ZL, low(VAL_CRON)
    rcall SEND_FMT_TIME
    ret

SEND_FMT_TIME: 
    movw Y, Z                ; Move os 2 bytes de Z para o Y
    ldd r16, Y+3             ; Pega os dados da dezena minuto
    rcall UART_SEND_DIGIT
    ldd r16, Y+2             ; pega os dados da unidade minuto
    rcall UART_SEND_DIGIT
    ldi ZH, high(STR_SEP << 1) 
    ldi ZL, low(STR_SEP << 1)
    rcall UART_PRINT
    ldd r16, Y+1            ; pega dados dezena segundos
    rcall UART_SEND_DIGIT
    ldd r16, Y+0            ; pega dados da unidade segundos
    rcall UART_SEND_DIGIT
    ldi ZH, high(STR_NL << 1) 
    ldi ZL, low(STR_NL << 1)
    rcall UART_PRINT
    ret

UART_SEND_DIGIT:
    subi r16, -'0'            ; Cast para obter o valor da string correspondete na tabela ASCII
wait_tx_d:
    lds r17, UCSR0A 
    sbrs r17, UDRE0
    rjmp wait_tx_d
    sts UDR0, r16
    ret

SEND_MSG_AJUSTE:                    ; Identifica qual modo está e envia a msg de 
    ldi ZH, high(STR_M3 << 1)       ; ajuste correspondente
    ldi ZL, low(STR_M3 << 1)        ; [modo 3] msg padrão
    rcall UART_PRINT
    lds r16, DIGITO_SEL
    cpi r16, 0                      ; A seleção da msg é feita nessa comparação
    breq am0
    cpi r16, 1
    breq am1
    cpi r16, 2
    breq am2
    ldi ZH, high(STR_A_DM << 1)
    ldi ZL, low(STR_A_DM << 1)
    rjmp am_print
am0: ldi ZH, high(STR_A_US << 1)
    ldi ZL, low(STR_A_US << 1)
    rjmp am_print
am1: ldi ZH, high(STR_A_DS << 1)
    ldi ZL, low(STR_A_DS << 1)
    rjmp am_print
am2: ldi ZH, high(STR_A_UM << 1)
    ldi ZL, low(STR_A_UM << 1)
am_print:
    rcall UART_PRINT
    ret
