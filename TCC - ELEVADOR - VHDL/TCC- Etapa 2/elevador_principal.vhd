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
        
        -- Visor 3: Indica a direção (Seta de subida ou descida) (PIN_F21 até PIN_E17).
        HEX3     : out std_logic_vector(6 downto 0)  
    );
end entity;

architecture rtl of elevador_principal is
    -- Sinais internos para ligar os diferentes blocos do projeto.
    signal rst_n : std_logic;
    
    -- Estados da máquina que controla o comportamento global do elevador.
    type estado_principal_t is (PARADO, MOVIMENTO);
    signal estado : estado_principal_t := PARADO;
    
    signal andar_atual : andar_t := (others=> '0');
    signal direcao : direcao_t := DIR_PARADA;
    
    -- O sinal pend_total agora é apenas um espelho direto da chave, sem memória.
    signal pend_total : std_logic_vector(N_ANDARES-1 downto 0);
    
    -- Cronômetro para tempo de viagem (3s).
    constant PULSOS_MOVIMENTO : natural := 50_000_000 * 3;
    signal contagem_mov : unsigned(31 downto 0) := (others=> '0');

begin
    -- Ligação física dos pinos da placa às variáveis lógicas do sistema.
    rst_n <= KEY(0);
    
    -- LÓGICA DE AMNÉSIA: O motor lê as chaves diretamente do hardware. 
    -- Como a memória (latch_chamadas) foi removida, se o usuário soltar a chave, o pedido some.
    pend_total <= SW(3 downto 0) or SW(7 downto 4);
    
    -- Controle das luzes vermelhas para monitoramento em tempo real.
    -- Trava os LEDs de 6 a 9 em zero para prevenir brilho fantasma de funções de segurança antigas.
    LEDR(9 downto 6) <= "0000";
    
    LEDR(3 downto 0) <= pend_total; 
    LEDR(5 downto 4) <= "01" when direcao=DIR_SOBE else "10" when direcao=DIR_DESCE else "00";
    
    -- Envio dos dados para os conversores de imagem dos visores.
    HEX0 <= decodifica_7seg(resize(andar_atual, 4));
    HEX3 <= hex_dir(direcao);

    -- Processo de Decisão: coordena as ações a cada batida do ritmo (Clock).
    process (CLOCK_50)
        variable a_atual : natural;
        variable alvo_encontrado : boolean;
        variable alvo_v : natural;
    begin
        if rising_edge(CLOCK_50) then
            
            -- Lógica de Reinício: volta ao estado inicial se o botão for pressionado.
            if rst_n='0' then
                estado <= PARADO; andar_atual <= (others=> '0'); direcao <= DIR_PARADA; contagem_mov <= (others=> '0');
            else
                a_atual := to_integer(andar_atual);
                
                -- O sistema verifica neste exato microssegundo se alguma chave está ativada.
                -- LÓGICA DE CÉREBRO SIMPLES: Varredura sequencial (0 ao 3).
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
                        
                        -- Se a chave estiver ativada e for para outro andar, começa a mover.
                        if alvo_encontrado and alvo_v /= a_atual then
                            if alvo_v > a_atual then 
                                direcao <= DIR_SOBE; 
                            else 
                                direcao <= DIR_DESCE; 
                            end if;
                            estado <= MOVIMENTO;
                        end if;
                        
                    when MOVIMENTO =>
                        -- A Prova da Amnésia: Se a chave for solta a meio do caminho (alvo_encontrado = falso),
                        -- ou se chegou ao andar desejado, o motor para imediatamente.
                        if not alvo_encontrado or (alvo_encontrado and alvo_v = a_atual) then
                            estado <= PARADO; direcao <= DIR_PARADA; contagem_mov <= (others=> '0');
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