library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pacote_elevador.all;

entity elevador_principal is
    port (
        -- Batimento do sistema (PIN_P11). Sincroniza todas as ações da placa.
        CLOCK_50 : in std_logic;
        
        -- Botões de pressão. 
        -- KEY[0] é o Reset: limpa a memória e volta ao térreo (PIN_B8).
        KEY      : in std_logic_vector(0 downto 0);
        
        -- Chaves deslizantes (Switches). 
        -- SW[0] a SW[7] são os botões dos andares (PIN_C10 ao PIN_A14).
        SW       : in std_logic_vector(7 downto 0);
        
        -- Luzes indicadoras (Monitoramento em tempo real)
        LEDR     : out std_logic_vector(7 downto 0);
        
        -- Visor 0: Indica o número do andar atual (PIN_C14 até PIN_C17).
        HEX0     : out std_logic_vector(6 downto 0);
        
        -- Visor 2: Indica o status da porta (PIN_B20 até PIN_B22).
        HEX2     : out std_logic_vector(6 downto 0); 
        
        -- Visor 3: Indica a direção (Seta de subida ou descida) (PIN_F21 até PIN_E17).
        HEX3     : out std_logic_vector(6 downto 0)  
    );
end entity;

architecture rtl of elevador_principal is
    -- Sinais internos para ligar os diferentes blocos do projeto.
    signal rst_n : std_logic;
    signal chamadas_cabine, chamadas_corredor : std_logic_vector(N_ANDARES-1 downto 0);
    signal pend_int, pend_ext, limpa_idx : std_logic_vector(N_ANDARES-1 downto 0);
    
    -- Estados da máquina que controla o comportamento global do elevador.
    type estado_principal_t is (PARADO, MOVIMENTO, CHEGADA_ABRE);
    signal estado : estado_principal_t := PARADO;
    
    signal andar_atual : andar_t := (others=> '0');
    signal direcao : direcao_t := DIR_PARADA;
    signal tem_alvo, pulso_chegada, porta_concluida, porta_aberta, sinal_porta_mov : std_logic := '0';
    signal alvo : andar_t;
    signal dir_sugerida : direcao_t;
    signal status_porta_s : status_porta_t;
    
    -- Cronômetro para tempo de viagem (3s).
    constant PULSOS_MOVIMENTO : natural := 50_000_000 * 3;
    signal contagem_mov : unsigned(31 downto 0) := (others=> '0');
begin
    -- Ligação física dos pinos da placa às variáveis lógicas do sistema.
    rst_n <= KEY(0);
    chamadas_cabine <= SW(3 downto 0);
    chamadas_corredor <= SW(7 downto 4);
    
    -- Controle das luzes vermelhas para monitoramento em tempo real.
    LEDR(3 downto 0) <= pend_int or pend_ext; 
    LEDR(5 downto 4) <= "01" when direcao=DIR_SOBE else "10" when direcao=DIR_DESCE else "00";
    LEDR(6) <= porta_aberta;
    LEDR(7) <= sinal_porta_mov;
    
    -- Envio dos dados para os conversores de imagem dos visores.
    HEX0 <= decodifica_7seg(resize(andar_atual, 4));
    HEX2 <= hex_porta(status_porta_s);
    HEX3 <= hex_dir(direcao);

    -- Módulo de Memória: anota os cliques nos botões.
    u_latch: entity work.latch_chamadas port map(
        clk => CLOCK_50, rst_n => rst_n, botao_int => chamadas_cabine, 
        botao_ext => chamadas_corredor, limpa_idx => limpa_idx, pend_int => pend_int, pend_ext => pend_ext
    );

    -- Módulo Despachante: o cérebro que calcula a rota.
    u_desp: entity work.despachante port map(
        andar_atual => andar_atual, dir_entrada => direcao, 
        pend_int => pend_int, pend_ext => pend_ext, tem_destino => tem_alvo, 
        destino => alvo, dir_saida => dir_sugerida
    );

    -- Módulo Porta: controla o motor e o tempo da porta.
    u_porta: entity work.fsm_porta port map(
        clk => CLOCK_50, rst_n => rst_n, chegada => pulso_chegada, 
        porta_aberta => porta_aberta, porta_movimento => sinal_porta_mov, 
        status_porta => status_porta_s, ciclo_concluido => porta_concluida
    );

    -- Processo de Decisão: coordena as ações a cada batida do ritmo (Clock).
    process (CLOCK_50)
        variable a_atual, a_alvo : natural;
        variable pend_total : std_logic_vector(N_ANDARES-1 downto 0);
    begin
        if rising_edge(CLOCK_50) then
            -- Limpeza de sinais temporários para o próximo ciclo.
            pulso_chegada <= '0'; limpa_idx <= (others=> '0');
            
            -- Lógica de Reinício: volta ao estado inicial se o botão for pressionado.
            if rst_n='0' then
                estado <= PARADO; andar_atual <= (others=> '0'); direcao <= DIR_PARADA; contagem_mov <= (others=> '0');
            else
                a_atual := to_integer(andar_atual);
                a_alvo := to_integer(alvo);
                
                -- Agrupa pedidos de passageiros.
                pend_total := pend_int or pend_ext;
                
                case estado is
                    when PARADO =>
                        direcao <= DIR_PARADA; contagem_mov <= (others=> '0');
                        
                        -- Abre a porta se houver pedido no andar atual.
                        if pend_total(a_atual)='1' then
                            limpa_idx(a_atual) <= '1'; pulso_chegada <= '1'; estado <= CHEGADA_ABRE;
                            
                        -- Inicia o motor se o cérebro calculou um alvo.
                        elsif tem_alvo='1' then
                            direcao <= dir_sugerida; estado <= MOVIMENTO;
                        end if;
                        
                    when MOVIMENTO =>
                        if tem_alvo = '0' then
                            estado <= PARADO; direcao <= DIR_PARADA; contagem_mov <= (others=> '0');
                            
                        -- Para no andar se houver pedido nele.
                        elsif pend_total(a_atual) = '1' then
                            limpa_idx(a_atual) <= '1'; pulso_chegada <= '1'; estado <= CHEGADA_ABRE;
                        else
                            -- Controla o tempo (3s) para passar entre andares adjacentes.
                            if contagem_mov = to_unsigned(PULSOS_MOVIMENTO, contagem_mov'length) then
                                contagem_mov <= (others=>'0');
                                if a_atual < a_alvo then 
                                    andar_atual <= to_unsigned(a_atual+1, andar_atual'length); direcao <= DIR_SOBE;
                                elsif a_atual > a_alvo then 
                                    andar_atual <= to_unsigned(a_atual-1, andar_atual'length); direcao <= DIR_DESCE; 
                                end if;
                            else 
                                contagem_mov <= contagem_mov + 1; 
                            end if;
                        end if;
                        
                    when CHEGADA_ABRE =>
                        -- Espera o ciclo de porta terminar antes de liberar o sistema para novas ações.
                        if porta_concluida='1' then 
                            estado <= PARADO; direcao <= DIR_PARADA; 
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;