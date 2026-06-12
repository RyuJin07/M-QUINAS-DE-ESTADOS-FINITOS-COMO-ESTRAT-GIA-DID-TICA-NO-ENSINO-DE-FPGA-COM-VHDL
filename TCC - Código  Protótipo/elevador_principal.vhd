library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pacote_elevador.all;

entity elevador_principal is
    port (
        CLOCK_50 : in  std_logic;

        -- KEY(0): reset ativo em 0
        -- KEY(1): barreira/obstrução da porta, ativo em 0, conforme uso original com KEY
        KEY      : in  std_logic_vector(1 downto 0);

        -- SW(0..3): chamadas internas dos andares 0..3
        -- SW(4..7): chamadas externas dos andares 0..3
        -- SW(8): excesso de peso
        -- SW(9): emergência
        SW       : in  std_logic_vector(9 downto 0);

        -- Sensores reais de andar do protótipo
        sum      : in  std_logic;  -- andar 0 / térreo
        sdois    : in  std_logic;  -- andar 1
        stres    : in  std_logic;  -- andar 2
        squatro  : in  std_logic;  -- andar 3

        -- Sensores reais de fim de curso da porta
        saberta  : in  std_logic;  -- porta totalmente aberta
        sfechada : in  std_logic;  -- porta totalmente fechada

        -- Saídas de indicação
        LEDR     : out std_logic_vector(9 downto 0);
        HEX0     : out std_logic_vector(6 downto 0);
        HEX2     : out std_logic_vector(6 downto 0);
        HEX3     : out std_logic_vector(6 downto 0);

        -- Atuadores reais do protótipo
        servo_pwm : out std_logic;
        motor1    : out std_logic;
        motor2    : out std_logic
    );
end entity;

architecture rtl of elevador_principal is

    -------------------------------------------------------------------------
    -- POLARIDADE DOS SENSORES
    -- Se os sensores do protótipo acenderem os LEDs quando estiverem em 0,
    -- troque as constantes abaixo de '1' para '0'.
    -------------------------------------------------------------------------
    constant NIVEL_SENSOR_ANDAR_ATIVO : std_logic := '1';
    constant NIVEL_SENSOR_PORTA_ATIVO : std_logic := '1';

    -------------------------------------------------------------------------
    -- PWM do servo. Este é o único contador do código.
    -- Ele não simula deslocamento nem espera: apenas gera o sinal elétrico
    -- necessário para o servo, reaproveitando os valores do código simples.
    -------------------------------------------------------------------------
    constant PERIODO_SERVO       : natural := 1_000_000; -- 20 ms em 50 MHz
    constant PULSO_PORTA_ABERTA  : natural := 51_389;    -- aproximadamente 5 graus
    constant PULSO_PORTA_FECHADA : natural := 98_611;    -- aproximadamente 175 graus

    signal contador_servo : natural range 0 to PERIODO_SERVO - 1 := 0;
    signal largura_servo  : natural range 0 to PERIODO_SERVO := PULSO_PORTA_FECHADA;
    signal servo_abre     : std_logic := '0';

    -------------------------------------------------------------------------
    -- Sinais internos
    -------------------------------------------------------------------------
    signal rst_n : std_logic;

    signal chamadas_cabine   : std_logic_vector(N_ANDARES-1 downto 0);
    signal chamadas_corredor : std_logic_vector(N_ANDARES-1 downto 0);
    signal pend_int          : std_logic_vector(N_ANDARES-1 downto 0);
    signal pend_ext          : std_logic_vector(N_ANDARES-1 downto 0);
    signal pend_total_s      : std_logic_vector(N_ANDARES-1 downto 0);
    signal limpa_idx         : std_logic_vector(N_ANDARES-1 downto 0) := (others => '0');

    signal sensores_andar       : std_logic_vector(N_ANDARES-1 downto 0);
    signal sensor_porta_aberta  : std_logic;
    signal sensor_porta_fechada : std_logic;

    signal sinal_peso       : std_logic;
    signal sinal_emergencia : std_logic;
    signal sinal_barreira   : std_logic;

    signal andar_atual : andar_t := (others => '0');
    signal direcao     : direcao_t := DIR_PARADA;
    signal tem_alvo    : std_logic;
    signal alvo        : andar_t;
    signal dir_sugerida: direcao_t;

    type estado_t is (
        PARADO,
        MOVENDO,
        ABRINDO_PORTA,
        PORTA_ABERTA,
        FECHANDO_PORTA,
        EMERGENCIA
    );
    signal estado : estado_t := PARADO;

    signal status_porta_s : status_porta_t := ST_FECHADA;

    -------------------------------------------------------------------------
    -- Funções auxiliares
    -------------------------------------------------------------------------
    function ha_sensor_ativo(s : std_logic_vector) return boolean is
    begin
        for i in s'range loop
            if s(i) = '1' then
                return true;
            end if;
        end loop;
        return false;
    end function;

    function primeiro_sensor_ativo(s : std_logic_vector; padrao : natural) return natural is
    begin
        for i in 0 to N_ANDARES-1 loop
            if s(i) = '1' then
                return i;
            end if;
        end loop;
        return padrao;
    end function;

begin

    -------------------------------------------------------------------------
    -- Entradas normalizadas
    -------------------------------------------------------------------------
    rst_n <= KEY(0);

    chamadas_cabine   <= SW(3 downto 0);
    chamadas_corredor <= SW(7 downto 4);

    sinal_peso       <= SW(8);
    sinal_emergencia <= SW(9);
    sinal_barreira   <= not KEY(1);

    sensores_andar(0) <= '1' when sum     = NIVEL_SENSOR_ANDAR_ATIVO else '0';
    sensores_andar(1) <= '1' when sdois   = NIVEL_SENSOR_ANDAR_ATIVO else '0';
    sensores_andar(2) <= '1' when stres   = NIVEL_SENSOR_ANDAR_ATIVO else '0';
    sensores_andar(3) <= '1' when squatro = NIVEL_SENSOR_ANDAR_ATIVO else '0';

    sensor_porta_aberta  <= '1' when saberta  = NIVEL_SENSOR_PORTA_ATIVO else '0';
    sensor_porta_fechada <= '1' when sfechada = NIVEL_SENSOR_PORTA_ATIVO else '0';

    pend_total_s <= pend_int or pend_ext;

    -------------------------------------------------------------------------
    -- Latch de chamadas
    -------------------------------------------------------------------------
    u_latch: entity work.latch_chamadas
        generic map (N => N_ANDARES)
        port map(
            clk       => CLOCK_50,
            rst_n     => rst_n,
            botao_int => chamadas_cabine,
            botao_ext => chamadas_corredor,
            limpa_idx => limpa_idx,
            pend_int  => pend_int,
            pend_ext  => pend_ext
        );

    -------------------------------------------------------------------------
    -- Despachante
    -------------------------------------------------------------------------
    u_desp: entity work.despachante
        generic map (N => N_ANDARES)
        port map(
            andar_atual => andar_atual,
            dir_entrada => direcao,
            pend_int    => pend_int,
            pend_ext    => pend_ext,
            tem_destino => tem_alvo,
            destino     => alvo,
            dir_saida   => dir_sugerida
        );

    -------------------------------------------------------------------------
    -- PWM do servo
    -------------------------------------------------------------------------
    largura_servo <= PULSO_PORTA_ABERTA when servo_abre = '1' else PULSO_PORTA_FECHADA;

    process(CLOCK_50)
    begin
        if rising_edge(CLOCK_50) then
            if rst_n = '0' then
                contador_servo <= 0;
                servo_pwm <= '0';
            else
                if contador_servo = PERIODO_SERVO - 1 then
                    contador_servo <= 0;
                else
                    contador_servo <= contador_servo + 1;
                end if;

                if contador_servo < largura_servo then
                    servo_pwm <= '1';
                else
                    servo_pwm <= '0';
                end if;
            end if;
        end if;
    end process;

    -------------------------------------------------------------------------
    -- Motor DC do protótipo
    -- Tabela reaproveitada do controle_sistema.vhd:
    -- DIR_PARADA : motor1='1', motor2='1'
    -- DIR_SOBE   : motor1='1', motor2='0'
    -- DIR_DESCE  : motor1='0', motor2='1'
    -------------------------------------------------------------------------
    motor1 <= '1' when (direcao = DIR_PARADA or direcao = DIR_SOBE) else '0';
    motor2 <= '0' when (direcao = DIR_SOBE) else '1';

    -------------------------------------------------------------------------
    -- Status da porta e posição do servo, sem espera por tempo.
    -------------------------------------------------------------------------
    servo_abre <= '1' when (estado = ABRINDO_PORTA or estado = PORTA_ABERTA) else '0';

    status_porta_s <= ST_ABRINDO  when estado = ABRINDO_PORTA else
                      ST_ABERTA   when estado = PORTA_ABERTA else
                      ST_FECHANDO when estado = FECHANDO_PORTA else
                      ST_FECHADA;

    -------------------------------------------------------------------------
    -- Indicadores de depuração
    -- LEDR0..3: sensores reais dos andares
    -- LEDR4: motor subindo
    -- LEDR5: motor descendo
    -- LEDR6: sensor de porta fechada
    -- LEDR7: sensor de porta aberta
    -- LEDR8: excesso de peso
    -- LEDR9: emergência
    -------------------------------------------------------------------------
    LEDR(3 downto 0) <= sensores_andar;
    LEDR(4) <= '1' when direcao = DIR_SOBE  else '0';
    LEDR(5) <= '1' when direcao = DIR_DESCE else '0';
    LEDR(6) <= sensor_porta_fechada;
    LEDR(7) <= sensor_porta_aberta;
    LEDR(8) <= sinal_peso;
    LEDR(9) <= sinal_emergencia;

    HEX0 <= decodifica_7seg(to_unsigned(14, 4)) when estado = EMERGENCIA else
            decodifica_7seg(resize(andar_atual, 4));

    HEX2 <= hex_porta(status_porta_s);
    HEX3 <= hex_dir(direcao);

    -------------------------------------------------------------------------
    -- Máquina principal 100% por sensores para movimento e porta.
    -- Não há contador de viagem entre andares.
    -- Não há contador de permanência da porta aberta.
    -- A cabine só reconhece andar quando sum/sdois/stres/squatro acionam.
    -- A porta só muda de etapa quando saberta/sfechada acionam.
    -------------------------------------------------------------------------
    process(CLOCK_50)
        variable existe_sensor : boolean;
        variable idx_sensor    : natural range 0 to N_ANDARES-1;
        variable pend_total_v  : std_logic_vector(N_ANDARES-1 downto 0);
    begin
        if rising_edge(CLOCK_50) then
            limpa_idx <= (others => '0');

            existe_sensor := ha_sensor_ativo(sensores_andar);
            idx_sensor    := primeiro_sensor_ativo(sensores_andar, to_integer(andar_atual));
            pend_total_v  := pend_int or pend_ext;

            if rst_n = '0' then
                estado <= PARADO;
                direcao <= DIR_PARADA;
                andar_atual <= (others => '0');

            elsif sinal_emergencia = '1' then
                estado <= EMERGENCIA;
                direcao <= DIR_PARADA;

            else
                -- Atualização do andar atual somente por sensor físico.
                if existe_sensor then
                    andar_atual <= to_unsigned(idx_sensor, andar_atual'length);
                end if;

                case estado is

                    when EMERGENCIA =>
                        direcao <= DIR_PARADA;
                        if sinal_emergencia = '0' then
                            estado <= PARADO;
                        end if;

                    when PARADO =>
                        direcao <= DIR_PARADA;

                        -- Se a porta não está fisicamente fechada, fecha antes de qualquer movimento.
                        if sensor_porta_fechada = '0' then
                            estado <= FECHANDO_PORTA;

                        -- Pedido no andar atual: atende sem movimentar.
                        elsif existe_sensor and pend_total_v(idx_sensor) = '1' then
                            limpa_idx(idx_sensor) <= '1';
                            estado <= ABRINDO_PORTA;

                        -- Movimento só começa com porta fechada, sem peso excedido e com destino válido.
                        elsif tem_alvo = '1' and sinal_peso = '0' then
                            if dir_sugerida = DIR_SOBE then
                                direcao <= DIR_SOBE;
                                estado <= MOVENDO;
                            elsif dir_sugerida = DIR_DESCE then
                                direcao <= DIR_DESCE;
                                estado <= MOVENDO;
                            end if;
                        end if;

                    when MOVENDO =>
                        -- Segurança: qualquer falha corta o motor.
                        if sensor_porta_fechada = '0' or sinal_peso = '1' then
                            direcao <= DIR_PARADA;
                            estado <= PARADO;

                        -- Chegou fisicamente a um andar solicitado.
                        elsif existe_sensor and pend_total_v(idx_sensor) = '1' then
                            direcao <= DIR_PARADA;
                            limpa_idx(idx_sensor) <= '1';
                            estado <= ABRINDO_PORTA;

                        -- Continua até algum sensor de andar solicitado ser detectado.
                        elsif tem_alvo = '1' then
                            if dir_sugerida = DIR_SOBE then
                                direcao <= DIR_SOBE;
                            elsif dir_sugerida = DIR_DESCE then
                                direcao <= DIR_DESCE;
                            else
                                direcao <= DIR_PARADA;
                                estado <= PARADO;
                            end if;
                        else
                            direcao <= DIR_PARADA;
                            estado <= PARADO;
                        end if;

                    when ABRINDO_PORTA =>
                        direcao <= DIR_PARADA;
                        -- A abertura termina somente pelo sensor saberta.
                        if sensor_porta_aberta = '1' then
                            estado <= PORTA_ABERTA;
                        end if;

                    when PORTA_ABERTA =>
                        direcao <= DIR_PARADA;
                        -- Sem temporizador: assim que a porta estiver aberta e não houver bloqueio,
                        -- o comando passa para fechamento. Se houver peso/obstrução, mantém aberta.
                        if sinal_peso = '0' and sinal_barreira = '0' then
                            estado <= FECHANDO_PORTA;
                        end if;

                    when FECHANDO_PORTA =>
                        direcao <= DIR_PARADA;
                        -- Se houver obstrução ou excesso de peso, volta a abrir.
                        if sinal_barreira = '1' or sinal_peso = '1' then
                            estado <= ABRINDO_PORTA;
                        -- O fechamento termina somente pelo sensor sfechada.
                        elsif sensor_porta_fechada = '1' then
                            estado <= PARADO;
                        end if;

                end case;
            end if;
        end if;
    end process;

end architecture;
