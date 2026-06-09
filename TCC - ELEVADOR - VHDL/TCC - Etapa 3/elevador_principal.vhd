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
        LEDR     : out std_logic_vector(9 downto 0); 
        
        -- Visor 0: Indica o número do andar atual (PIN_C14 até PIN_C17).
        HEX0     : out std_logic_vector(6 downto 0);
        
        -- HEX2 removido completamente: Sem a porta, o visor de status da porta não é mais necessário nesta etapa.
        
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
    -- Removido o estado CHEGADA_ABRE: O elevador agora atende o pedido instantaneamente, sem tempo de espera.
    type estado_principal_t is (PARADO, MOVIMENTO);
    signal estado : estado_principal_t := PARADO;
    
    signal andar_atual : andar_t := (others=> '0');
    signal direcao : direcao_t := DIR_PARADA;
    
    -- Cronômetro para tempo de viagem (3s).
    constant PULSOS_MOVIMENTO : natural := 50_000_000 * 3;
    signal contagem_mov : unsigned(31 downto 0) := (others=> '0');

begin
    -- Ligação física dos pinos da placa às variáveis lógicas do sistema.
    rst_n <= KEY(0);
    chamadas_cabine <= SW(3 downto 0);
    chamadas_corredor <= SW(7 downto 4);
    
    -- Controle das luzes vermelhas para monitoramento em tempo real.
    -- Trava os LEDs de 6 a 9 em zero (Sinais de Segurança e de Porta foram removidos nesta etapa)
    LEDR(9 downto 6) <= "0000";
    
    LEDR(3 downto 0) <= pend_int or pend_ext; 
    LEDR(5 downto 4) <= "01" when direcao=DIR_SOBE else "10" when direcao=DIR_DESCE else "00";
    
    -- Envio dos dados para os conversores de imagem dos visores.
    HEX0 <= decodifica_7seg(resize(andar_atual, 4));
    HEX3 <= hex_dir(direcao);

    -- Módulo de Memória: anota os cliques nos botões.
    -- Latch mantido (Memória da Etapa 3): Mesmo sem porta, o elevador precisa lembrar de todos os pedidos.
    u_latch: entity work.latch_chamadas port map(
        clk => CLOCK_50, rst_n => rst_n, botao_int => chamadas_cabine, 
        botao_ext => chamadas_corredor, limpa_idx => limpa_idx, pend_int => pend_int, pend_ext => pend_ext
    );

    -- Processo de Decisão: coordena as ações a cada batida do ritmo (Clock).
    process (CLOCK_50)
        variable a_atual : natural;
        variable pend_total : std_logic_vector(N_ANDARES-1 downto 0);
        variable alvo_encontrado : boolean;
        variable alvo_v : natural;
    begin
        if rising_edge(CLOCK_50) then
            -- Limpeza de sinais temporários para o próximo ciclo.
            limpa_idx <= (others=> '0');
            
            -- Lógica de Reinício: volta ao estado inicial se o botão for pressionado.
            if rst_n='0' then
                estado <= PARADO; andar_atual <= (others=> '0'); direcao <= DIR_PARADA; contagem_mov <= (others=> '0');
            else
                a_atual := to_integer(andar_atual);
                
                -- Agrupa pedidos de passageiros.
                pend_total := pend_int or pend_ext;
                
                -- LÓGICA DE CÉREBRO SIMPLES: Varredura sequencial (0 ao 3)
                -- Sem a inteligência do despachante, o elevador apenas olha os andares de baixo para cima 
                -- e atende o primeiro pedido que encontrar, independentemente de ser o mais perto ou o mais lógico.
                alvo_encontrado := false;
                alvo_v := 0;
                for i in 0 to N_ANDARES-1 loop
                    if pend_total(i) = '1' then
                        alvo_v := i;
                        alvo_encontrado := true;
                        exit; -- Para de procurar assim que encontrar o primeiro pedido na lista
                    end if;
                end loop;

                case estado is
                    when PARADO =>
                        direcao <= DIR_PARADA; contagem_mov <= (others=> '0');
                        
                        if pend_total(a_atual)='1' then
                            -- Limpa o pedido instantaneamente e fica pronto para agir no próximo ciclo
                            limpa_idx(a_atual) <= '1'; 
                        elsif alvo_encontrado then
                            -- Inicia o motor se o cérebro simples encontrou algum alvo.
                            if alvo_v > a_atual then 
                                direcao <= DIR_SOBE; 
                            else 
                                direcao <= DIR_DESCE; 
                            end if;
                            estado <= MOVIMENTO;
                        end if;
                        
                    when MOVIMENTO =>
                        if not alvo_encontrado then
                            estado <= PARADO; direcao <= DIR_PARADA;
                            
                        elsif pend_total(a_atual) = '1' then
                            -- Chegou no destino. Para imediatamente (A ausência da fsm_porta elimina a espera).
                            estado <= PARADO; direcao <= DIR_PARADA; 
                        else
                            -- Controla o tempo (3s) para passar entre andares adjacentes.
                            if contagem_mov = to_unsigned(PULSOS_MOVIMENTO, contagem_mov'length) then
                                contagem_mov <= (others=>'0');
                                if direcao = DIR_SOBE then 
                                    andar_atual <= andar_atual + 1;
                                else 
                                    andar_atual <= andar_atual - 1; 
                                end if;
                            else 
                                contagem_mov <= contagem_mov + 1; 
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;