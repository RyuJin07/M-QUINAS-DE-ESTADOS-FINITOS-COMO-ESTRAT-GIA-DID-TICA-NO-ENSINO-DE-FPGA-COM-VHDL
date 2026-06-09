library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pacote_elevador.all;

entity elevador_principal is
    port (
        -- Batimento do sistema (PIN_P11). Sincroniza todas as ações da placa.
        CLOCK_50     : in std_logic;                               
        
        -- Botões de pressão da Placa. 
        -- KEY[0] é o Reset: limpa a memória e volta ao térreo (PIN_B8).
        -- KEY[1] é o sensor de barreira da porta (PIN_A7).
        KEY          : in std_logic_vector(1 downto 0);          
        
        -- Chaves deslizantes (Switches). 
        -- SW[0] a SW[3] são os botões internos da cabine.
        -- SW[8] é o sensor de excesso de peso (PIN_B14).
        -- SW[9] é o botão de emergência (PIN_F15).
        SW           : in std_logic_vector(9 downto 0);          
        
        -- Sensores de Andar (PIN_V10, PIN_V9, PIN_W5, PIN_AA14)
        SENSOR_ANDAR : in std_logic_vector(3 downto 0);
        
        -- Sensores Fim de Curso Porta: Aberta (PIN_AB11) e Fechada (PIN_AB10)
        SENSOR_PORTA : in std_logic_vector(1 downto 0);
        
        -- Botões Externos Corredor: PIN_Y7, PIN_Y8, PIN_AA10, PIN_W11
        BOTAO_EXT    : in std_logic_vector(3 downto 0);
        
        -- Saída para a Ponte H do Motor DC (PIN_AB13, PIN_Y11)
        MOTOR_DC     : out std_logic_vector(1 downto 0);
        
        -- Saída PWM para o Servomotor da Porta (PIN_AB2)
        SERVO_PWM    : out std_logic;
        
        -- Luzes indicadoras (PIN_A8 a PIN_B11) e Visores (HEX0, HEX2, HEX3).
        LEDR         : out std_logic_vector(9 downto 0);         
        HEX0         : out std_logic_vector(6 downto 0);
        HEX2         : out std_logic_vector(6 downto 0); 
        HEX3         : out std_logic_vector(6 downto 0)  
    );
end entity;

architecture rtl of elevador_principal is
    -- Sinais internos para comunicação entre módulos.
    signal rst_n : std_logic;
    signal chamadas_cabine : std_logic_vector(N_ANDARES-1 downto 0);
    signal pend_int, pend_ext, limpa_idx : std_logic_vector(N_ANDARES-1 downto 0);
    
    -- Inversores de sinal lógico (Transformam o Active-Low da maquete em Active-High)
    signal sensor_andar_int : std_logic_vector(3 downto 0);
    signal botao_ext_int    : std_logic_vector(3 downto 0);
    signal fim_porta_aberta, fim_porta_fechada : std_logic;
    
    type estado_principal_t is (PARADO, MOVIMENTO, CHEGADA_ABRE, EMERGENCIA);
    signal estado : estado_principal_t := PARADO;
    
    signal andar_atual : andar_t := (others=> '0');
    signal direcao : direcao_t := DIR_PARADA;
    signal tem_alvo : std_logic;
    signal alvo : andar_t;
    signal dir_sugerida : direcao_t;

    -- Cronómetro de inatividade mantido.
    constant PULSOS_ESTACIONAMENTO : natural := 50_000_000 * 15;
    signal contagem_estac : unsigned(31 downto 0) := (others=> '0');
    signal chamada_estacionamento : std_logic_vector(N_ANDARES-1 downto 0) := (others => '0');

    signal pulso_chegada, porta_aberta, porta_concluida, sinal_porta_mov : std_logic := '0';
    signal status_porta_s : status_porta_t; 
    signal comando_servo_s : std_logic;
    
    signal sinal_emergencia, sinal_peso, sinal_barreira : std_logic; 

begin
    -- Ligação física dos pinos da FPGA às variáveis.
    rst_n <= KEY(0);
    chamadas_cabine <= SW(3 downto 0);
    sinal_peso <= SW(8); 
    sinal_emergencia <= SW(9); 
    sinal_barreira <= not KEY(1); 
    
    -- Tratamento Active-Low: Inverte os sinais vindos da maquete para '1' (Ativo).
    sensor_andar_int <= not SENSOR_ANDAR;
    botao_ext_int    <= not BOTAO_EXT;
    fim_porta_aberta <= not SENSOR_PORTA(1);
    fim_porta_fechada<= not SENSOR_PORTA(0);
    
    -- Lógica da Ponte H (Motor DC): Comanda a força motriz baseando-se na máquina de estados.
    MOTOR_DC <= "10" when (estado = MOVIMENTO and direcao = DIR_SOBE) else
                "01" when (estado = MOVIMENTO and direcao = DIR_DESCE) else
                "11"; -- Motor Parado / Bloqueado por inércia
    
    -- Monitores Visuais na Placa.
    LEDR(3 downto 0) <= pend_int or pend_ext; 
    LEDR(5 downto 4) <= "01" when direcao=DIR_SOBE else "10" when direcao=DIR_DESCE else "00";
    LEDR(6) <= porta_aberta; LEDR(7) <= sinal_porta_mov; LEDR(8) <= sinal_peso; LEDR(9) <= sinal_emergencia;
    
    HEX0 <= decodifica_7seg(to_unsigned(14, 4)) when estado = EMERGENCIA else decodifica_7seg(resize(andar_atual, 4));
    HEX2 <= hex_porta(status_porta_s);
    HEX3 <= hex_dir(direcao);

    -- Módulo Latch: Memória de pedidos (Cabine via SW, Corredores via Maquete).
    u_latch: entity work.latch_chamadas
        generic map (N => N_ANDARES)
        port map(
            clk => CLOCK_50, rst_n => rst_n, botao_int => chamadas_cabine, botao_ext => botao_ext_int,
            limpa_idx => limpa_idx, pend_int => pend_int, pend_ext => pend_ext
        );

    -- Módulo Despachante: Calcula a Rota.
    u_desp: entity work.despachante
        generic map (N => N_ANDARES)
        port map(
            andar_atual => andar_atual, dir_entrada => direcao, 
            pend_int => (pend_int or chamada_estacionamento), pend_ext => pend_ext, 
            tem_destino => tem_alvo, destino => alvo, dir_saida => dir_sugerida
        );

    -- Módulo Porta FSM: Controla a segurança.
    u_porta: entity work.fsm_porta
        generic map ( TEMPO_ABERTA => 50_000_000 * 5 )
        port map(
            clk => CLOCK_50, rst_n => rst_n, chegada => pulso_chegada, excesso_peso => sinal_peso, 
            sensor_barreira => sinal_barreira, sensor_fim_aberta => fim_porta_aberta, 
            sensor_fim_fechada => fim_porta_fechada, comando_servo => comando_servo_s,
            porta_aberta => porta_aberta, porta_movimento => sinal_porta_mov, 
            status_porta => status_porta_s, ciclo_concluido => porta_concluida
        );

    -- Transforma o sinal lógico do Cérebro em PWM real para o Servomotor.
    u_pwm: entity work.pwm_porta
        port map( clk => CLOCK_50, comando_abrir => comando_servo_s, servo_pwm => SERVO_PWM );

    -- Processo Principal: Cérebro Físico
    process (CLOCK_50)
        variable a_atual : natural;
        variable pend_total : std_logic_vector(N_ANDARES-1 downto 0);
    begin
        if rising_edge(CLOCK_50) then
            pulso_chegada <= '0'; limpa_idx <= (others=> '0');

            -- Lógica de Atualização Dinâmica da Cabine na Maquete
            if sensor_andar_int(0) = '1' then andar_atual <= "00";
            elsif sensor_andar_int(1) = '1' then andar_atual <= "01";
            elsif sensor_andar_int(2) = '1' then andar_atual <= "10";
            elsif sensor_andar_int(3) = '1' then andar_atual <= "11";
            end if;

            if rst_n='0' then
                estado <= PARADO; direcao <= DIR_PARADA; 
                contagem_estac <= (others=> '0'); chamada_estacionamento <= (others=> '0');
            
            elsif sinal_emergencia = '1' then
                estado <= EMERGENCIA; direcao <= DIR_PARADA; contagem_estac <= (others=> '0');
            else
                a_atual := to_integer(andar_atual);
                pend_total := pend_int or pend_ext or chamada_estacionamento; 

                case estado is
                    when EMERGENCIA =>
                        estado <= PARADO;

                    when PARADO =>
                        direcao <= DIR_PARADA;
                        
                        if (pend_int or pend_ext) /= "0000" then
                            contagem_estac <= (others => '0'); chamada_estacionamento <= (others => '0');
                        else
                            if a_atual /= 0 then
                                if contagem_estac = to_unsigned(PULSOS_ESTACIONAMENTO, contagem_estac'length) then
                                    chamada_estacionamento(0) <= '1'; 
                                else contagem_estac <= contagem_estac + 1;
                                end if;
                            else contagem_estac <= (others => '0'); 
                            end if;
                        end if;

                        if pend_total(a_atual)='1' or sinal_peso = '1' then
                            limpa_idx(a_atual) <= '1'; pulso_chegada <= '1';  
                            chamada_estacionamento(a_atual) <= '0'; 
                            estado <= CHEGADA_ABRE;   
                        elsif tem_alvo='1' and sinal_peso = '0' then
                            direcao <= dir_sugerida; estado <= MOVIMENTO;            
                        end if;

                    when MOVIMENTO =>
                        if tem_alvo = '0' then
                            estado <= PARADO; direcao <= DIR_PARADA;
                        
                        -- Lógica de Paragem Real: Para o motor IMEDIATAMENTE ao detetar o sensor físico do andar alvo.
                        elsif sensor_andar_int(a_atual) = '1' and (pend_total(a_atual) = '1' or sinal_peso = '1') then
                            limpa_idx(a_atual) <= '1'; pulso_chegada <= '1';  
                            chamada_estacionamento(a_atual) <= '0'; 
                            estado <= CHEGADA_ABRE;    
                        end if;

                    when CHEGADA_ABRE =>
                        if porta_concluida='1' then
                            estado <= PARADO; direcao <= DIR_PARADA;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;